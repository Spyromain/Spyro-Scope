using System;
using System.Collections;
using System.Diagnostics;
using System.Threading;

namespace SpyroScope {
	class Emulator {
		public static Emulator active;
		public static List<Emulator> emulators = new .() ~ DeleteContainerAndItems!(_);

		public Windows.ProcessHandle processHandle;
		public Windows.HModule moduleHandle; // Also contains the base address directly
		
		int emulatorIndex = -1, versionIndex = -1;

		public StringView Name { get => ProcessFound ? EmulatorsConfig.emulators[emulatorIndex].label : ""; }
		public StringView Version { get => versionIndex > -1 ? EmulatorsConfig.emulators[emulatorIndex].versions[versionIndex].label : "Unknown"; }
		public uint MainModuleSize { get; private set; }
		public bool ProcessFound { get => emulatorIndex > -1; }
		public bool Supported { get => ProcessFound && versionIndex > -1; }

		public int RAMBaseAddress;
		public int VRAMBaseAddress;

		public enum SpyroROM {
			None,
			SpyroTheDragon_NTSC_U,
			SpyroTheDragon_NTSC_J,
			SpyroTheDragon_PAL,
			RiptosRage_NTSC_U,
			RiptosRage_NTSC_J,
			RiptosRage_PAL,
			YearOfTheDragon_1_0_NTSC_U,
			YearOfTheDragon_1_1_NTSC_U,
			YearOfTheDragon_1_0_PAL,
			YearOfTheDragon_1_1_PAL
		}
		public SpyroROM rom;

		public enum SpyroInstallment {
			None,
			SpyroTheDragon,
			RiptosRage,
			YearOfTheDragon
		}
		public SpyroInstallment installment;

		public struct Address : uint32 {
			public override void ToString(String strBuffer) {
				strBuffer.AppendF("{:X8}", (uint32)this);
			}

			public bool IsNull { get => this == Null; }

			public const Address Null = 0;
		}

		public struct Address<T> : Address {
			public override void ToString(String strBuffer) {
				base.ToString(strBuffer);
			}

			public void Read(T* buffer, Emulator emulator = active) {
				emulator.ReadFromRAM(this, buffer, sizeof(T));
			}

			public void ReadArray(T* buffer, int count, Emulator emulator = active) {
				emulator.ReadFromRAM(this, buffer, sizeof(T) * count);
			}

			public void Write(T* buffer, Emulator emulator = active) {
				emulator.WriteToRAM(this, buffer, sizeof(T));
			}

			public void WriteArray(T* buffer, int count, Emulator emulator = active) {
			    emulator.WriteToRAM(this, buffer, sizeof(T) * count);
			}

			public void GetAtIndex(T* buffer, int index, Emulator emulator = active) {
			    emulator.ReadFromRAM(this + index * sizeof(T), buffer, sizeof(T));
			}

			public void SetAtIndex(T* buffer, int index, Emulator emulator = active) {
			    emulator.WriteToRAM(this + index * sizeof(T), buffer, sizeof(T));
			}

			public void ReadRange(T* buffer, int start, int count, Emulator emulator = active) {
			    emulator.ReadFromRAM(this + start * sizeof(T), buffer, count * sizeof(T));
			}

			public void WriteRange(T* buffer, int start, int count, Emulator emulator = active) {
			    emulator.WriteToRAM(this + start * sizeof(T), buffer, count * sizeof(T));
			}
		}

		public const String[8] pointerLabels = .(
			"Terrain Mesh",
			"Terrain Deform",
			"Terrain Collision",
			"Terrain Collision Flags",
			"Terrain Collision Deform",
			"Textures",
			"Texture Scrollers",
			"Texture Swappers"
		);
		public Address[8] loadedPointers;
		public bool[8] changedPointers;
		public const Address<Address>[8][11] pointerSets = .(
			sceneRegionPointers,
			farRegionDeformPointers,
			collisionDataPointers,
			collisionFlagsArrayPointers,
			collisionDeformDataPointers,
			textureDataPointers,
			textureScrollerPointers,
			textureSwapperPointers
		);

		public enum LoadingStatus {
			Idle,
			Loading,
			CutsceneDone,
			CutsceneIdle,
			Done
		}
		public LoadingStatus loadingStatus;

		// Begin Spyro games information
		
		public const Address<char8>[10] testAddresses = .((.)0x800103e7/*StD*/, 0, 0, (.)0x80066ea8/*RR*/, 0, 0, (.)0x8006c3b0, (.)0x8006c490/*YotD-1.1*/, 0, 0);
		public const String[11] gameNames = .(String.Empty, "Spyro the Dragon (NTSC-U)", "Spyro the Dragon (NTSC-J)", "Spyro the Dragon (PAL)", "Spyro: Ripto's Rage (NTSC-U)", "Spyro and Sparx: Tondemo Tours (NTSC-J)", "Spyro: Gateway to Glimmer (PAL)", "Spyro: Year of the Dragon (v1.0 NTSC-U)", "Spyro: Year of the Dragon (v1.1 NTSC-U)", "Spyro: Year of the Dragon (v1.0 PAL)", "Spyro: Year of the Dragon (v1.1 PAL)");

