package mdd.play;

import haxe.ds.Vector;
import mdd.song.Lane;
import mdd.song.Note;

/**
	Turns the notes of one lane into the voices a part can actually sound: one at a time, as the
	channel on the chip plays them, with a note that starts while another still sounds refused.

	The result is a flat set of parallel vectors rather than objects, because the
	sequencer reads it once per block and nothing may allocate on that path.
**/
@:unreflective
final class Voices {
	/**
		How many voices the last `resolve` produced.
	**/
	public var count(default, null):Int = 0;

	/**
		How many notes the last `resolve` refused, because they started while another still sounded.
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
		Reads a lane and produces the voices for a span. A note that starts while another still
		sounds is refused rather than sounded, which is what the hardware does.

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

		var first = lane.seek(head < 0 ? 0 : head);
		var back = 0;

		while (first > 0 && first < many && back < CHAIN
				&& notes[first - 1].ends() > notes[first].at) {
			first--;
			back++;
		}

		final last = lane.seek(until);
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
		Adds one voice, or leaves it out where there is no room left.

		@param start The tick it starts on.
		@param ends The tick it ends on.
		@param note The note it comes from.
		@param held Whether it was already sounding when the span began.
	**/
	function hold(start:Int, ends:Int, note:Note, held:Bool):Void {
		if (start >= ends || count >= capacity) return;

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
}
