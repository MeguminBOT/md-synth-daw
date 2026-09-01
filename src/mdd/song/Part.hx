package mdd.song;

enum abstract Part(Int) from Int to Int {
	var Fm1 = 0;
	var Fm2 = 1;
	var Fm3 = 2;
	var Fm4 = 3;
	var Fm5 = 4;
	var Fm6 = 5;
	var Psg1 = 6;
	var Psg2 = 7;
	var Psg3 = 8;
	var Noise = 9;
	var Dac = 10;

	public static inline final COUNT = 11;

	public inline function fm():Bool {
		return this <= 5;
	}

	public inline function square():Bool {
		return this >= 6 && this <= 8;
	}

	public inline function noise():Bool {
		return this == 9;
	}

	public inline function sampled():Bool {
		return this == 10;
	}

	public inline function index():Int {
		return this;
	}

	public function name():String {
		return switch (cast this : Part) {
			case Fm1: "FM1";
			case Fm2: "FM2";
			case Fm3: "FM3";
			case Fm4: "FM4";
			case Fm5: "FM5";
			case Fm6: "FM6";
			case Psg1: "PSG1";
			case Psg2: "PSG2";
			case Psg3: "PSG3";
			case Noise: "NOISE";
			case Dac: "DAC";
		}
	}
}