		public const Address<int32>[11] gameStateAddresses = .(0, (.)0x800757d8/*StD*/, 0, 0, (.)0x800681c8/*RR*/, 0, 0, (.)0x8006e344, (.)0x8006e424/*YotD-1.1*/, 0, 0);
		public const Address<int32>[11] loadStateAddresses = .(0, (.)0x80075864/*StD*/, 0, 0, (.)0x80066eec/*RR*/, 0, 0, 0, (.)0x8006c5f8/*YotD-1.1*/, 0, 0);

		public const Address<Vector3Int>[11] spyroPositionAddresses = .(0, (.)0x80078a58/*StD*/, 0, 0, (.)0x80069ff0/*RR*/, 0, 0, (.)0x80070328, (.)0x80070408/*YotD-1.1*/, 0, 0);
		public const Address<Vector3Int>[11] spyroEulerRotationAddresses = .(0, (.)0x80078b74/*StD*/, 0, 0, (.)0x8006a054/*RR*/, 0, 0, 0, 0/*YotD-1.1*/, 0, 0);
		public const Address<MatrixInt>[11] spyroMatrixAddresses = .(0, (.)0x80078a8c/*StD*/, 0, 0, (.)0x8006a020/*RR*/, 0, 0, (.)0x80070358, (.)0x80070438/*YotD-1.1*/, 0, 0);
		public const Address<uint32>[11] spyroStateAddresses = .(0, (.)0x80078ad0/*StD*/, 0, 0, (.)0x8006a040/*RR*/, 0, 0, 0, 0/*YotD-1.1*/, 0, 0); 
		public const Address<Vector3Int>[11] spyroIntendedVelocityAddresses = .(0, (.)0x80078b4c/*StD*/, 0, 0, (.)0x8006a084/*RR*/, 0, 0, (.)0x800703B4, (.)0x80070494/*YotD-1.1*/, 0, 0);
		public const Address<Vector3Int>[11] spyroPhysicsVelocityAddresses = .(0, (.)0x80078b64/*StD*/, 0, 0, (.)0x8006a090/*RR*/, 0, 0, (.)0x800703c0, (.)0x800704a0/*YotD-1.1*/, 0, 0);
		public const Address<Vector3Int>[4] spyroIntendedAirVelocityAddress = .(0, (.)0x80078b40/*StD*/, 0, 0); // Exclusive to Spyro the Dragon

		public const Address<Address>[11] objectArrayPointers = .(0, (.)0x80075828/*StD*/, 0, 0, (.)0x80066f14/*RR*/, 0, 0, (.)0x8006c550, (.)0x8006c630/*YotD-1.1*/, 0, 0);
		public const Address<Address>[11] modelPointers = .(0, (.)0x80076378/*StD*/, 0, 0, (.)0x80068c94/*RR*/, 0, 0, (.)0x8006ee2c, (.)0x8006ef0c/*YotD-1.1*/, 0, 0);

		public const Address<Vector3Int>[11] cameraPositionAddress = .(0, (.)0x80076df8/*StD*/, 0, 0, (.)0x80067eac/*RR*/, 0, 0, (.)0x8006e020, (.)0x8006e100/*YotD-1.1*/, 0, 0);
		public const Address<int16[3]>[11] cameraEulerRotationAddress = .(0, (.)0x80076e1c/*StD*/, 0, 0, (.)0x80067ec8/*RR*/, 0, 0, (.)0x8006e03c, (.)0x8006e11c/*YotD-1.1*/, 0, 0);
		public const Address<MatrixInt>[11] cameraMatrixAddress = .(0, (.)0x80076de4/*StD*/, 0, 0, (.)0x80067e98/*RR*/, 0, 0, (.)0x8006e00c, (.)0x8006e0ec/*YotD-1.1*/, 0, 0);

		public const Address<uint32>[11] currentWorldIdAddress = .(0, (.)0x80075964/*StD*/, 0, 0, (.)0x80066f54/*RR*/, 0, 0, (.)0x8006e58c, (.)0x8006c66c/*YotD-1.1*/, 0, 0);
		public const Address<uint32>[4] currentSubWorldIdAddress = .((.)0x8006c5c8, (.)0x8006c6a8, (.)0, (.)0); // Exclusive to Spyro: Year of the Dragon.

