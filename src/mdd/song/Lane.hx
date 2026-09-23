package mdd.song;

/**
	One part worth of a pattern: its notes, in tick order, and the automation lanes
	that ride them.
**/
@:unreflective
final class Lane {
	/**
		The shortest a lane ever reports itself as, so an empty pattern still has room to
		be written into.
	**/
	static inline final FLOOR = 1536;

	/**
		Which part this lane is for.
	**/
	public var part(default, null):Part;

	/**
		The notes, kept in tick order.
	**/
	public final notes:Array<Note> = [];

	var held:Int = 0;

	/**
		The automation lanes riding these notes.
	**/
	public final automation:Array<Automation> = [];

	/**
		Builds an empty lane.

		@param part Which part it is for.
	**/
	public function new(part:Part) {
		this.part = part;
	}

	/**
		How long the lane is, which is the last note end or the floor, whichever is more.
	**/
	public var reach(get, never):Int;

	function get_reach():Int {
		return held < FLOOR ? FLOOR : held;
	}

	/**
		Makes sure the lane reports itself as at least this long.

		@param length The length in ticks.
	**/
	public function grow(length:Int):Void {
		if (length > held) held = length;
	}

	/**
		Puts a note in, in tick order.

		@param note The note to add.
		@return The same note.
	**/
	public function add(note:Note):Note {
		var at = notes.length;
		while (at > 0 && notes[at - 1].at > note.at) at--;

		notes.insert(at, note);
		grow(note.length);

		return note;
	}

	/**
		Takes a note out.

		@param note The note to remove.
		@return False where it was not in this lane.
	**/
	public function remove(note:Note):Bool {
		return notes.remove(note);
	}

	/**
		Puts the notes back in tick order, which moving one can break.
	**/
	public function sort():Void {
		held = 0;
		for (note in notes) grow(note.length);

		for (i in 1...notes.length) {
			final note = notes[i];
			var at = i;

			while (at > 0 && after(notes[at - 1], note)) {
				notes[at] = notes[at - 1];
				at--;
			}

			notes[at] = note;
		}
	}

	/**
		@param a One note.
		@param b Another.
		@return Whether the first sorts after the second.
	**/
	static inline function after(a:Note, b:Note):Bool {
		return a.at != b.at ? a.at > b.at : a.pitch > b.pitch;
	}

	/**
		Finds a note by search rather than by walking every one, so a long lane costs no
		more to read than a short one. It relies on the notes being in tick order.

		@param tick A tick.
		@return The index of the first note starting at or after it, which is the note count
			where none does. The last note starting at or before a tick is one before
			`seek(tick + 1)`.
	**/
	public function seek(tick:Int):Int {
		var low = 0;
		var high = notes.length;

		while (low < high) {
			final middle = (low + high) >> 1;

			if (notes[middle].at < tick) low = middle + 1;
			else high = middle;
		}

		return low;
	}

	/**
		@return The tick the last note finishes on.
	**/
	public function longest():Int {
		var most = 0;
		for (note in notes) if (note.ends() > most) most = note.ends();
		return most;
	}
}
