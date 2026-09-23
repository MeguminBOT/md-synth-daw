package mdd.song;

/**
	A block of music: one lane per part, a name, a colour and a length.

	A pattern is written once and placed by as many clips as want it, which is what
	makes an arrangement reuse rather than copy.
**/
@:unreflective
final class Pattern {
	/**
		What it is called.
	**/
	public var name:String;

	/**
		Its colour, or -1 to fall back to the track and then the theme.
	**/
	public var colour:Int;

	/**
		How long it is, in ticks.
	**/
	public var length:Int;

	/**
		Which part this pattern is for, or -1 where it carries several.
	**/
	public var part:Int = -1;

	/**
		One lane per part, always all eleven, in an array made at its size and never grown: a
		`Vector` of objects casts through a virtual call on every read, and the sequencer reads
		this for every part of every pattern it walks. The build tool reads the model on the
		interpreter while it writes the shipped banks, and there it is an ordinary array filled in
		order.
	**/
	public final lanes:Array<Lane> = #if cpp cpp.NativeArray.create(Part.COUNT) #else [] #end;

	/**
		Builds an empty pattern with a lane for every part.

		@param name What to call it.
		@param length How long it is, in ticks.
		@param colour Its colour, or -1 for none of its own.
	**/
	public function new(name:String, length:Int, colour:Int = -1) {
		this.name = name;
		this.length = length;
		this.colour = colour;

		for (i in 0...Part.COUNT) lanes[i] = new Lane(i);
	}

	/**
		Copies the whole pattern: every note and every automation lane, each its own.

		Nothing here is shared with the pattern it came from, which is the point. Two
		clips on the playlist showing the same pattern are the same music by design, and
		a copy is how one of them stops being.

		@param called What to call the copy.
		@return The copy.
	**/
	public function copy(called:String):Pattern {
		final out = new Pattern(called, length, colour);
		out.part = part;

		for (index in 0...Part.COUNT) {
			final part:Part = index;

			final from = lane(part);
			final into = out.lane(part);

			for (note in from.notes) into.add(note.copy());
			for (line in from.automation) into.automation.push(line.copy());
		}

		return out;
	}

	/**
		@param part Which part.
		@return That part lane, which always exists.
	**/
	public inline function lane(part:Part):Lane {
		return lanes[part.index()];
	}

	/**
		@return How many notes are in the whole pattern.
	**/
	public function notes():Int {
		var total = 0;
		for (i in 0...Part.COUNT) total += lanes[i].notes.length;
		return total;
	}

	/**
		@param part Which part.
		@return Whether that lane carries anything at all.
	**/
	public function used(part:Part):Bool {
		return lanes[part.index()].notes.length > 0;
	}

	/**
		Grows or shrinks the pattern to the nearest whole bar that holds its notes, so
		writing past the end lengthens it rather than cutting the note off.

		@param bar How many ticks a bar is.
		@return The length it was before, for an undo step to put back.
	**/
	public function fits(bar:Int):Int {
		final was = length;
		if (bar < 1) return was;

		final most = longest();
		var want = Math.ceil(most / bar) * bar;

		if (want < bar) want = bar;
		length = want;

		return was;
	}

	/**
		@return The tick the last note in any lane finishes on.
	**/
	public function longest():Int {
		var most = 0;
		for (i in 0...Part.COUNT) {
			final ends = lanes[i].longest();
			if (ends > most) most = ends;
		}
		return most;
	}
}
