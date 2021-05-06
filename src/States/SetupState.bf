using System;
using System.Collections;
using System.Diagnostics;

namespace SpyroScope {
	class SetupState : WindowState {
		List<GUIElement> guiElements = new .() ~ DeleteContainerAndItems!(_);

		Stopwatch stopwatch = new .() ~ delete _;
		public List<Process> processes = new .() ~ delete _;

		public override void Enter() {
			GUIElement.SetActiveGUI(guiElements);

			Renderer.clearColor = .(0,0,0);
			stopwatch.Start();
		}
		
		public override void Exit() {
			stopwatch.Reset();
			
			GUIElement.SetActiveGUI(null);
		}

		public override void Update() {
			if (!(Emulator.active == null || Emulator.active.rom == .None)) {
				if (stopwatch.ElapsedMilliseconds > 3000) {
					windowApp.GoToState<ViewerState>();
				}
			} else if (stopwatch.ElapsedMilliseconds > 1000) {
				if (Emulator.active == null) {
					DeleteAndClearItems!(processes);
					DeleteAndClearItems!(guiElements);

					Emulator.FindProcesses(processes);

					if (processes.Count == 1) {
						// Automatically bind to the process
						Emulator.BindEmulatorProcess(processes[0]);
					} else {
						// List out and let user choose applicable processes
						for (let i < processes.Count) {
							let process = processes[i];

							Button processButton = new .();
							processButton.Anchor = .(0.5f, 0.5f, 0.5f, 0.5f);
							processButton.Offset = .(-128, 128, (i + 1) * 16, (i + 2) * 16);
							processButton.text = new .() .. AppendF("{} - {}", process.ProcessName, process.Id);
							processButton.OnActuated.Add(new () => {
								Emulator.BindEmulatorProcess(processes[i]);

								DeleteAndClearItems!(processes);
								DeleteAndClearItems!(guiElements);
							});

							stopwatch.Restart();
						}
					}
				}

				if (Emulator.active != null) {
					Emulator.active.CheckProcessStatus();
					if (Emulator.active.Supported) {
						Emulator.active.FetchMainAddresses();
						Emulator.active.FindGame();
					}
				}
				
				stopwatch.Restart();
			}
		}

		public override void DrawGUI() {
			let middleWindow = WindowApp.width / 2;

			Message : {
				Emulator activeEmulator = Emulator.active;
				String message = .Empty;
				if (activeEmulator == null) {
					message = "Waiting for Emulator";
				} else {
					if (!activeEmulator.Supported) {
						message = scope:Message String() .. AppendF("Unknown Module Size: (0x{:x})", activeEmulator.MainModuleSize);
					} else if (activeEmulator.rom == .None) {
						message = "Waiting for Game";
					} else {
						message = Emulator.gameNames[(int)activeEmulator.rom];
					}
	
					let baseline = WindowApp.height / 2 - WindowApp.font.height * 1.5f;
					let emulatorName = scope String() .. AppendF("{} ({})", activeEmulator.Name, activeEmulator.Version);
					let halfWidth = Math.Round(WindowApp.font.CalculateWidth(emulatorName) / 2);
					WindowApp.font.Print(emulatorName, .(middleWindow - halfWidth, baseline), activeEmulator.Supported ? .(255,255,255) : .(255,255,0));
				}
	
				var baseline = (WindowApp.height - WindowApp.font.height) / 2;
				let halfWidth = Math.Round(WindowApp.font.CalculateWidth(message) / 2);
				WindowApp.font.Print(message, .(middleWindow - halfWidth, baseline), .(255,255,255));
	
				baseline += WindowApp.font.penLine;
				if (activeEmulator == null || activeEmulator.rom == .None) {
					let t = (float)stopwatch.ElapsedMilliseconds / 1000 * 3.14f;
					DrawUtilities.Rect(baseline + 2, baseline + 4, middleWindow - halfWidth * Math.Sin(t), middleWindow + halfWidth * Math.Sin(t),
						.(255,255,255));
				} else {
					let t = 1f - (float)stopwatch.ElapsedMilliseconds / 3000;
					DrawUtilities.Rect(baseline + 2, baseline + 4, middleWindow - halfWidth * t, middleWindow + halfWidth * t,
						.(255,255,255));
				}
			}

			for (let element in guiElements) {
				if (element.GetVisibility()) {
					element.Draw();
				}
			}
		}
	}
}
