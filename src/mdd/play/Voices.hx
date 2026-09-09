package mdd.play;

import haxe.ds.Vector;
import mdd.song.Lane;
import mdd.song.Note;

/**
	Turns the notes of one lane into the voices a part can actually sound, under
	whichever polyphony behaviour is chosen.

	The result is a flat set of parallel vectors rather than objects, because the
	sequencer reads it once per block and nothing may allocate on that path.
**/
@:unreflective
final class Voices {
	/**
		What to do when more notes are wanted than there are channels.
	**/
	public var policy:Polyphony = Polyphony.Strict;

	/**
		How many ticks each note gets while arpeggiating.
	**/
	public var arpeggio:Int = 6;

	/**
		How many voices the last `resolve` produced.
	**/
	public var count(default, null):Int = 0;

	/**
		How many notes were given up to make room, under stealing.
	**/
	public var dropped(default, null):Int = 0;

	/**
		How many notes were never sounded at all, under strict.
	**/
	public var refused(default, null):Int = 0;

	/**
		How many voices this can hold before it stops adding them.
	**/
	public var capacity(default, null):Int;

	final starts:Vector<Int>;
	final ends:Vector<Int>;
	final pitches:Vector<Int>;
	final velocities:Vector<Int>;
	final instruments:Vector<Int>;
	final ties:Vector<Bool>;
	final holds:Vector<Bool>;

	/**
		Builds the voice arrays.

		@param capacity How many voices to make room for.
	**/
	public function new(capacity:Int = 4096) {
		this.capacity = capacity < 16 ? 16 : capacity;

		starts = new Vector<Int>(this.capacity);
		ends = new Vector<Int>(this.capacity);
		pitches = new Vector<Int>(this.capacity);
		velocities = new Vector<Int>(this.capacity);
		instruments = new Vector<Int>(this.capacity);
		ties = new Vector<Bool>(this.capacity);
		holds = new Vector<Bool>(this.capacity);
	}

	/**
		@param index A voice below `count`.
		@return The tick it starts on.
	**/
	public inline function startAt(index:Int):Int {
		return starts[index];
	}

	/**
		@param index A voice below `count`.
		@return The tick it ends on.
	**/
	public inline function endAt(index:Int):Int {
		return ends[index];
	}

	/**
		@param index A voice below `count`.
		@return Its MIDI note number.
	**/
	public inline function pitchAt(index:Int):Int {
		return pitches[index];
	}

	/**
		@param index A voice below `count`.
		@return Its velocity, 0 to 127.
	**/
	public inline function velocityAt(index:Int):Int {
		return velocities[index];
	}

	/**
		@param index A voice below `count`.
		@return Which instrument it plays.
	**/
	public inline function instrumentAt(index:Int):Int {
		return instruments[index];
	}

	/**
		@param index A voice below `count`.
		@return True where it runs straight into the next one, so no key off happens between them.
	**/
	public inline function tiedAt(index:Int):Bool {
		return ties[index];
	}

	/**
		@param index A voice below `count`.
		@return True where it was already sounding when the span began, so it needs no key on.
	**/
	public inline function heldAt(index:Int):Bool {
		return holds[index];
	}

	/**
		How far back a tie is looked for before giving up.
	**/
	static inline final CHAIN = 64;

	/**
		Reads a lane and produces the voices for a span, applying the polyphony
		behaviour where more notes overlap than there are channels.

		@param lane The lane to read.
		@param from The first tick of the span.
		@param until One past the last tick.
		@return How many voices were produced, which is also left in `count`.
	**/
	public function resolve(lane:Lane, from:Int = 0, until:Int = 0x3FFFFFFF):Int {
		count = 0;
		refused = 0;

		final notes = lane.notes;
		final many = notes.length;
		if (many == 0) return 0;

		final head = from - lane.reach;

		var first = seek(notes, head < 0 ? 0 : head);
		var back = 0;

		while (first > 0 && first < many && back < CHAIN
				&& notes[first - 1].ends() > notes[first].at) {
			first--;
			back++;
		}

		final last = seek(notes, until);

		return switch (policy) {
			case Polyphony.Strict: strict(notes, first, last);
			case Polyphony.Stealing: stealing(notes, first, last);
			case _: arpeggiate(notes, first, last, from, until);
		}
	}

