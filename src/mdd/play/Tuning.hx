package mdd.play;

@:unreflective
final class Tuning {
	public static inline final FNUM = 0x7FF;
	public static inline final BLOCKS = 7;
	public static inline final RAW = false;

	public static inline function blockIn(word:Int):Int {
		return (word >> 11) & BLOCKS;
	}

	public static inline function fnumIn(word:Int):Int {
		return word & FNUM;
	}

	public static function offset(word:Int, note:Int):Int {
		if (RAW) return word - Stream.wordOf(note);

		final block = Stream.blockOf(note);

		var held = blockIn(word);
		var fnum = fnumIn(word);

		while (held > block) {
			fnum <<= 1;
			held--;
		}

		while (held < block) {
			fnum >>= 1;
			held++;
		}

		return fnum - Stream.frequencyOf(note);
	}

	public static function word(offset:Int, note:Int):Int {
		if (RAW) {
			final held = Stream.wordOf(note) + offset;
			return held < 0 ? 0 : (held > 0x3FFF ? 0x3FFF : held);
		}

		var block = Stream.blockOf(note);
		var fnum = Stream.frequencyOf(note) + offset;

		if (fnum < 0) fnum = 0;

		while (fnum > FNUM && block < BLOCKS) {
			fnum >>= 1;
			block++;
		}

		if (fnum > FNUM) fnum = FNUM;

		return ((block & BLOCKS) << 11) | (fnum & FNUM);
	}
}
