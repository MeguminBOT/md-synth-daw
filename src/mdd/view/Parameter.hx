package mdd.view;

import mdd.app.Locale;
import mdd.song.Automation;
import mdd.song.Part;

@:unreflective

/**
	One thing about a channel that can be automated: which register it writes, what it
	is called, what range it takes, and what a value means.

	This is where the framework and the hardware meet. A control in `mdd.ui` knows
	nothing about a total level; this is what tells it that a value of 12 on operator
	four is register `$4C` and nine decibels down, which is what the tooltip shows.
**/
final class Parameter {
	/**
		Which lane of the channel it is, from `Automation`.
	**/
	public var target(default, null):Int;

	/**
		Which operator, for a per operator parameter.
	**/
	public var slot(default, null):Int;

	/**
		The smallest value it takes.
	**/
	public var low(default, null):Int;

	/**
		The largest.
	**/
	public var high(default, null):Int;

	/**
		Whether the value is a difference from the note rather than a value in its own
		right, which pitch is.
	**/
	public var offset(default, null):Bool;

	/**
		Whether a ramp between two values sounds continuous, which decides the shape a new
		point gets.
	**/
	public var smooth(default, null):Bool;

	/**
		Whether there is one of these per operator rather than one per channel.
	**/
	public var operators(default, null):Bool;

	/**
		What it is called, as the documentation writes it, which is never translated.
	**/
	public var name(default, null):String;

	/**
		A line saying what it does.
	**/
	public var about(default, null):Locale;

	/**
		What one step is worth in decibels, for a parameter that attenuates.
	**/
	public var decibels(default, null):Float;

	/**
		Private: the list is built by `of`.

		@param target Which lane.
		@param slot Which operator.
		@param low The smallest value.
		@param high The largest.
		@param name What it is called.
		@param about A line saying what it does.
	**/
	function new(target:Int, slot:Int, low:Int, high:Int, name:String, about:Locale) {
		this.target = target;
		this.slot = slot;
		this.low = low;
		this.high = high;
		this.name = name;
		this.about = about;

		offset = false;
		smooth = false;
		operators = false;
		decibels = 0;
	}

	static function made(target:Int, slot:Int, low:Int, high:Int, name:String,
			about:Locale):Parameter {
		return new Parameter(target, slot, low, high, name, about);
	}

	/**
		@return The same parameter marked as one that changes a sounding note rather than setting
			one up.
	**/
	function rides():Parameter {
		offset = true;
		return this;
	}

	/**
		@return The same parameter marked as one a ramp sounds continuous on.
	**/
	function ramps():Parameter {
		smooth = true;
		return this;
	}

	/**
		@return The same parameter marked as one there is one of per operator.
	**/
	function slotted():Parameter {
		operators = true;
		return this;
	}

	/**
		@param much What one step is worth in decibels.
		@return The same parameter, marked as attenuating.
	**/
	function quiets(much:Float):Parameter {
		decibels = much;
		return this;
	}

	/**
		@param slot Which operator.
		@return What to call it here, with the operator number where there is one of these per
			operator.
	**/
	public function titled(slot:Int):String {
		return operators ? name + " " + (slot + 1) : name;
	}

	/**
		@return Whether a value of it means a number of decibels.
	**/
	public function attenuates():Bool {
		return decibels != 0;
	}

	/**
		@param value A value.
		@return It held inside the range.
	**/
	public function holds(value:Int):Int {
		return value < low ? low : (value > high ? high : value);
	}

	/**
		@param value A value.
		@return What it means: the raw number, and the decibels or the semitones where the parameter
			has them.
	**/
	public function said(value:Int):String {
		if (decibels == 0) return (offset && value > 0 ? "+" : "") + value;

		final much = -value * decibels;
		final one = Math.round(much * 10) / 10;

		return (offset && value > 0 ? "+" : "") + value + "  "
			+ (one > 0 ? "+" : "") + one + " dB";
	}

	/**
		The highest instrument index a preset lane reaches.
	**/
	static inline final PRESETS = 1023;

	static final FM:Array<Parameter> = fm();
	static final SQUARE:Array<Parameter> = square();
	static final NOISE:Array<Parameter> = noise();
	static final SAMPLED:Array<Parameter> = sampled();

	static final NONE:Array<Parameter> = [];

	static final FM_MOVED:Array<Parameter> = fmMoved();
	static final SQUARE_MOVED:Array<Parameter> = [pitch()];
	static final NOISE_MOVED:Array<Parameter> = [made(Automation.TUNE, 0, 0, 15, "NOISE", Locale.PARAM_NOISE)];

