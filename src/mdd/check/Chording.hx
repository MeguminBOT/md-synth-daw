package mdd.check;

import mdd.song.Note;
import mdd.song.Scale;

/**
	Finds where a piece asks one channel to play a chord.

	Every part of this console sounds one note at a time. A file written for something
	that does not, which is most of them, puts three notes on one channel and expects a
	chord: what the hardware does instead is play whichever note keyed on last and drop
	the rest. Nothing is wrong with the file and nothing is wrong with the import, but
	what comes out is not what went in, and until this told anybody, the only sign was a
	warning in a list nobody opens on the way in.

	**Notes merely overlapping are left alone.** A line played legato has each note
	running a little past the start of the next, which a monophonic channel handles
	exactly as intended: the new note takes the voice. Treating that as a chord would
	strip a melody down to every other note. What is looked for is notes starting
	together, within `TOGETHER`, which is what a chord is.
**/
@:unreflective
class Chording {
	/**
		How far apart two notes may start and still be a chord rather than a line, in
		ticks at 96 to the quarter. A thirty second note: wider than the jitter a
		performance carries and narrower than anything meant as two notes.
	**/
	public static inline final TOGETHER = 12;

	/**
		How many of the twelve a part may use before it is called chromatic, and the key
		is given up on. A piece using this many is either atonal or a drum part, and
		neither has a note that is more in key than another.
	**/
	public static inline final ATONAL = 10;

	/**
		Works out what key a run of notes is in.

		Every major and minor key is tried and the one holding the most notes wins, which
		is the oldest way of doing this and good enough for deciding which note of a chord
		to keep. Where the notes use most of the twelve there is no key to find and the
		chromatic scale comes back, which `holds` answers true to for everything, so
		nothing downstream has to know the difference.

		@param notes The notes to read, in any order.
		@return The key they are most nearly in, or a chromatic scale where there is none.
	**/
	public static function keyed(notes:Array<Note>):Scale {
		final seen = new haxe.ds.Vector<Int>(12);
		for (index in 0...12) seen[index] = 0;

		var many = 0;

		for (note in notes) {
			seen[((note.pitch % 12) + 12) % 12]++;
			many++;
		}

		if (many == 0) return new Scale(0, Scale.CHROMATIC);

		var used = 0;
		for (index in 0...12) if (seen[index] > 0) used++;

		if (used >= ATONAL) return new Scale(0, Scale.CHROMATIC);

		var bestRoot = 0;
		var bestKind = Scale.CHROMATIC;
		var best = -1;

		for (kind in [Scale.MAJOR, Scale.MINOR]) {
			for (root in 0...12) {
				final held = new Scale(root, kind);
				var score = 0;

				for (index in 0...12) if (held.holds(index)) score += seen[index];

				if (score <= best) continue;

				best = score;
				bestRoot = root;
				bestKind = kind;
			}
		}

		return best <= 0 ? new Scale(0, Scale.CHROMATIC) : new Scale(bestRoot, bestKind);
	}

	/**
		Finds the notes a part will never sound.

		Notes starting together are a chord, and one of them keeps the voice: the one in
		key, and the highest of those where more than one is, because the top of a chord
		is what a listener follows and what a chip arrangement usually keeps. Where no key
		was found every note is in key, so the highest simply wins.

		@param notes One part's notes, in tick order.
		@param key What key they are in, from `keyed`.
		@return The notes that cannot sound, in tick order. The ones that can are not in
			it, so the two together are the whole lane.
	**/
	public static function silenced(notes:Array<Note>, key:Scale):Array<Note> {
		final out:Array<Note> = [];

		var index = 0;

		while (index < notes.length) {
			final first = notes[index];
			var last = index;

			while (last + 1 < notes.length && notes[last + 1].at - first.at <= TOGETHER) last++;

			if (last == index) {
				index++;
				continue;
			}

			var keeping = first;

			for (at in index...last + 1) {
				if (better(notes[at], keeping, key)) keeping = notes[at];
			}

			for (at in index...last + 1) if (notes[at] != keeping) out.push(notes[at]);

			index = last + 1;
		}

		return out;
	}

	/**
		@param note A note of a chord.
		@param than The one currently being kept.
		@param key What key the part is in.
		@return Whether the first should keep the voice instead.
	**/
	static function better(note:Note, than:Note, key:Scale):Bool {
		final held = key.holds(note.pitch);
		final was = key.holds(than.pitch);

		if (held != was) return held;

		return note.pitch > than.pitch;
	}
}