	/**
		@param notes The notes of a lane, in order.
		@param tick The tick to find.
		@return The index of the first note starting at or after that tick.
	**/
	static function seek(notes:Array<Note>, tick:Int):Int {
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
		Adds one voice, or counts it as refused where there is no room left.

		@param start The tick it starts on.
		@param ends The tick it ends on.
		@param note The note it comes from.
		@param held Whether it was already sounding when the span began.
	**/
	function hold(start:Int, ends:Int, note:Note, held:Bool):Void {
		if (start >= ends) return;

		if (count >= capacity) {
			dropped++;
			return;
		}

		starts[count] = start;
		this.ends[count] = ends;
		pitches[count] = note.pitch;
		velocities[count] = note.velocity;
		instruments[count] = note.instrument;
		ties[count] = note.tied;
		holds[count] = held;
		count++;
	}

	/**
		@param notes The notes of a lane, in order.
		@param index Which note.
		@return True where the next note begins exactly where this one ends at the same pitch, so
			the two are one held note.
	**/
	static inline function joined(notes:Array<Note>, index:Int):Bool {
		final next = index + 1;

		return next < notes.length && notes[next].tied
			&& notes[next].at <= notes[index].ends();
	}

	/**
		Sounds what fits and refuses the rest, which is what the hardware does.

		@param notes The notes of a lane, in order.
		@param first The first note in the span.
		@param last One past the last.
		@return How many notes were refused.
	**/
	function strict(notes:Array<Note>, first:Int, last:Int):Int {
		var sounding = -1;

		for (index in first...last) {
			final note = notes[index];

			if (note.at < sounding) {
				refused++;
				continue;
			}

			hold(note.at, note.ends(), note, joined(notes, index));
			sounding = note.ends();
		}

		return count;
	}

	/**
		Gives the oldest voice away when a new note has nowhere to go.

		@param notes The notes of a lane, in order.
		@param first The first note in the span.
		@param last One past the last.
		@return How many notes were cut short.
	**/
	function stealing(notes:Array<Note>, first:Int, last:Int):Int {
		final many = notes.length;

		for (index in first...last) {
			final note = notes[index];
			var ends = note.ends();

			for (later in (index + 1)...many) {
				if (notes[later].at <= note.at) continue;
				if (notes[later].at < ends) ends = notes[later].at;
				break;
			}

			hold(note.at, ends, note, joined(notes, index));
		}

		return count;
	}

	/**
		Cycles the notes that overlap through the channels there are, each holding for
		`arpeggio` ticks.

		@param notes The notes of a lane, in order.
		@param first The first note in the span.
		@param last One past the last.
		@param from The first tick of the span.
		@param until One past the last tick.
		@return How many notes could still not be fitted.
	**/
	function arpeggiate(notes:Array<Note>, first:Int, last:Int, from:Int, until:Int):Int {
		if (last <= first) return 0;

		var edge = 0;
		for (index in first...last) if (notes[index].ends() > edge) edge = notes[index].ends();

		final step = arpeggio < 1 ? 1 : arpeggio;
		final stop = until < edge ? until : edge;

		var at = Std.int(from / step) * step;
		if (at < 0) at = 0;

		while (at < stop) {
			final ends = at + step;
			var chosen = -1;
			var seen = 0;
			final sounding = held(notes, first, last, at);

			for (index in first...last) {
				final note = notes[index];
				if (note.at > at || note.ends() <= at) continue;

				if (seen == Std.int(at / step) % sounding) chosen = index;
				seen++;
			}

			if (chosen >= 0) {
				hold(at, ends > notes[chosen].ends() ? notes[chosen].ends() : ends,
					notes[chosen], false);
			}

			at = ends;
		}

		return count;
	}

	/**
		@param notes The notes of a lane, in order.
		@param first The first note to consider.
		@param last One past the last.
		@param at A tick.
		@return How many of those notes are sounding at that tick.
	**/
	static function held(notes:Array<Note>, first:Int, last:Int, at:Int):Int {
		var many = 0;

		for (index in first...last) {
			final note = notes[index];
			if (note.at <= at && note.ends() > at) many++;
		}

		return many < 1 ? 1 : many;
	}
}
