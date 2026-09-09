package mdd.song;

/**
	One of the eleven parts the machine has, and there are no others: six FM channels,
	three squares, the noise channel and the sample channel.

	A part is a fixed hardware channel rather than a track. Tracks are an arrangement
	idea and live in `Track`; this is what the chips actually carry.
**/
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

	/**
		How many parts there are.
	**/
	public static inline final COUNT = 11;

	/**
		@return Whether this is one of the six FM channels.
	**/
	public inline function fm():Bool {
		return this <= 5;
	}

	/**
		@return Whether this is one of the three square channels.
	**/
	public inline function square():Bool {
		return this >= 6 && this <= 8;
	}

	/**
		@return Whether this is the noise channel.
	**/
	public inline function noise():Bool {
		return this == 9;
	}

	/**
		@return Whether this is the sample channel.
	**/
	public inline function sampled():Bool {
		return this == 10;
	}

	/**
		@return This part as a number from 0 to 10, for indexing a vector by part.
	**/
	public inline function index():Int {
		return this;
	}

	/**
		@return Which chip it belongs to, for grouping in the interface.
	**/
	public function family():String {
		if (fm()) return "FM";
		if (square()) return "PSG";
		if (noise()) return "NOISE";

		return "DAC";
	}

	/**
		@return The name the documentation uses, which is never translated.
	**/
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
