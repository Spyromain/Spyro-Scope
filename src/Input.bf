using SDL2;
using System;

namespace SpyroScope {
	class Input : GUIElement {
		public static int cursor, selectBegin;
		public static bool dragging;
		
		public Renderer.Color normalColor = .(255, 255, 255);
		public Renderer.Color activeColor = .(255, 255, 128);
		public Renderer.Color disabledColor = .(128, 128, 128);

		public Texture normalTexture = Renderer.whiteTexture;
		public Texture activeTexture = Renderer.whiteTexture;

		String lastValidText = new .() ~ delete _;
		public String text = new .() ~ delete _;
		
		public bool enabled = true;
		public Event<delegate void()> OnSubmit ~ _.Dispose();
		public Event<delegate void()> OnChanged ~ _.Dispose();
		public delegate bool() OnValidate ~ delete _;

		public override void Draw(Rect parentRect) {
			base.Draw(parentRect);

			Renderer.Color color = ?;
			Texture texture = normalTexture;
			if (!enabled) {
				color = disabledColor;
			} else if (selectedElement == this) {
				color = activeColor;
				texture = activeTexture;
			} else {
				color = normalColor;
			}
			DrawUtilities.SlicedRect(drawn.bottom, drawn.top, drawn.left, drawn.right, 0,1,0,1, 0.3f,0.7f,0.3f,0.7f, texture, color);

			let vcenter = (drawn.top + drawn.bottom) / 2;
			let halfHeight = Math.Floor(WindowApp.fontSmall.height / 2);

			let textStartX = drawn.left + 4;
			var cursorPos = 0f;
			if (text != null && !text.IsEmpty) {
				if (selectedElement == this) {
					cursorPos = WindowApp.fontSmall.CalculateWidth(.(text,0,cursor));

					if (SelectionExists()) {
						var selectBeginPos = WindowApp.fontSmall.CalculateWidth(.(text,0,selectBegin));
	
						float left, right;
						if (cursor > selectBegin) {
							left = selectBeginPos;
							right = cursorPos;
						} else {
							left = cursorPos;
							right = selectBeginPos;
						}

						left += textStartX;
						right += textStartX;

						DrawUtilities.Rect(vcenter - halfHeight, vcenter + halfHeight, left, right, .(56,154,232,192));
					}
				}
				
				WindowApp.fontSmall.Print(text, .(textStartX, vcenter - halfHeight, 0), .(0,0,0));
			}

			if (selectedElement == this) {
				cursorPos += textStartX;
				Renderer.DrawLine(.(cursorPos, vcenter - halfHeight, 0), .(cursorPos, vcenter + halfHeight, 0), .(0,0,0), .(0,0,0));
			}
		}

		public bool Input(SDL.Event event) {
			var event;

			switch (event.type) {
				case .KeyDown:
					if (enabled && event.key.keysym.sym == .BACKSPACE && text.Length > 0 && cursor > 0) {
						if (SelectionExists()) {
							let left = GetLeft();
							text.Remove(left, GetRight() - left);
							cursor = left;
						} else {
							text.Remove(cursor--, 1);
						}
						selectBegin = cursor;
						CheckText();
					}
				
					if (event.key.keysym.mod & .CTRL > 0) {
						if (event.key.keysym.sym == .A) {
							SelectAll();
						}

						if (event.key.keysym.sym == .C) {
							Copy();
						}

						if (enabled) {
							// Cut
							if (event.key.keysym.sym == .X) {
								if (SelectionExists()) {
									SDL.SetClipboardText(scope String(GetSelectionText()));
									
									let left = GetLeft();
									text.Remove(left, GetRight() - left);
									cursor = left;
								} else {
									SDL.SetClipboardText(text);
	
									text.Set("");
									cursor = 0;
								}
								selectBegin = cursor;
							}
	
							// Paste
							if (event.key.keysym.sym == .V) {
								if (SelectionExists()) {
									let left = GetLeft();
									let right = GetRight();
	
									text.Remove(left, right - left);
									cursor = left;
								}
	
								let clipboard = scope String(SDL.GetClipboardText()) .. Replace("\t", "") .. Replace("\n", "");
								text.Insert(cursor, clipboard);
								cursor += clipboard.Length;
								selectBegin = cursor;
								CheckText();
							}
						}
					}

					if (event.key.keysym.sym == .LEFT) {
						if (SelectionExists() && event.key.keysym.mod & .SHIFT == 0) {
							cursor = GetLeft();
						} else if (--cursor < 0) {
							cursor = 0;
						}

						if (event.key.keysym.mod & .SHIFT == 0) {
							selectBegin = cursor;
						}
					}

					if (event.key.keysym.sym == .RIGHT) {
						if (SelectionExists() && event.key.keysym.mod & .SHIFT == 0) {
							cursor = GetRight();
						} else if (++cursor > text.Length) {
							cursor = text.Length;
						}

						if (event.key.keysym.mod & .SHIFT == 0) {
							selectBegin = cursor;
						}
					}

					if (event.key.keysym.sym == .RETURN) {
						selectedElement = null;
						text.Set(lastValidText);
						OnSubmit();
					}
	
				// All key inputs will be consumed while a text input is selected
				return true;

				case .TextInput:
					if (enabled) {
						if (SelectionExists()) {
							let left = GetLeft();
							text.Remove(left, GetRight());
							cursor = left;
						}
						text.Insert(cursor, .((char8*)&event.text.text[0]));
						selectBegin = ++cursor;
						CheckText();
					}
					return true;

				case .MouseMotion:
					if (dragging) {
						cursor = WindowApp.fontSmall.NearestTextIndex(text, WindowApp.mousePosition.x - (drawn.left + 4));
					}

				default:
			}

			return false;
		}

		protected override void MouseEnter() {
			SDL.SetCursor(Ibeam);
		}

		protected override void MouseExit() {
			SDL.SetCursor(arrow);
		}

		protected override void Pressed() {
			selectBegin = cursor = WindowApp.fontSmall.NearestTextIndex(text, WindowApp.mousePosition.x - (drawn.left + 4));
			dragging = true;
		}

		protected override void Unpressed() {
			dragging = false;
		}

		void CheckText() {
			if (OnValidate == null || OnValidate()) {
				lastValidText.Set(text);
				OnChanged();
			}
		}

		public void SetValidText(StringView validText) {
			if (selectedElement != this) {
				text.Set(validText);
			}
			lastValidText.Set(validText);
		}

		[Inline]
		int GetLeft() {
			return Math.Min(cursor, selectBegin);
		}
		
		[Inline]
		int GetRight() {
			return Math.Max(cursor, selectBegin);
		}

		[Inline]
		bool SelectionExists() {
			return cursor != selectBegin;
		}

		[Inline]
		StringView GetSelectionText() {
			return .(text, GetLeft(), Math.Abs(cursor - selectBegin));
		}

		public void SelectAll() {
			selectBegin = 0;
			cursor = text.Length;
		}

		public void Copy() {
			if (SelectionExists()) {
				SDL.SetClipboardText(scope String(GetSelectionText()));
			} else {
				SDL.SetClipboardText(text);
			}
		}
	}
}