		public const Address<Address>[11] collisionDataPointers = .(0, (.)0x800785d4/*StD*/, 0, 0, (.)0x800673fc/*RR*/, 0, 0, (.)0x8006d070, (.)0x8006d150/*YotD-1.1*/, 0, 0);
		public const Address<Address>[11] collisionFlagsArrayPointers = .(0, (.)0x800785b8/*StD*/, 0, 0, (.)0x800673e8/*RR*/, 0, 0, (.)0x8006d05c, (.)0x8006d13c/*YotD-1.1*/, 0, 0);
		public const Address<Address>[11] collisionDeformDataPointers = .(0, (.)0x800785a4/*StD*/, 0, 0, (.)0x80068208/*RR*/, 0, 0, (.)0x8006e384, (.)0x8006e464/*YotD-1.1*/, 0, 0);
		public const Address<uint32>[4] collisionRadius = .((.)0x8007036c, (.)0x8007044c, 0, 0); // Exclusive to Spyro: Year of the Dragon

		public const Address<Renderer.Color4>[11] backgroundClearColorAddress = .(0, (.)0x80078a50/*StD*/, 0, 0, (.)0x800681c0/*RR*/, 0, 0, 0, (.)0x8006e41c/*YotD-1.1*/, 0, 0);
		public const Address<Address>[11] sceneRegionPointers = .(0, (.)0x800785a8/*StD*/, 0, 0, (.)0x800673d4/*RR*/, 0, 0, 0, (.)0x8006d128/*YotD-1.1*/, 0, 0);
		public const Address<Address>[11] farRegionDeformPointers = .(0, (.)0x80078574/*StD*/, 0, 0, (.)0x800681e8/*RR*/, 0, 0, 0, (.)0x8006e444/*YotD-1.1*/, 0, 0);
		public const Address<Address>[11] nearRegionDeformPointers = .(0, (.)0x80078584/*StD*/, 0, 0, (.)0x800681f8/*RR*/, 0, 0, 0, (.)0x8006e454/*YotD-1.1*/, 0, 0);
		public const Address<Address>[11] warpingRegionPointers = .(0, 0/*StD*/, 0, 0, (.)0x800673f0/*RR*/, 0, 0, 0, (.)0x8006d144/*YotD-1.1*/, 0, 0);
		
		public const Address<Address>[11] textureDataPointers = .(0, (.)0x800785c4/*StD*/, 0, 0, (.)0x800673f4/*RR*/, 0, 0, 0, (.)0x8006d148/*YotD-1.1*/, 0, 0);
		public const Address<Address>[11] textureScrollerPointers = .(0, (.)0x8007856c/*StD*/, 0, 0, (.)0x800681e0/*RR*/, 0, 0, 0, (.)0x8006e43c/*YotD-1.1*/, 0, 0);
		public const Address<Address>[11] textureSwapperPointers = .(0, (.)0x80078564/*StD*/, 0, 0, (.)0x800681d8/*RR*/, 0, 0, 0, (.)0x8006e434/*YotD-1.1*/, 0, 0);

		// Exclusive to Spyro: Ripto's Rage
		public const Address<uint8>[3] spriteWidthArrayAddress = .((.)0x800634b8, 0, 0);
		public const Address<uint8>[3] spriteHeightArrayAddress = .((.)0x800634d0, 0, 0);
		public const Address<TextureSprite.SpriteFrame>[3] spriteFrameArrayAddress = .((.)0x8006351c, 0, 0);

		public const Address<uint16>[7] spyroFontAddress = .((.)0x800636a4/*RR*/, 0, 0, 0, (.)0x800667c8/*YotD-1.1*/, 0, 0); // Doesn't exist in Spyro the Dragon
		public const Address<Address<TextureQuad>>[4] spriteArrayPointer = .(0, (.)0x8006c868, 0, 0); // Exclusive to Spyro: Year of the Dragon

		public const Address<uint32>[11] deathPlaneHeightsAddresses = .(0, (.)0x8006e9a4/*StD*/, 0, 0, (.)0x80060234/*RR*/, 0, 0, (.)0x800676e8, (.)0x800677c8/*YotD-1.1*/, 0, 0);
		public const Address<uint32>[11] maxFreeflightHeightsAddresses = .(0, 0/*StD*/, 0, 0, (.)0x800601b4/*RR*/, 0, 0, (.)0x80067648, (.)0x80067728/*YotD-1.1*/, 0, 0);

		public const Address<uint32>[11] healthAddresses = .(0, (.)0x80078bbc/*StD*/, 0, 0, (.)0x8006A248/*RR*/, 0, 0, (.)0x800705a8, (.)0x80070688/*YotD-1.1*/, 0, 0);

		public const Address<uint32>[11] gameInputAddress = .(0, (.)0x800773c0/*StD*/, 0, 0, (.)0x800683a0/*RR*/, 0, 0, 0, (.)0x8006e618/*YotD-1.1*/, 0, 0);
		public const Address<uint32>[11] gameInputSetAddress = .(0, 0/*StD*/, 0, 0, (.)0x8001291c/*RR*/, 0, 0, 0, (.)0x8003a7a0/*YotD-1.1*/, 0, 0);
		public const uint32[11] gameInputValue = .(0, 0/*StD*/, 0, 0, 0xac2283a0/*RR*/, 0, 0, 0, 0xae220030/*YotD-1.1*/, 0, 0);

