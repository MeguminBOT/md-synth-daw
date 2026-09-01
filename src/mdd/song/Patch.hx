package mdd.song;

import haxe.ds.Vector;

@:unreflective
final class Patch {
	public static inline final SLOTS = 4;

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

	public function carries(slot:Int):Bool {
		return switch (algorithm) {
			case 0, 1, 2, 3: slot == 3;
			case 4: slot == 1 || slot == 3;
			case 5, 6: slot == 1 || slot == 2 || slot == 3;
			case _: true;
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
