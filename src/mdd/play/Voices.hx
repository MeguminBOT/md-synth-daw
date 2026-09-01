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

	public function resolve(lane:Lane):Int {
		count = 0;
		refused = 0;

		return switch (policy) {
			case Polyphony.Strict: strict(lane);
			case Polyphony.Stealing: stealing(lane);
			case _: arpeggiate(lane);
		}
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

	function strict(lane:Lane):Int {
		var sounding = -1;

		for (note in lane.notes) {
			if (note.at < sounding) {
				refused++;
				continue;
			}

			hold(note.at, note.ends(), note);
			sounding = note.ends();
		}

		return count;
	}

	function stealing(lane:Lane):Int {
		final notes = lane.notes;

		for (i in 0...notes.length) {
			final note = notes[i];
			var ends = note.ends();

			for (later in (i + 1)...notes.length) {
				if (notes[later].at <= note.at) continue;
				if (notes[later].at < ends) ends = notes[later].at;
				break;
			}

			hold(note.at, ends, note);
		}

		return count;
	}

	function arpeggiate(lane:Lane):Int {
		final notes = lane.notes;
		if (notes.length == 0) return 0;

		var last = 0;
		for (note in notes) if (note.ends() > last) last = note.ends();

		final step = arpeggio < 1 ? 1 : arpeggio;
		var at = 0;

		while (at < last) {
			final until = at + step;
			var chosen = -1;
			var seen = 0;

			for (i in 0...notes.length) {
				final note = notes[i];
				if (note.at > at || note.ends() <= at) continue;

				if (seen == Std.int(at / step) % held(notes, at)) chosen = i;
				seen++;
			}

			if (chosen >= 0) hold(at, until > notes[chosen].ends() ? notes[chosen].ends() : until,
				notes[chosen]);

			at = until;
		}

		return count;
	}

	static function held(notes:Array<Note>, at:Int):Int {
		var many = 0;
		for (note in notes) if (note.at <= at && note.ends() > at) many++;
		return many < 1 ? 1 : many;
	}
}