		public const Address<uint32>[11] spyroStateChangeAddress = .(0, (.)0x8003fd5c/*StD*/, 0, 0, (.)0x80035d04/*RR*/, 0, 0, 0, 0/*YotD-1.1*/, 0, 0);
		public const uint32[11] spyroStateChangeValue = .(0, 0xac358ad0/*StD*/, 0, 0, 0xac33a040/*RR*/, 0, 0, 0, 0/*YotD-1.1*/, 0, 0);

		// Game Values
		public int32 gameState, loadState;

		uint32 input;
		public uint32 Input {
			get => input;
			set {
				input = value;
				gameInputAddress[(int)rom].Write(&input, this);
			}
		}

		Vector3Int cameraPosition;
		public Vector3Int CameraPosition {
			get => cameraPosition;
			set {
				cameraPosition = value;
				cameraPositionAddress[(int)rom].Write(&cameraPosition, this);
			}
		}

		Vector3Int spyroPosition;
		/// Current location of Spyro
		public Vector3Int SpyroPosition {
			get => spyroPosition;
			set {
				spyroPosition = value;
				spyroPositionAddresses[(int)rom].Write(&spyroPosition, this);
			}
		}

		Vector3Int spyroEulerRotation;
		/// Current rotation of Spyro
		public Vector3Int SpyroEulerRotation {
			get => spyroEulerRotation;
			set {
				spyroEulerRotation = value;
				spyroEulerRotationAddresses[(int)rom].Write(&spyroEulerRotation, this);
			}
		}

		uint32 spyroState;
		/// Current state of Spyro
		public uint32 SpyroState {
			get => spyroState;
			set {
				spyroState = value;
				spyroStateAddresses[(int)rom].Write(&spyroState, this);
			}
		}

		Vector3Int spyroIntendedVelocity;
		/// The motion the game will test that will make Spyro move
		public Vector3Int SpyroIntendedVelocity {
			get => spyroIntendedVelocity;
			set {
				spyroIntendedVelocity = value;
				spyroIntendedVelocityAddresses[(int)rom].Write(&spyroIntendedVelocity, this);
			}
		}

		Vector3Int spyroPhysicsVelocity;
		/// The net motion the game makes that will move Spyro
		public Vector3Int SpyroPhysicsVelocity {
			get => spyroPhysicsVelocity;
			set {
				spyroPhysicsVelocity = value;
				spyroPhysicsVelocityAddresses[(int)rom].Write(&spyroPhysicsVelocity, this);
			}
		}

		public int16[3] cameraEulerRotation;
		public MatrixInt cameraBasisInv, spyroBasis;
		public int32 collidingTriangle = -1;
		
		public Renderer.Color4[10][4] shinyColors;
		public uint32[] deathPlaneHeights ~ delete _;
		public uint32[] maxFreeflightHeights ~ delete _;

		public Address<Moby> objectArrayAddress;

		// Game Constants
		public static (String label, Renderer.Color color)[11] collisionTypes = .(
			("Sink", 		.(255, 255, 64)),
			("Hot", 		.(255, 64, 64)),
			("Supercharge", .(64, 64, 64)),
			("Trigger", 	.(255, 64, 255)),
			("Ice", 		.(64, 255, 255)),
			("Barrier", 	.(128, 128, 255)),
			("Portal", 		.(64, 255, 64)),
			("Electric", 	.(64, 64, 255)),
			("Ladder", 		.(128, 92, 64)),
			("Ramp", 		.(128, 255, 64)),
			("Slip", 		.(64, 64, 128))
		);
		
		// Function Overrides
		public const Address<uint32>[11] spyroUpdateAddresses = .(0, (.)0x80033ad8/*StD*/, 0, 0, (.)0x8001b0c4/*RR*/, 0, 0, (.)0x800552f4, (.)0x80055384/*YotD-1.1*/, 0, 0);
		public const uint32[11] spyroUpdateJumpValue = .(0, 0x0c012880/*StD*/, 0, 0, 0x0c00a81f/*RR*/, 0, 0, 0x0c00fa0f, 0x0c00fa18/*YotD-1.1*/, 0, 0);
		public const Address<uint32>[11] cameraUpdateAddresses = .(0, (.)0x80037cfc/*StD*/, 0, 0, (.)0x8001b110/*RR*/, 0, 0, (.)0x80055340, (.)0x800553d0/*YotD-1.1*/, 0, 0);
		public const uint32[11] cameraUpdateJumpValue = .(0, 0x0c00d7ed/*StD*/, 0, 0, 0x0c00761f/*RR*/, 0, 0, 0x0c004813, 0x0c004818/*YotD-1.1*/, 0, 0);
		public const Address<uint32>[11] updateAddresses = .(0, (.)0x80012230/*StD*/, 0, 0, (.)0x80011af4/*RR*/, 0, 0, (.)0x80012024, (.)0x80012038/*YotD-1.1*/, 0, 0);
		public const uint32[11] updateJumpValue = .(0, 0x0c00ce17/*StD*/, 0, 0, 0x0c006c50/*RR*/, 0, 0, 0x0c015500, 0x0c015524/*YotD-1.1*/, 0, 0);

