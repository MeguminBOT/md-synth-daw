package mdd.ui;

enum abstract Key(Int) from Int to Int {
	var Unknown = 0;

	var A = 4;
	var B = 5;
	var C = 6;
	var D = 7;
	var E = 8;
	var F = 9;
	var G = 10;
	var H = 11;
	var I = 12;
	var J = 13;
	var K = 14;
	var L = 15;
	var M = 16;
	var N = 17;
	var O = 18;
	var P = 19;
	var Q = 20;
	var R = 21;
	var S = 22;
	var T = 23;
	var U = 24;
	var V = 25;
	var W = 26;
	var X = 27;
	var Y = 28;
	var Z = 29;

	var One = 30;
	var Two = 31;
	var Three = 32;
	var Four = 33;
	var Five = 34;
	var Six = 35;
	var Seven = 36;
	var Eight = 37;
	var Nine = 38;
	var Zero = 39;

	var Return = 40;
	var Escape = 41;
	var Backspace = 42;
	var Tab = 43;
	var Space = 44;
	var Minus = 45;
	var Comma = 54;
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
			case Comma: ",";
			case Minus: "-";
			case Equals: "=";
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
