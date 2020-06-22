using System;
using System.Collections;
using System.Threading;

namespace SpyroScope {
	static struct Emulator {
		static Windows.ProcessHandle processHandle;

		const void* n = null;
		const uint32 PEBaseAddress = 0x00400000;
		const uint32[4] staticPointerAddresses = .( 0x0, PEBaseAddress + 0x00091E10, 0x0, 0x0 );

		public enum EmulatorType {
			None,
			NoCashPSX
		}
		public static EmulatorType emulator;
		static uint32 emulatorRAMBaseAddress;
		// TODO: Include other emulators

		public enum SpyroROM {
			None,
			SpyroTheDragon,
			RiptosRage,
			YearOfTheDragon
		}
		public static SpyroROM rom;

		public typealias Address = uint32;

		// Begin Spyro games information

		public const Address[3] testAddresses = .(0, 0x80066ea8, 0x8006c490);
		public const String[4] gameNames = .(String.Empty, "Spyro the Dragon", "Spyro: Ripto's Rage", "Spyro: Year of the Dragon");

		public const Address[4] spyroPositionPointers = .(0, 0, 0x80069ff0, 0x80070408);
		public const Address[4] spyroMatrixPointers = .(0, 0, 0x8006a020, 0x80070438);
		public const Address[4] spyroIntendedVelocityPointers = .(0, 0, 0x8006a084, 0x80070494);
		public const Address[4] spyroPhysicsVelocityPointers = .(0, 0, 0x8006a090, 0x800704a0);

		public const Address[4] objectArrayPointers = .(0, 0, 0x80066f14, 0x8006c630);
		public const Address[4] modelPointers = .(0, 0, 0x80068c94, 0);

		public const Address[4] cameraPositionAddress = .(0, 0, 0x80067eac, 0x8006e100);
		public const Address[4] cameraEulerRotationAddress = .(0, 0, 0x80067ec8, 0x8006e11c);
		public const Address[4] cameraMatrixAddress = .(0, 0, 0x80067e98, 0x8006e0ec);

		public const Address[4] collisionDataPointer = .(0, 0, 0x800673fc, 0x8006d150);
		public const Address[4] collisionFlagsArrayPointer = .(0, 0, 0x800673e8, 0x8006d13c);

		public const Address[4] fuckSparx = .(0, 0, 0x8006A248, 0x80070688);

		// Game Values
		public static VectorInt cameraPosition, spyroPosition;
		public static VectorInt spyroIntendedVelocity, spyroPhysicsVelocity;
		public static uint16[3] cameraEulerRotation;
		public static MatrixInt cameraBasisInv, spyroBasis;
		public static int32 collidingTriangle = -1;
		
		public static Emulator.Address collisionDataAddress;
		public static List<PackedTriangle> collisionTriangles = new .() ~ delete _;
		public static uint32 specialTerrainBeginIndex;
		public static List<uint8> collisionFlagsIndices = new .() ~ delete _;
		public static List<uint32> collisionFlagPointerArray = new .() ~ delete _;

		// Function Overrides
		public const Address[4] cameraUpdateAddresses = .(0, 0, 0x8001b110, 0x800553d0);		  
		public const Address[4] cameraUpdateJumpValue = .(0, 0, 0x0c00761f, 0x0c004818);
		public const Address[4] updateAddresses = .(0, 0, 0x80011af4, 0x80012038);
		public const Address[4] updateJumpValue = .(0, 0, 0x0c006c50, 0x0c015524);

		public static bool cameraMode, pausedMode = false;

		// Events
		public static Action OnSceneChanged;

		public static void BindToEmulator() {
			// TODO: Have an option or auto detect
			emulator = .NoCashPSX;
			let windowHandle = Windows.FindWindowW(null, "No$psx Debugger".ToScopedNativeWChar!());

			if (windowHandle == 0) {
				Console.WriteLine("Window cannot be found. Closing after 10 seconds...");
				Thread.Sleep(10000);
				return;
			}

			int32 processID;
			Windows.GetWindowThreadProcessId(windowHandle, out processID);
			processHandle = Windows.OpenProcess(Windows.PROCESS_ALL_ACCESS, false, processID);

			FetchRAMBaseAddress();
			
			Console.WriteLine("Detecting Game...");
			for (int i < 3) {
				let test = scope String();
				let testPtr = test.PrepareBuffer(5);
				ReadFromRAM(testAddresses[i], testPtr, 5);

				if (test == "Spyro") {
					rom = (.)(i + 1);
					break;
				}
			}

			if (rom == .None) {
				Console.WriteLine("Game cannot be detected. Closing after 10 seconds...");	
				Thread.Sleep(10000);
				return;
			} else {
				Console.WriteLine("{} was detected!", gameNames[(int)rom]);
			}
		}

		public static void CheckEmulatorStatus() {
			int32 exitCode;
			if (Windows.GetExitCodeProcess(processHandle, out exitCode) && exitCode != 259 /*STILL_ACTIVE*/) {
				Console.WriteLine("Emulator was closed!");
				emulator = .None;
				Thread.Sleep(3000);
			}
		}

		public static void UnbindToEmulator() {
			if (emulator != .None) {
				RestoreCameraUpdate();
				RestoreUpdate();
			}
		}