		// Code Injections
		public const Address<uint32> stepperAddress = (.)0x80009000;
		public static uint32[] stepperLogic = new .(
			0x27bdfff8, // addiu sp, -0x8
			0xafbf0000, // sw ra, 0x0($sp)
			0x3c028001, // lui v0, 0x8000
			0x24429000, // addiu v0, 0x9000
			0xafa20004, // sw v0, 0x4($sp)
			0x8c430020, // lw v1, 0x9020(v0)
			0x00000000, // _nop
			0x10600003, // beq v1, z0, 0x3
			0x00000000, // _nop
			0x00000000, // jal ??? [set externally]
			0x00000000, // _nop
			0x8fa20004, // lw v0, 0x4($sp)
			0x00000000, // _nop
			0xac400020, // sw v1, 0x9020(v0)
			0x8fbf0000, // lw ra, 0x0($sp)
			0x27bd0008, // addiu sp, 0x8
			0x03e00008, // jr ra
			0x00000000, // _nop
		) ~ delete _;
		public bool stepperInjected;

		bool paused;
		public bool Paused {
			get {
				return paused;
			}

			set {
				if (value) {
					KillUpdate();
				} else {
					if (!Lockstep) {
						RestoreUpdate();
					}
				}

				paused = value;
			}
		}

		public enum UpdateMode {
			None,
			Normal,
			Manual,
		}

		public UpdateMode UpdateMode { get {
			uint32 value = ?;
			ReadFromRAM(updateAddresses[(int)rom], &value, 4);
			switch (value) {
				case 0: return .None;
				case updateJumpValue[(int)rom]: return .Normal;
				default: return .Manual;
			}
		} }

		public bool InStep { get {
			uint32 v = ?;
			ReadFromRAM(stepperAddress + (8 * 4), &v, 4);
			return v > 0;
		} }

		public bool CameraMode { get {
			uint32 value = ?;
			ReadFromRAM(cameraUpdateAddresses[(int)rom], &value, 4);
			return value != cameraUpdateJumpValue[(int)rom];
		} }

		public bool InputMode { get {
			uint32 value = ?;
			ReadFromRAM(gameInputSetAddress[(int)rom], &value, 4);
			return value != gameInputValue[(int)rom];
		} }

		bool lockstep;
		public bool Lockstep {
			get {
				return lockstep;
			}
			private set {
				if (value) {
					InjectStepperLogic();
				}

				if (!paused) {
					if (value) {
						KillUpdate();
					} else {
						RestoreUpdate();
					}
				}

				lockstep = value;
			}
		}

		// Using lock-step method as the program will be
		// running much faster than the actual emulator speed
		// The emulator will not appear to slow down or lag
		Event<delegate void()> OnStep; 

		// Event Timestamps
		public DateTime lastSceneChanging;
		public DateTime lastSceneChange;

		this(Windows.ProcessHandle process, int emulator) {
			processHandle = process;

			Debug.WriteLine(scope String() .. AppendF("Emulator Process: {}", EmulatorsConfig.emulators[emulator].processName));

			moduleHandle = GetModule(processHandle, EmulatorsConfig.emulators[emulator].processName);

			let mainModuleSize = GetModuleSize(processHandle, moduleHandle);
			Debug.WriteLine(scope String() .. AppendF("Main Module Size: {:x} bytes", mainModuleSize));

			versionIndex = EmulatorsConfig.emulators[emulator].versions.FindIndex(scope (x) => x.moduleSize == mainModuleSize);
			Debug.WriteLine(scope String() .. AppendF("Emulator Version: {}", versionIndex > -1 ? EmulatorsConfig.emulators[emulator].versions[versionIndex].label : "Unknown"));

			emulatorIndex = emulator;

			if (active == null) {
				active = this;
			}

			emulators.Add(this);
		}

		public static void FindProcesses(List<Process> processes) {
			if (Process.GetProcesses(processes) case .Err) {
				Debug.FatalError("Failed to get process list");
			}

			processes.RemoveAll(scope (process) => {
				if (EmulatorsConfig.emulators.FindIndex(scope (x) => x.processName == process.ProcessName) > -1) {
					return false;
				}
				
				delete process;
				return true;
			});
		}

		public static Emulator BindEmulatorProcess(Process process) {
			// Try to open and access the process
			Windows.ProcessHandle processHandle = Windows.OpenProcess(Windows.PROCESS_ALL_ACCESS, false, process.Id);

			let emulatorIndex = EmulatorsConfig.emulators.FindIndex(scope (x) => x.processName == process.ProcessName);

			if (emulatorIndex > -1) {
				return new Emulator(processHandle, emulatorIndex);
			}

			return null;
		}

