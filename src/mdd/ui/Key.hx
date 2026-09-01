package mdd.ui;

enum abstract Key(Int) from Int to Int {
	var A = 4;
	var C = 6;
	var D = 7;
	var E = 8;
	var G = 10;
	var S = 22;
	var V = 25;
	var X = 27;
	var Y = 28;
	var Z = 29;

	var One = 30;
	var Nine = 38;
	var Zero = 39;

	var Return = 40;
	var Escape = 41;
	var Backspace = 42;
	var Tab = 43;
	var Space = 44;
	var Minus = 45;
	var Equals = 46;

	var Home = 74;
	var PageUp = 75;
	var Delete = 76;
	var End = 77;
	var PageDown = 78;
	var Right = 79;
	var Left = 80;
	var Down = 81;
	var Up = 82;

	public function name():String {
		return switch (cast this : Key) {
			case Return: "Return";
			case Escape: "Escape";
			case Backspace: "Backspace";
			case Tab: "Tab";
			case Space: "Space";
			case Delete: "Delete";
			case Right: "Right";
			case Left: "Left";
			case Down: "Down";
			case Up: "Up";
			case Home: "Home";
			case End: "End";
			case PageUp: "Page Up";
			case PageDown: "Page Down";
			case Zero: "0";
			case _:
				if (this >= 4 && this <= 29) String.fromCharCode("A".code + this - 4);
				else if (this >= 30 && this <= 38) String.fromCharCode("1".code + this - 30);
				else "";
		}
	}

	public function chord(mods:Mod):String {
		var out = "";
		if ((mods & Mod.Ctrl) != 0) out += "Ctrl+";
		if ((mods & Mod.Alt) != 0) out += "Alt+";
		if ((mods & Mod.Shift) != 0) out += "Shift+";
		return out + name();
	}
}