		public static void FetchRAMBaseAddress() {
			uint8* pointer = (uint8*)n + staticPointerAddresses[(int)emulator];
			Windows.ReadProcessMemory(processHandle, pointer, &pointer, 4, null);
			pointer -= 0x1fc; // Currently specific to no$psx
			Windows.ReadProcessMemory(processHandle, pointer, &emulatorRAMBaseAddress, 4, null);
		}

		public static mixin RawAddressFromRAM(Address address) {
			(void*)((uint8*)n + emulatorRAMBaseAddress + (address & 0x003fffff))
		}

		public static void ReadFromRAM(Address address, void* buffer, int size) {
			let rawAddress = RawAddressFromRAM!(address);
			Windows.ReadProcessMemory(processHandle, rawAddress, buffer, size, null);
		}

		public static void WriteToRAM(Address address, void* buffer, int size) {
			let rawAddress = RawAddressFromRAM!(address);
			Windows.WriteProcessMemory(processHandle, rawAddress, buffer, size, null);
		}

		// Spyro

		public static void FetchImportantObjects() {
			ReadFromRAM(spyroPositionPointers[(int)rom], &spyroPosition, sizeof(VectorInt));
			ReadFromRAM(spyroMatrixPointers[(int)rom], &spyroBasis, sizeof(MatrixInt));
			ReadFromRAM(spyroIntendedVelocityPointers[(int)rom], &spyroIntendedVelocity, sizeof(VectorInt));
			ReadFromRAM(spyroPhysicsVelocityPointers[(int)rom], &spyroPhysicsVelocity, sizeof(VectorInt));

			ReadFromRAM(cameraPositionAddress[(int)rom], &cameraPosition, sizeof(VectorInt));
			ReadFromRAM(cameraMatrixAddress[(int)rom], &cameraBasisInv, sizeof(MatrixInt));
			ReadFromRAM(cameraEulerRotationAddress[(int)rom], &cameraEulerRotation, 6);

			//ReadFromRAM(0x8006a28c, &collidingTriangle, 4);

			let collisionDataAddressOld = collisionDataAddress;
			Emulator.ReadFromRAM(Emulator.collisionDataPointer[(int)Emulator.rom], &collisionDataAddress, 4);
			if (collisionDataAddressOld != collisionDataAddress) {
				// Wait for the level data to load before caching
				Thread.Sleep(500);

				uint32 triangleCount = ?;
				Emulator.ReadFromRAM(collisionDataAddress, &triangleCount, 4);
				Emulator.ReadFromRAM(collisionDataAddress + 4, &specialTerrainBeginIndex, 4);

				collisionTriangles.Clear();
				let ptrTriangles = collisionTriangles.GrowUnitialized(triangleCount);
				Emulator.Address collisionTriangleArray = ?;
				Emulator.ReadFromRAM(collisionDataAddress + 20, &collisionTriangleArray, 4);
				Emulator.ReadFromRAM(collisionTriangleArray, ptrTriangles, sizeof(PackedTriangle) * triangleCount);
				
				Emulator.Address collisionFlagArray = ?;

				collisionFlagsIndices.Clear();
				let ptrFlagIndices = collisionFlagsIndices.GrowUnitialized(triangleCount);
				Emulator.ReadFromRAM(collisionDataAddress + 24, &collisionFlagArray, 4);
				Emulator.ReadFromRAM(collisionFlagArray, ptrFlagIndices, 1 * triangleCount);

				collisionFlagPointerArray.Clear();
				let ptrFlags = collisionFlagPointerArray.GrowUnitialized(0x3f);
				Emulator.ReadFromRAM(collisionFlagsArrayPointer[(uint)rom], &collisionFlagArray, 4);
				Emulator.ReadFromRAM(collisionFlagArray, ptrFlags, 4 * 0x3f);

				OnSceneChanged();
			}
		}

		// Main Update
		public static void KillUpdate() {
			uint32 v = 0;
			WriteToRAM(updateAddresses[(int)rom], &v, 4);
			pausedMode = true;
			Console.WriteLine("Game Paused.");
		}

		public static void RestoreUpdate() {
			uint32 v = updateJumpValue[(int)rom];
			WriteToRAM(updateAddresses[(int)rom], &v, 4);
			pausedMode = false;
			Console.WriteLine("Game Resumed.");
		}

		public static void TogglePaused() {
			if (pausedMode) {
				RestoreUpdate();
			} else {
				KillUpdate();
			}
		}

		// Camera
		public static void KillCameraUpdate() {
			uint32 v = 0;
			WriteToRAM(cameraUpdateAddresses[(int)rom], &v, 4);
			cameraMode = true;
			Console.WriteLine("Free Camera On.");
		}

		public static void RestoreCameraUpdate() {
			uint32 v = cameraUpdateJumpValue[(int)rom];
			WriteToRAM(cameraUpdateAddresses[(int)rom], &v, 4);
			cameraMode = false;
			Console.WriteLine("Free Camera Off.");
		}

		public static void ToggleCameraMode() {
			if (cameraMode) {
				RestoreCameraUpdate();
			} else {
				KillCameraUpdate();
			}
			Console.WriteLine("Toggled Camera Mode.");
		}

		public static void GetCameraPosition(VectorInt* position) {
			ReadFromRAM(cameraPositionAddress[(int)rom], position, sizeof(VectorInt));
		}

		public static void MoveCameraTo(VectorInt* position) {
			WriteToRAM(cameraPositionAddress[(int)rom], position, sizeof(VectorInt));
		}
	}
}