		public void FindGame() {
			SpyroROM newRom = .None;
			for (int i < 10) {
				let test = scope String();
				let testPtr = test.PrepareBuffer(5);
				ReadFromRAM(testAddresses[i], testPtr, 5);

				if (test.CompareTo("Spyro", true) == 0) {
					newRom = (.)(i + 1);
					break;
				}
			}

			switch (newRom) {
				case .SpyroTheDragon_NTSC_U,
					 .SpyroTheDragon_NTSC_J,
					 .SpyroTheDragon_PAL:
					installment = .SpyroTheDragon;

				case .RiptosRage_NTSC_U,
					 .RiptosRage_NTSC_J,
					 .RiptosRage_PAL:
					installment = .RiptosRage;

				case .YearOfTheDragon_1_0_NTSC_U,
					 .YearOfTheDragon_1_0_PAL,
					 .YearOfTheDragon_1_1_NTSC_U,
					 .YearOfTheDragon_1_1_PAL:
					installment = .YearOfTheDragon;

				default:
					installment = .None;
			}

			if (newRom != .None && newRom != rom) {
				FetchStaticData();
			}

			rom = newRom;
		}
		
		[Import("psapi.lib"),CLink, CallingConvention(.Stdcall)]
		static extern Windows.IntBool EnumProcessModules(Windows.ProcessHandle process, Windows.HModule* module, uint16 size, uint32* sizeNeeded);
		[Import("psapi.lib"),CLink, CallingConvention(.Stdcall)]
		static extern Windows.IntBool GetModuleFileNameExA(Windows.ProcessHandle process, Windows.HModule module, char8* buffer, uint32 size);

		static Windows.HModule GetModule(Windows.ProcessHandle process, String moduleName) {
			Windows.HModule[512] modules = ?;
			uint32 sizeNeeded = ?;

			if (EnumProcessModules(process, &modules[0], sizeof(Windows.HModule[512]), &sizeNeeded)) {
				for (let i < sizeNeeded / sizeof(Windows.HModule)) {
					let module = modules[i];
				    String modName = scope .();
					let ptr = modName.PrepareBuffer(1024);
				    if (GetModuleFileNameExA(process, module, ptr, 1024) && modName.Contains(moduleName)) {
				  		return module;
				    }
				}
			}

			return 0;
		}
		
		[CRepr]
		struct ModuleInfo {
			public void* baseOfDLL;
			public uint32 sizeOfImage;
			public void* entryPoint;
		}

		[Import("psapi.lib"),CLink, CallingConvention(.Stdcall)]
		static extern Windows.IntBool GetModuleInformation(Windows.ProcessHandle process, Windows.HModule module, ModuleInfo* moduleInfo, uint32 cb);

		static uint32 GetModuleSize(Windows.ProcessHandle process, Windows.HModule module) {
			ModuleInfo info = ?;
			GetModuleInformation(process, module, &info, sizeof(ModuleInfo));

			return info.sizeOfImage;
		}

		public void CheckProcessStatus() {
			int32 exitCode;
			if (Windows.GetExitCodeProcess(processHandle, out exitCode) && exitCode != 259 /*STILL_ACTIVE*/) {
				UnbindEmulatorProcess();
			}
		}

		public void FetchMainAddresses() {
			// Do this once since all emulators have one location for its RAM/VRAM

			if (RAMBaseAddress == 0) {
				FetchRAMBaseAddress();
			}

			if (VRAMBaseAddress == 0) {
				FetchVRAMBaseAddress();
			}

			// NOTE: Careful with getting VRAM once, since some emulators have multiple rendering engine that can be swapped out
		}

		public void CheckSources() {
			for (let i < 8) {
				Address newLoadedPointer = ?;
				var pointerSet = pointerSets[i];
				let pointer = pointerSet[(int)rom];

				pointer.Read(&newLoadedPointer, this);
				if (!newLoadedPointer.IsNull && loadedPointers[i] != newLoadedPointer) {
					loadedPointers[i] = newLoadedPointer;
					changedPointers[i] = true;

					if (loadingStatus == .Idle) {
						lastSceneChanging = .Now;
					}

					loadingStatus = .Loading;
				}
			}

			if (loadingStatus == .Loading) {
				if (loadState == -1) { // Loaded everything the game needs for a level
					loadingStatus = .Done;
	
					for (let i < 8) {
						changedPointers[i] = false;
					}
					VRAM.upToDate = false;
				} else if (
					installment == .SpyroTheDragon && (gameState == 13 || gameState == 14) ||
					installment != .SpyroTheDragon && (gameState == 6 || gameState == 11)
				) {
					loadingStatus = .CutsceneDone;

					for (let i < 8) {
						changedPointers[i] = false;
					}
					VRAM.upToDate = false;
				}
			}
		}

