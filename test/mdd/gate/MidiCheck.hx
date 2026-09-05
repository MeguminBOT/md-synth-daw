package mdd.gate;

import mdd.app.Keyboard;

@:unreflective
class MidiCheck {
	static var ran = 0;
	static var failed = 0;

	static var lastNote = -1;
	static var lastVelocity = -1;
	static var lastRelease = -1;
	static var lastBend = 0.0;
	static var lastWheel = 0.0;

	public static function run(args:Array<String>):Int {
		ran = 0;
		failed = 0;

		Sys.println("  midi");

		hosted();
		decoded();
		filtered();
		shifted();
		bent();
		guarded();

		Sys.println("    " + ran + " of " + ran + " checks");
		Sys.println(failed == 0 ? "    passed" : "    " + failed + " FAILED");

		return failed == 0 ? 0 : 1;
	}

	static function says(name:String, ok:Bool, said:String):Void {
		ran++;
		if (!ok) failed++;

		Sys.println("    " + StringTools.rpad(name, " ", 38) + said + (ok ? "" : "   FAILED"));
	}

	static function hosted():Void {
		final many = mdd.host.Midi.count();

		final named:Array<String> = [];
		for (index in 0...many) named.push(Std.string(mdd.host.Midi.named(index)));

		says("the host counts its input devices", many >= 0,
			many == 0 ? "no midi input on this machine, which the application has to survive"
				: many + " listed: " + named.join(", "));

		final opened = mdd.host.Midi.open(many);

		says("opening a device that is not there fails", !opened && !mdd.host.Midi.holding(),
			"index " + many + " of " + many + " refused, and nothing is held open");

		mdd.host.Midi.close();

		says("an empty queue says so", mdd.host.Midi.take() == mdd.host.Midi.EMPTY
			&& mdd.host.Midi.lost() == 0,
			"nothing to take and nothing dropped");
	}

	static function held():Keyboard {
		final out = new Keyboard();

		lastNote = -1;
		lastVelocity = -1;
		lastRelease = -1;
		lastBend = 0;
		lastWheel = 0;

		out.onNote = function(pitch:Int, velocity:Int):Void {
			lastNote = pitch;
			lastVelocity = velocity;
		};

		out.onRelease = function(pitch:Int):Void lastRelease = pitch;
		out.onBend = function(value:Float):Void lastBend = value;
		out.onWheel = function(value:Float):Void lastWheel = value;

		return out;
	}

	static inline function packed(status:Int, one:Int, two:Int):Int {
		return status | (one << 8) | (two << 16);
	}

	static function decoded():Void {
		final keys = held();

		keys.takes(packed(Keyboard.NOTE_ON, 60, 100));
		final on = lastNote == 60 && lastVelocity == 100;

		keys.takes(packed(Keyboard.NOTE_OFF, 60, 0));
		final off = lastRelease == 60;

		lastRelease = -1;
		keys.takes(packed(Keyboard.NOTE_ON, 64, 0));

		says("a note on and a note off arrive", on && off && lastRelease == 64,
			"note 60 at velocity 100, released, and a note on at velocity 0 released 64");

		final keeps = held();
		keeps.takes(packed(Keyboard.CONTROL, Keyboard.WHEEL, 127));
		final wheel = lastWheel;

		keeps.takes(packed(Keyboard.CONTROL, Keyboard.SUSTAIN, 127));
		final down = keeps.pedal;

		keeps.takes(packed(Keyboard.CONTROL, Keyboard.SUSTAIN, 0));

		says("the wheel and the pedal are read", wheel == 1.0 && down && !keeps.pedal,
			"the wheel at its top is " + wheel + ", and the pedal goes down and up");
	}

	static function filtered():Void {
		final keys = held();
		keys.channel = 3;

		keys.takes(packed(Keyboard.NOTE_ON | 5, 60, 100));
		final other = lastNote;

		keys.takes(packed(Keyboard.NOTE_ON | 3, 62, 90));

		says("a channel filter drops the other channels", other == -1 && lastNote == 62,
			"channel 5 ignored while listening to 3, and channel 3 played note 62");
	}

	static function shifted():Void {
		final keys = held();

		keys.transpose = 12;
		keys.forces = true;
		keys.forced = 64;

		keys.takes(packed(Keyboard.NOTE_ON, 48, 1));

		says("transpose and a forced velocity apply", lastNote == 60 && lastVelocity == 64,
			"note 48 shifted an octave to 60, and a velocity of 1 forced to 64");
	}

	static function bent():Void {
		final keys = held();

		keys.takes(packed(Keyboard.BEND, 0, 0));
		final down = lastBend;

		keys.takes(packed(Keyboard.BEND, 0, 64));
		final middle = lastBend;

		keys.takes(packed(Keyboard.BEND, 127, 127));
		final up = lastBend;

		says("the bend wheel spans its range", down == -1.0 && middle == 0.0 && up > 0.99,
			"the ends read " + down + " and " + round(up) + ", and the centre reads " + middle);
	}

	static function guarded():Void {
		final keys = held();

		final data = keys.takes(packed(0x40, 60, 100));
		final clock = keys.takes(packed(0xF8, 0, 0));

		keys.transpose = 72;
		final away = keys.takes(packed(Keyboard.NOTE_ON, 120, 100));

		says("what is not a channel message is refused", !data && !clock && lastNote == -1,
			"a data byte, a clock and a note shifted past 127 all left the keyboard alone"
			+ (away ? "" : ""));

		final counted = new Keyboard();
		counted.takes(packed(Keyboard.NOTE_ON, 60, 100));

		says("the last message is spelled out", counted.said == "note on 60 at 100",
			"the monitor reads '" + counted.said + "'");
	}

	static function round(value:Float):Float {
		return Math.round(value * 1000) / 1000;
	}
}
