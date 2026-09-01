package mdd.gate;

import mdd.chip.Sn76489;

@:unreflective
class PsgCheck {
	static inline final LATCH = 0x80;
	static inline final TONE0 = 0x00;
	static inline final VOLUME0 = 0x10;
	static inline final TONE2 = 0x40;
	static inline final NOISE = 0x60;
	static inline final VOLUME3 = 0x70;
	static inline final OFF = 0x0F;

	static inline final REPEATS = 57337;

	static var failed:Int = 0;
	static var ran:Int = 0;

	public static function run(args:Array<String>):Int {
		failed = 0;
		ran = 0;

		Sys.println("  psg");

		registers();
		volumes();
		tones();
		noise();
		periodic();
		rates();

		Sys.println("    " + (ran - failed) + " of " + ran + " checks");

		if (failed > 0) {
			Sys.println("    failed");
			return 1;
		}

		Sys.println("    passed");
		return 0;
	}

	static function says(name:String, ok:Bool, said:String):Void {
		ran++;
		if (!ok) failed++;
		Sys.println("    " + StringTools.rpad(name, " ", 22) + said + (ok ? "" : "   FAILED"));
	}

	static function same(name:String, got:Int, wanted:Int, said:String):Void {
		says(name, got == wanted, said + ", got " + got);
	}

	static function sameHex(name:String, got:Int, wanted:Int, digits:Int, said:String):Void {
		says(name, got == wanted, said + ", got " + StringTools.hex(got, digits));
	}

	static function near(name:String, got:Int, wanted:Int, slack:Int, said:String):Void {
		final off = got - wanted;
		says(name, (off < 0 ? -off : off) <= slack, said + ", got " + got);
	}

	static function silent():Sn76489 {
		final psg = new Sn76489();
		for (channel in 0...4) psg.write(LATCH | VOLUME0 | (channel << 5) | OFF);
		return psg;
	}

	static function sounding(register:Int, period:Int):Sn76489 {
		final psg = silent();
		psg.write(LATCH | register | (period & 0x0F));
		psg.write((period >> 4) & 0x3F);
		psg.write(LATCH | VOLUME0 | (register << 1 & 0x60) | 0x00);
		return psg;
	}

	static function registers():Void {
		final psg = new Sn76489();

		psg.write(LATCH | TONE0 | 0x0A);
		sameHex("latch a period", psg.tone[0], 0x00A, 3, "the low four bits of one");

		psg.write(0x35);
		sameHex("data a period", psg.tone[0], 0x35A, 3, "the six bits above them");

		psg.write(LATCH | TONE2 | 0x07);
		psg.write(0x3F);
		sameHex("a channel of its own", psg.tone[2], 0x3F7, 3, "the third channel holds");
		sameHex("and the first is kept", psg.tone[0], 0x35A, 3, "the first is untouched at");

		psg.write(LATCH | VOLUME0 | 0x09);
		same("latch an attenuation", psg.attenuation[0], 9, "four bits of one");

		psg.write(0x3F);
		same("data an attenuation", psg.attenuation[0], 0x0F,
			"four bits again, not six, of 3F");
	}

	static function volumes():Void {
		final psg = silent();

		psg.write(LATCH | VOLUME0 | OFF);
		same("silence", psg.level(), 0, "attenuation fifteen is nothing at all");

		psg.write(LATCH | VOLUME0 | 0x00);
		final loudest = psg.level();
		says("loudest", loudest > 0, "attenuation zero is " + loudest);

		var previous = loudest;
		var held = 0;
		var worst = 0;

		for (step in 1...15) {
			psg.write(LATCH | VOLUME0 | step);

			final now = psg.level();
			final want = Math.round(previous * 0.794328);
			final off = now - want;
			final wide = off < 0 ? -off : off;

			if (wide > worst) worst = wide;
			if (wide <= 1) held++;

			previous = now;
		}

		says("two decibels a step", held == 14,
			held + " of 14 steps are the ratio applied again, worst off by " + worst);
	}

	static function toggles(psg:Sn76489, steps:Int):Int {
		var previous = psg.level();
		var seen = 0;

		for (i in 0...steps) {
			psg.run(Sn76489.DIVIDER);
			final now = psg.level();
			if (now != previous) seen++;
			previous = now;
		}

		return seen;
	}

	static function tones():Void {
		for (period in [1, 2, 16, 100, 1023]) {
			final psg = sounding(TONE0, period);
			near("period " + period, toggles(psg, period * 64), 64, 1,
				"toggles once every " + period + " counts");
		}

		final psg = sounding(TONE0, 0);
		final seen = toggles(psg, 4096);

		same("period zero", seen, 0, "never toggles across 4096 counts");
		says("and holds high", psg.level() > 0, "the output stays at " + psg.level());
	}

	static function noise():Void {
		final psg = silent();

		psg.write(LATCH | NOISE | 0x04);
		psg.write(LATCH | VOLUME3 | 0x00);

		for (i in 0...100) psg.run(Sn76489.DIVIDER * 0x10);
		says("the register moves", psg.shift != 0x8000,
			"a hundred shifts leave it at " + StringTools.hex(psg.shift, 4));

		psg.write(LATCH | NOISE | 0x04);
		sameHex("a write resets it", psg.shift, 0x8000, 4, "back to");

		var zero = false;
		var steps = 0;

		while (steps <= REPEATS) {
			psg.run(Sn76489.DIVIDER * 0x10);
			steps++;
			if (psg.shift == 0) zero = true;
			if (psg.shift == 0x8000) break;
		}

		says("never zero", !zero, "white noise never shifts itself to a dead register");
		same("white noise repeats", steps, REPEATS, "after as many shifts as the taps allow");
	}

	static function periodic():Void {
		final psg = silent();

		psg.write(LATCH | NOISE | 0x00);
		psg.write(LATCH | VOLUME3 | 0x00);

		var high = 0;
		for (i in 0...(16 * 64)) {
			psg.run(Sn76489.DIVIDER * 0x10);
			if ((psg.shift & 1) != 0) high++;
		}

		same("periodic noise", high, 64, "high one shift in sixteen across 1024");
	}

	static function rates():Void {
		final psg = silent();
		psg.write(LATCH | VOLUME3 | 0x00);

		for (mode in 0...3) {
			psg.write(LATCH | NOISE | 0x04 | mode);

			final every = 0x10 << mode;
			var shifts = 0;
			var previous = psg.shift;

			for (i in 0...(every * 64)) {
				psg.run(Sn76489.DIVIDER);
				if (psg.shift != previous) shifts++;
				previous = psg.shift;
			}

			near("noise every " + every, shifts, 64, 32, "64 shifts across " + (every * 64));
		}

		psg.write(LATCH | TONE2 | 0x00);
		psg.write(0x04);
		psg.write(LATCH | NOISE | 0x07);

		var shifts = 0;
		var previous = psg.shift;

		for (i in 0...(0x40 * 64)) {
			psg.run(Sn76489.DIVIDER);
			if (psg.shift != previous) shifts++;
			previous = psg.shift;
		}

		near("noise on channel 3", shifts, 64, 32, "shifts at the third channel's own period");
	}
}
