package mdd.view;

import mdd.app.Locale;
import mdd.song.Automation;
import mdd.song.Part;

@:unreflective
final class Parameter {
	public var target(default, null):Int;
	public var slot(default, null):Int;

	public var low(default, null):Int;
	public var high(default, null):Int;

	public var offset(default, null):Bool;
	public var smooth(default, null):Bool;
	public var operators(default, null):Bool;

	public var name(default, null):String;
	public var about(default, null):String;

	public var decibels(default, null):Float;

	function new(target:Int, slot:Int, low:Int, high:Int, name:String, about:String) {
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
			about:String):Parameter {
		return new Parameter(target, slot, low, high, name, about);
	}

	function rides():Parameter {
		offset = true;
		return this;
	}

	function ramps():Parameter {
		smooth = true;
		return this;
	}

	function slotted():Parameter {
		operators = true;
		return this;
	}

	function quiets(much:Float):Parameter {
		decibels = much;
		return this;
	}

	public function titled(slot:Int):String {
		return operators ? name + " " + (slot + 1) : name;
	}

	public function attenuates():Bool {
		return decibels != 0;
	}

	public function holds(value:Int):Int {
		return value < low ? low : (value > high ? high : value);
	}

	public function said(value:Int):String {
		if (decibels == 0) return (offset && value > 0 ? "+" : "") + value;

		final much = -value * decibels;
		final one = Math.round(much * 10) / 10;

		return (offset && value > 0 ? "+" : "") + value + "  "
			+ (one > 0 ? "+" : "") + one + " dB";
	}

	static final FM:Array<Parameter> = fm();
	static final SQUARE:Array<Parameter> = square();
	static final NOISE:Array<Parameter> = noise();
	static final SAMPLED:Array<Parameter> = sampled();

	static final NONE:Array<Parameter> = [];

	public static function of(part:Part):Array<Parameter> {
		if (part.fm()) return FM;
		if (part.square()) return SQUARE;
		if (part.noise()) return NOISE;
		if (part.sampled()) return SAMPLED;

		return NONE;
	}

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
			made(Automation.WIRING, 0, 0, 63, "FB ALG", Locale.PARAM_WIRING)
		];
	}

	static function square():Array<Parameter> {
		return [
			made(Automation.LEVEL, 0, -15, 15, "LEVEL", Locale.PARAM_ATTENUATION)
				.rides().ramps().quiets(2),
			made(Automation.TUNE, 0, -1023, 1023, "PERIOD", Locale.PARAM_PERIOD)
				.rides().ramps()
		];
	}

	static function noise():Array<Parameter> {
		return [
			made(Automation.LEVEL, 0, -15, 15, "LEVEL", Locale.PARAM_ATTENUATION)
				.rides().ramps().quiets(2),
			made(Automation.TUNE, 0, 0, 15, "NOISE", Locale.PARAM_NOISE)
		];
	}

	static function sampled():Array<Parameter> {
		return [made(Automation.TUNE, 0, 0, 1, "DAC", Locale.PARAM_CONVERTER)];
	}
}