		public void UnbindEmulatorProcess() {
			if (Supported && rom != .None) {
				RestoreCameraUpdate();
				RestoreInputRelay();
				RestoreUpdate();
				RestoreSpyroUpdate();
				RestoreSpyroStateChange();
			}

			processHandle.Close();
			processHandle = 0;
			moduleHandle = 0;

			for (let i < 8) {
				loadedPointers[i] = 0;
				changedPointers[i] = false;
			}
		}


		public static void UnbindAllEmulators() {
			for (let emulator in emulators) {
				emulator.UnbindEmulatorProcess();
				delete emulator;
			}

			emulators.Clear();
		}

		public void FetchRAMBaseAddress() {
			if (versionIndex == -1) {
				return;
			}

			let version = EmulatorsConfig.emulators[emulatorIndex].versions[versionIndex];
			let moduleHandle = GetModule(processHandle, version.ramModuleName);

			if (moduleHandle.IsInvalid) {
				return;
			}

			RAMBaseAddress = PointerOffsetsToAddress((.)moduleHandle, version.offsetsToRAM);
		}

		public void FetchVRAMBaseAddress() {
			if (versionIndex == -1) {
				return;
			}

			let version = EmulatorsConfig.emulators[emulatorIndex].versions[versionIndex];
			let moduleHandle = GetModule(processHandle, version.vramModuleName);

			if (moduleHandle.IsInvalid) {
				return;
			}

			VRAMBaseAddress = PointerOffsetsToAddress((.)moduleHandle, version.offsetsToVRAM);
		}

		int PointerOffsetsToAddress(int baseAddress, List<int> offsets) {
			var address = baseAddress;
			address += offsets[0];
			for (var i = 1; i < offsets.Count; i++) {
				Windows.ReadProcessMemory(processHandle, (.)address, &address, 4, null);
				if (address == 0) {
					return 0;
				}
				address += offsets[i];
			}
			return address;
		}

		[Inline]
		public void* RawAddressFromRAM(Address address) {
			return ((uint8*)null + RAMBaseAddress + ((uint32)address & 0x003fffff));
		}

		public void ReadFromRAM(Address address, void* buffer, int size) {
			let rawAddress = RawAddressFromRAM(address);
			Windows.ReadProcessMemory(processHandle, rawAddress, buffer, size, null);
		}

		public void WriteToRAM(Address address, void* buffer, int size) {
			if (loadingStatus == .Loading) {
				return; // Do not try change anything while loading
			}
			let rawAddress = RawAddressFromRAM(address);
			Windows.WriteProcessMemory(processHandle, rawAddress, buffer, size, null);
		}

		// Spyro
		void FetchStaticData() {
			delete maxFreeflightHeights;
			delete deathPlaneHeights;

			switch (installment) {

				case .SpyroTheDragon: {
					ReadFromRAM((.)0x8006e44c, &shinyColors, sizeof(Renderer.Color4[10][4]));

					// 35 worlds exist, but there is space for 36. (Probably due to short/int reasons.)
					deathPlaneHeights = new .[36];
					maxFreeflightHeights = new .[36];

					deathPlaneHeightsAddresses[(int)rom].ReadArray(&deathPlaneHeights[0], 36, this);
					maxFreeflightHeightsAddresses[(int)rom].ReadArray(&maxFreeflightHeights[0], 36, this);
				}

				case .RiptosRage: {
					ReadFromRAM((.)0x80064440, &shinyColors, sizeof(Renderer.Color4[10][4]));

					// 28 worlds exists but there is space for 32 (probably a power of 2 related thing)
					deathPlaneHeights = new .[32];
					maxFreeflightHeights = new .[32];
					
					deathPlaneHeightsAddresses[(int)rom].ReadArray(&deathPlaneHeights[0], 32, this);
					maxFreeflightHeightsAddresses[(int)rom].ReadArray(&maxFreeflightHeights[0], 32, this);
				}

				case .YearOfTheDragon: {
					ReadFromRAM((.)0x80066a70, &shinyColors, sizeof(Renderer.Color4[10][4]));

					// 37 worlds exist, but theres space for 40. (Probably due to short/int reasons.)
					// Also gets multipled by 4 due to sub worlds, there being a minimum of 4 in each homeworld.
					deathPlaneHeights = new .[40 * 4];
					maxFreeflightHeights = new .[40 * 4];

					deathPlaneHeightsAddresses[(int)rom].ReadArray(&deathPlaneHeights[0], 40 * 4, this);
					maxFreeflightHeightsAddresses[(int)rom].ReadArray(&maxFreeflightHeights[0], 40, this);
				}
				default : {}
			}
		}

		

