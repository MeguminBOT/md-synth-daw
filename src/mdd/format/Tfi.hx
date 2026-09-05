package mdd.format;

import haxe.io.Bytes;
import mdd.song.Patch;

@:unreflective
final class Tfi {
	public static inline final BYTES = 42;

	public static function read(bytes:Bytes):Null<Patch> {
		if (bytes == null || bytes.length < BYTES) return null;

		final out = new Patch();

		out.algorithm = bytes.get(0) & 7;
		out.feedback = bytes.get(1) & 7;

		for (slot in 0...Patch.SLOTS) {
			final at = 2 + slot * 10;

			out.multiple[slot] = bytes.get(at) & 15;
			out.detune[slot] = bytes.get(at + 1) & 7;
			out.totalLevel[slot] = bytes.get(at + 2) & 127;
			out.keyScale[slot] = bytes.get(at + 3) & 3;
			out.attack[slot] = bytes.get(at + 4) & 31;
			out.decay[slot] = bytes.get(at + 5) & 31;
			out.sustain[slot] = bytes.get(at + 6) & 31;
			out.release[slot] = bytes.get(at + 7) & 15;
			out.sustainLevel[slot] = bytes.get(at + 8) & 15;
			out.ssg[slot] = bytes.get(at + 9) & 15;
		}

		return out;
	}

	public static function write(patch:Patch):Bytes {
		final out = Bytes.alloc(BYTES);

		out.set(0, patch.algorithm & 7);
		out.set(1, patch.feedback & 7);

		for (slot in 0...Patch.SLOTS) {
			final at = 2 + slot * 10;

			out.set(at, patch.multiple[slot] & 15);
			out.set(at + 1, patch.detune[slot] & 7);
			out.set(at + 2, patch.totalLevel[slot] & 127);
			out.set(at + 3, patch.keyScale[slot] & 3);
			out.set(at + 4, patch.attack[slot] & 31);
			out.set(at + 5, patch.decay[slot] & 31);
			out.set(at + 6, patch.sustain[slot] & 31);
			out.set(at + 7, patch.release[slot] & 15);
			out.set(at + 8, patch.sustainLevel[slot] & 15);
			out.set(at + 9, patch.ssg[slot] & 15);
		}

		return out;
	}

	public static function same(one:Patch, two:Patch):Bool {
		if (one.algorithm != two.algorithm || one.feedback != two.feedback) return false;

		for (slot in 0...Patch.SLOTS) {
			if (one.multiple[slot] != two.multiple[slot]) return false;
			if (one.detune[slot] != two.detune[slot]) return false;
			if (one.totalLevel[slot] != two.totalLevel[slot]) return false;
			if (one.keyScale[slot] != two.keyScale[slot]) return false;
			if (one.attack[slot] != two.attack[slot]) return false;
			if (one.decay[slot] != two.decay[slot]) return false;
			if (one.sustain[slot] != two.sustain[slot]) return false;
			if (one.release[slot] != two.release[slot]) return false;
			if (one.sustainLevel[slot] != two.sustainLevel[slot]) return false;
			if (one.ssg[slot] != two.ssg[slot]) return false;
		}

		return true;
	}
}
