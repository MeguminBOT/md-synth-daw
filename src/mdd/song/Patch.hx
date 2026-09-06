package mdd.song;

import haxe.ds.Vector;

@:unreflective
final class Patch {
	public static inline final SLOTS = 4;

	public static inline final ROWS = 10;
	public static inline final DIALS = 4;

	public static inline final ALGORITHM = 0;
	public static inline final FEEDBACK = 1;
	public static inline final AMS = 2;
	public static inline final PMS = 3;

	public static final NAMES:Array<String> = ["TL", "AR", "D1R", "D1L", "D2R", "RR", "MUL",
		"DT", "RS", "SSG"];

	public static final SPELT:Array<String> = ["Total level", "Attack rate",
		"First decay rate", "Sustain level", "Second decay rate", "Release rate", "Multiple",
		"Detune", "Rate scaling", "SSG envelope"];

	public static final DIAL_NAMES:Array<String> = ["ALG", "FB", "AMS", "PMS"];

	public static final DIAL_SPELT:Array<String> = ["Algorithm", "Feedback", "Tremolo",
		"Vibrato"];

	static final DIAL_MOST:Array<Int> = [7, 7, 3, 7];

	public var algorithm:Int = 0;
	public var feedback:Int = 0;
	public var ams:Int = 0;
	public var pms:Int = 0;

	public final detune:Vector<Int> = new Vector<Int>(SLOTS);
	public final multiple:Vector<Int> = new Vector<Int>(SLOTS);
	public final totalLevel:Vector<Int> = new Vector<Int>(SLOTS);
	public final keyScale:Vector<Int> = new Vector<Int>(SLOTS);
	public final attack:Vector<Int> = new Vector<Int>(SLOTS);
	public final decay:Vector<Int> = new Vector<Int>(SLOTS);
	public final sustain:Vector<Int> = new Vector<Int>(SLOTS);
	public final sustainLevel:Vector<Int> = new Vector<Int>(SLOTS);
	public final release:Vector<Int> = new Vector<Int>(SLOTS);
	public final ssg:Vector<Int> = new Vector<Int>(SLOTS);
	public final tremolo:Vector<Bool> = new Vector<Bool>(SLOTS);

	public function new() {
		for (i in 0...SLOTS) {
			detune[i] = 0;
			multiple[i] = 1;
			totalLevel[i] = i == SLOTS - 1 ? 0 : 127;
			keyScale[i] = 0;
			attack[i] = 31;
			decay[i] = 0;
			sustain[i] = 0;
			sustainLevel[i] = 0;
			release[i] = 15;
			ssg[i] = 0;
			tremolo[i] = false;
		}
	}

	public static function mostOf(row:Int):Int {
		return switch (row) {
			case 0: 127;
			case 1, 2, 4, 5: 31;
			case 3: 15;
			case 6: 15;
			case 7: 7;
			case 8: 3;
			case _: 15;
		}
	}

	public static function mostDial(which:Int):Int {
		return which < 0 || which >= DIALS ? 0 : DIAL_MOST[which];
	}

	public function reads(slot:Int, row:Int):Int {
		return switch (row) {
			case 0: totalLevel[slot];
			case 1: attack[slot];
			case 2: decay[slot];
			case 3: sustainLevel[slot];
			case 4: sustain[slot];
			case 5: release[slot];
			case 6: multiple[slot];
			case 7: detune[slot];
			case 8: keyScale[slot];
			case _: ssg[slot];
		}
	}

	public function writes(slot:Int, row:Int, value:Int):Void {
		final most = mostOf(row);
		final want = value < 0 ? 0 : (value > most ? most : value);

		switch (row) {
			case 0: totalLevel[slot] = want;
			case 1: attack[slot] = want;
			case 2: decay[slot] = want;
			case 3: sustainLevel[slot] = want;
			case 4: sustain[slot] = want;
			case 5: release[slot] = want;
			case 6: multiple[slot] = want;
			case 7: detune[slot] = want;
			case 8: keyScale[slot] = want;
			case _: ssg[slot] = want;
		}
	}

	public function dial(which:Int):Int {
		return switch (which) {
			case ALGORITHM: algorithm;
			case FEEDBACK: feedback;
			case AMS: ams;
			case _: pms;
		}
	}

	public function turns(which:Int, value:Int):Void {
		final most = mostDial(which);
		final want = value < 0 ? 0 : (value > most ? most : value);

		switch (which) {
			case ALGORITHM: algorithm = want;
			case FEEDBACK: feedback = want;
			case AMS: ams = want;
			case _: pms = want;
		}
	}

	public function carries(slot:Int):Bool {
		return switch (algorithm) {
			case 0, 1, 2, 3: slot == 3;
			case 4: slot == 1 || slot == 3;
			case 5, 6: slot == 1 || slot == 2 || slot == 3;
			case _: true;
		}
	}

	public function raises():Void {
		var least = 127;

		for (slot in 0...SLOTS) {
			if (!carries(slot)) continue;
			if (totalLevel[slot] < least) least = totalLevel[slot];
		}

		if (least <= 0 || least > 127) return;

		for (slot in 0...SLOTS) {
			if (!carries(slot)) continue;
			totalLevel[slot] -= least;
		}
	}

	public function copy():Patch {
		final out = new Patch();

		out.algorithm = algorithm;
		out.feedback = feedback;
		out.ams = ams;
		out.pms = pms;

		for (i in 0...SLOTS) {
			out.detune[i] = detune[i];
			out.multiple[i] = multiple[i];
			out.totalLevel[i] = totalLevel[i];
			out.keyScale[i] = keyScale[i];
			out.attack[i] = attack[i];
			out.decay[i] = decay[i];
			out.sustain[i] = sustain[i];
			out.sustainLevel[i] = sustainLevel[i];
			out.release[i] = release[i];
			out.ssg[i] = ssg[i];
			out.tremolo[i] = tremolo[i];
		}

		return out;
	}
}
