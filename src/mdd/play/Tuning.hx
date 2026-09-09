package mdd.play;

/**
	The difference between the frequency word a driver actually wrote and the one this
	application would write for the same note.

	A key on is read as the nearest semitone, and writing that semitone back gives a
	word one or two units from the original, because every driver carries its own table
	and rounds it its own way. It is a fraction of a cent and inaudible on its own, and
	it is wrong on nearly every frame: one imported piece disagreed with its file on 85
	per cent of sampled frames until the exact word was recorded beside the note.

	Recording the difference rather than the word keeps the note the editable thing
	while the import stays exact.
**/
@:unreflective
final class Tuning {
	/**
		The mask of the frequency word.
	**/
	static inline final FNUM = 0x7FF;

	/**
		The highest block the part has.
	**/
	static inline final BLOCKS = 7;

	/**
		Whether an offset is the plain difference of two packed words instead of a
		difference of frequency words at a common block. The plain difference jumps at an
		octave boundary, so it is off.
	**/
	static inline final RAW = false;

	/**
		@param word A packed block and frequency word.
		@return The block in it.
	**/
	static inline function blockIn(word:Int):Int {
		return (word >> 11) & BLOCKS;
	}

	/**
		@param word A packed block and frequency word.
		@return The frequency word in it.
	**/
	static inline function fnumIn(word:Int):Int {
		return word & FNUM;
	}

	/**
		Measures how far a written word is from the note it was read as.

		@param word The packed word the driver wrote.
		@param note The note it was read as.
		@return The difference in frequency word units, at the note's own block.
	**/
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

	/**
		Puts a note and its recorded offset back together as the word to write.

		@param offset The difference `offset` measured.
		@param note The note being played.
		@return The packed block and frequency word, carried up an octave where the frequency word
			would otherwise overflow.
	**/
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