		public void FetchImportantData() {
			// Load static address values
			gameStateAddresses[(int)rom].Read(&gameState, this);
			loadStateAddresses[(int)rom].Read(&loadState, this);

			gameInputAddress[(int)rom].Read(&input, this);

			spyroPositionAddresses[(int)rom].Read(&spyroPosition, this);
			spyroEulerRotationAddresses[(int)rom].Read(&spyroEulerRotation, this);
			spyroMatrixAddresses[(int)rom].Read(&spyroBasis, this);
			spyroStateAddresses[(int)rom].Read(&spyroState, this);
			spyroIntendedVelocityAddresses[(int)rom].Read(&spyroIntendedVelocity, this);
			spyroPhysicsVelocityAddresses[(int)rom].Read(&spyroPhysicsVelocity, this);

			cameraPositionAddress[(int)rom].Read(&cameraPosition, this);
			cameraMatrixAddress[(int)rom].Read(&cameraBasisInv, this);
			cameraEulerRotationAddress[(int)rom].Read(&cameraEulerRotation, this);

			//ReadFromRAM((.)0x8006a28c, &collidingTriangle, 4);

			CheckSources();
			if (loadingStatus == .Done || loadingStatus == .CutsceneDone) {
				Thread.Sleep(500); // This is mainly needed for when emulators load snapshots/savestates
				// as there is a big delay when loading the large data at once
				
				loadingStatus = loadingStatus == .CutsceneDone ? .CutsceneIdle : .Idle;
				lastSceneChange = .Now;
			}

			if (!VRAM.upToDate && gameState != (installment == .SpyroTheDragon ? 2 : 4)) {
				VRAM.TakeSnapshot();
			}

			Emulator.Address<Moby> newObjectArrayAddress = ?;
			objectArrayPointers[(int)rom].Read(&newObjectArrayAddress, this);
			if (objectArrayAddress != newObjectArrayAddress) {
				Moby.allocated.Clear();
			}
			objectArrayAddress = newObjectArrayAddress;

			if (Lockstep && !InStep && !Paused) {
				OnStep();
				Step();
			}
		}

		// Spyro Update
		public void KillSpyroUpdate() {
			uint32 v = 0;
			spyroUpdateAddresses[(int)rom].Write(&v, this);
		}

		public void RestoreSpyroUpdate() {
			uint32 v = spyroUpdateJumpValue[(int)rom];
			spyroUpdateAddresses[(int)rom].Write(&v, this);
		}

		public void KillSpyroStateChange() {
			uint32 v = 0;
			spyroStateChangeAddress[(int)rom].Write(&v, this);
		}

		public void RestoreSpyroStateChange() {
			uint32 v = spyroStateChangeValue[(int)rom];
			spyroStateChangeAddress[(int)rom].Write(&v, this);
		}

		// Main Update
		public void KillUpdate() {
			// If stepper code injection exists, jump to that code instead of nop'ing it out
			// since the code will not cause one from of the game loop to occur by default
			uint32 v = stepperInjected ? 0x0C002400 : 0;
			updateAddresses[(int)rom].Write(&v, this);
		}

		public void RestoreUpdate() {
			uint32 v = updateJumpValue[(int)rom];
			updateAddresses[(int)rom].Write(&v, this);
		}

		// Camera
		public void KillCameraUpdate() {
			uint32 v = 0;
			cameraUpdateAddresses[(int)rom].Write(&v, this);
		}

		public void RestoreCameraUpdate() {
			uint32 v = cameraUpdateJumpValue[(int)rom];
			cameraUpdateAddresses[(int)rom].Write(&v, this);
		}

		public void SetCameraPosition(Vector3Int* position) {
			cameraPositionAddress[(int)rom].Write(position, this);
		}

		// Input
		public void KillInputRelay() {
			uint32 v = 0;
			gameInputSetAddress[(int)rom].Write(&v, this);

			// Beyond the point of this function being called
			// input should be written into RAM from the program

			// Currently it still receives input elsewhere
			// even after this is called
		}

		public void RestoreInputRelay() {
			uint32 v = gameInputValue[(int)rom];
			gameInputSetAddress[(int)rom].Write(&v, this);
		}

		// Logic
		public void InjectStepperLogic() {
			WriteToRAM(stepperAddress, &stepperLogic[0], 4 * stepperLogic.Count);
			uint32 v = 0x0C002400; // (stepperAddress & 0x0fffffff) >> 2;
			updateAddresses[(int)rom].Write(&v, this);
			stepperInjected = true;
		}

		public void Step() {
			if (!stepperInjected) {
				InjectStepperLogic();
			}
			KillUpdate();
			uint32 v = updateJumpValue[(int)rom];
			WriteToRAM(stepperAddress + (8 * 4), &v, 4);
		}

		public void AddStepListener(delegate void() listener) {
			OnStep.Add(listener);
			Lockstep = true;
		}

		public void RemoveStepListener(delegate void() listener) {
			OnStep.Remove(listener);
			Lockstep = OnStep.HasListeners;
		}
	}
}