	/**
		@param part A part.
		@return Every parameter a preset for that part may move on each of its notes: an FM part's
			own, with pitch in cents in place of the pattern's pitch and no preset lane, a square's
			pitch, and the noise channel's mode. A square's and the noise channel's level is their
			envelope's.
	**/
	public static function moved(part:Part):Array<Parameter> {
		if (part.fm()) return FM_MOVED;
		if (part.square()) return SQUARE_MOVED;
		if (part.noise()) return NOISE_MOVED;

		return NONE;
	}

	/**
		@param part A part.
		@param target Which lane.
		@param slot Which operator.
		@return That parameter as a preset moves it, or null where a preset for the part cannot.
	**/
	public static function movedFound(part:Part, target:Int, slot:Int):Null<Parameter> {
		for (held in moved(part)) {
			if (held.target != target) continue;
			if (held.operators) return held;
			if (held.slot == slot) return held;
		}

		return null;
	}

	static function pitch():Parameter {
		return made(Automation.PITCH, 0, -4800, 4800, "PITCH", Locale.PARAM_PITCH).rides().ramps();
	}

	static function fmMoved():Array<Parameter> {
		final out:Array<Parameter> = [];

		for (held in fm()) {
			if (held.target == Automation.TUNE) out.push(pitch());
			else if (held.target != Automation.INSTRUMENT) out.push(held);
		}

		return out;
	}

	/**
		@param part A part.
		@return Every parameter that part has, built once per call.
	**/
	public static function of(part:Part):Array<Parameter> {
		if (part.fm()) return FM;
		if (part.square()) return SQUARE;
		if (part.noise()) return NOISE;
		if (part.sampled()) return SAMPLED;

		return NONE;
	}

	/**
		@param part A part.
		@param target Which lane.
		@param slot Which operator.
		@return That parameter, or null where the part does not have it.
	**/
	public static function found(part:Part, target:Int, slot:Int):Null<Parameter> {
		for (held in of(part)) {
			if (held.target != target) continue;
			if (held.operators) return held;
			if (held.slot == slot) return held;
		}

		return null;
	}

	static function fm():Array<Parameter> {
		return [
			made(Automation.LEVEL, 0, -127, 127, "TL", Locale.PARAM_LEVEL)
				.rides().ramps().slotted().quiets(0.75),
			made(Automation.TUNE, 0, -2048, 2048, "FREQ", Locale.PARAM_FREQUENCY)
				.rides().ramps(),
			made(Automation.SIDES, 0, 0, 255, "SIDES", Locale.PARAM_SIDES),
			made(Automation.TIMBRE, 0, 0, 127, "DT MUL", Locale.PARAM_TIMBRE).slotted(),
			made(Automation.ATTACK, 0, 0, 255, "KS AR", Locale.PARAM_ATTACK).slotted(),
			made(Automation.DECAY, 0, 0, 255, "AM D1R", Locale.PARAM_DECAY).slotted(),
			made(Automation.SUSTAIN, 0, 0, 31, "D2R", Locale.PARAM_SUSTAIN)
				.ramps().slotted(),
			made(Automation.RELEASE, 0, 0, 255, "D1L RR", Locale.PARAM_RELEASE).slotted(),
			made(Automation.LOOP, 0, 0, 15, "SSG", Locale.PARAM_LOOP).slotted(),
			made(Automation.WIRING, 0, 0, 63, "FB ALG", Locale.PARAM_WIRING),
			made(Automation.INSTRUMENT, 0, 0, PRESETS, "PRESET", Locale.PARAM_PRESET)
		];
	}

	static function square():Array<Parameter> {
		return [
			made(Automation.LEVEL, 0, -15, 15, "LEVEL", Locale.PARAM_ATTENUATION)
				.rides().ramps().quiets(2),
			made(Automation.TUNE, 0, -1023, 1023, "PERIOD", Locale.PARAM_PERIOD)
				.rides().ramps(),
			made(Automation.INSTRUMENT, 0, 0, PRESETS, "PRESET", Locale.PARAM_PRESET)
		];
	}

	static function noise():Array<Parameter> {
		return [
			made(Automation.LEVEL, 0, -15, 15, "LEVEL", Locale.PARAM_ATTENUATION)
				.rides().ramps().quiets(2),
			made(Automation.TUNE, 0, 0, 15, "NOISE", Locale.PARAM_NOISE),
			made(Automation.INSTRUMENT, 0, 0, PRESETS, "PRESET", Locale.PARAM_PRESET)
		];
	}

	static function sampled():Array<Parameter> {
		return [made(Automation.TUNE, 0, 0, 1, "DAC", Locale.PARAM_CONVERTER)];
	}
}
