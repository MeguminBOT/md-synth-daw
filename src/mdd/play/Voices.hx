package mdd.play;

import haxe.ds.Vector;
import mdd.song.Lane;
import mdd.song.Note;

@:unreflective
final class Voices {
	public var policy:Polyphony = Polyphony.Strict;
	public var arpeggio:Int = 6;

	public var count(default, null):Int = 0;
	public var dropped(default, null):Int = 0;
	public var refused(default, null):Int = 0;

	public var capacity(default, null):Int;

	final starts:Vector<Int>;
	final ends:Vector<Int>;
	final pitches:Vector<Int>;
	final velocities:Vector<Int>;
	final instruments:Vector<Int>;

	public function new(capacity:Int = 4096) {
		this.capacity = capacity < 16 ? 16 : capacity;

		starts = new Vector<Int>(this.capacity);
		ends = new Vector<Int>(this.capacity);
		pitches = new Vector<Int>(this.capacity);
		velocities = new Vector<Int>(this.capacity);
		instruments = new Vector<Int>(this.capacity);
	}

	public inline function startAt(index:Int):Int {
		return starts[index];
	}

	public inline function endAt(index:Int):Int {
		return ends[index];
	}

	public inline function pitchAt(index:Int):Int {
		return pitches[index];
	}

	public inline function velocityAt(index:Int):Int {
		return velocities[index];
	}

	public inline function instrumentAt(index:Int):Int {
		return instruments[index];
	}

	public function resolve(lane:Lane, from:Int = 0, until:Int = 0x3FFFFFFF):Int {
		count = 0;
		refused = 0;

		final notes = lane.notes;
		final many = notes.length;
		if (many == 0) return 0;

		final head = from - lane.reach;
		final first = seek(notes, head < 0 ? 0 : head);
		final last = seek(notes, until);

		return switch (policy) {
			case Polyphony.Strict: strict(notes, first, last);
			case Polyphony.Stealing: stealing(notes, first, last);
			case _: arpeggiate(notes, first, last, from, until);
		}
	}

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

	function hold(start:Int, ends:Int, note:Note):Void {
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
		count++;
	}

	function strict(notes:Array<Note>, first:Int, last:Int):Int {
		var sounding = -1;

		for (index in first...last) {
			final note = notes[index];

			if (note.at < sounding) {
				refused++;
				continue;
			}

			hold(note.at, note.ends(), note);
			sounding = note.ends();
		}

		return count;
	}

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

			hold(note.at, ends, note);
		}

		return count;
	}

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
					notes[chosen]);
			}

			at = ends;
		}

		return count;
	}

	static function held(notes:Array<Note>, first:Int, last:Int, at:Int):Int {
		var many = 0;

		for (index in first...last) {
			final note = notes[index];
			if (note.at <= at && note.ends() > at) many++;
		}

		return many < 1 ? 1 : many;
	}
}
