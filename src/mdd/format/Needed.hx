package mdd.format;

import haxe.ds.Vector;
import mdd.song.Automation;
import mdd.song.Instrument;
import mdd.song.Part;
import mdd.song.Sample;
import mdd.song.Song;

/**
	What of a piece a file has to carry, and where each part of it goes in the file.

	A piece open in the application holds the whole presets library, because the browser shows what
	is installed and a bank has to be in the piece to be shown. A file is not that. A file is the
	piece, and the piece is what it plays: everything else is put back by the library when the file
	is opened, on this machine and on one whose library holds something else, so writing it out
	would be writing a copy of the library into every piece.

	What a piece plays is its rack, every preset a note or a preset lane names, the whole of any
	bank a converter preset sits in, because a kit is picked by note out of a bank rather than by
	index, and everything in a bank that was kept on purpose. A recording is carried where a preset
	that is carried plays it, and one nothing names at all is carried too, because nothing else
	says it was wanted.

	A preset nothing plays is carried anyway where the library has nothing of that name for that
	part, because leaving it out would be the only copy of it going. That is the whole of the
	safety net: a preset the library can hand back is left out, and one it cannot is kept.
**/
@:unreflective
final class Needed {
	/**
		The presets the file carries, in the order it writes them.
	**/
	public final instruments:Array<Instrument> = [];

	/**
		The recordings it carries, in the order it writes them.
	**/
	public final samples:Array<Sample> = [];

	var instrumentAt:Vector<Int>;
	var sampleAt:Vector<Int>;

	function new(many:Int, held:Int) {
		instrumentAt = new Vector<Int>(many);
		sampleAt = new Vector<Int>(held);
	}

	/**
		Works out what a piece has to carry.

		@param song The piece.
		@return What to write, and where each preset and recording goes.
	**/
	public static function of(song:Song, ?library:mdd.song.Library):Needed {
		final many = song.instruments.length;
		final held = song.samples.length;

		final out = new Needed(many, held);
		final want = new Vector<Bool>(many);

		for (index in 0...many) want[index] = false;

		for (index in 0...Part.COUNT) {
			final part:Part = index;
			marks(song, want, song.rack[index], part.sampled());
		}

		for (pattern in song.patterns) {
			for (index in 0...Part.COUNT) {
				final lane = pattern.lanes[index];

				for (note in lane.notes) marks(song, want, note.instrument, false);

				for (line in lane.automation) {
					if (line.target != Automation.INSTRUMENT) continue;

					for (point in line.points) marks(song, want, point.value, false);
				}
			}
		}

		for (bank in song.banks) {
			if (!bank.kept) continue;

			for (index in bank.instruments) marks(song, want, index, false);
		}

		if (library != null) {
			for (index in 0...many) {
				if (want[index] || library.knows(song.instruments[index])) continue;

				want[index] = true;
			}
		}

		final playing = new Vector<Bool>(held);
		final claimed = new Vector<Bool>(held);

		for (index in 0...held) {
			playing[index] = false;
			claimed[index] = false;
		}

		for (index in 0...many) {
			final at = song.instruments[index].sample;
			if (at < 0 || at >= held) continue;

			claimed[at] = true;
			if (want[index]) playing[at] = true;
		}

		for (index in 0...held) {
			if (claimed[index] && !playing[index]) {
				out.sampleAt[index] = -1;
				continue;
			}

			out.sampleAt[index] = out.samples.length;
			out.samples.push(song.samples[index]);
		}

		for (index in 0...many) {
			if (!want[index]) {
				out.instrumentAt[index] = -1;
				continue;
			}

			out.instrumentAt[index] = out.instruments.length;
			out.instruments.push(song.instruments[index]);
		}

		return out;
	}

	/**
		@param at A preset, by index into the piece.
		@return Where it goes in the file, or -1 where the file leaves it out.
	**/
	public inline function instrument(at:Int):Int {
		return at < 0 || at >= instrumentAt.length ? -1 : instrumentAt[at];
	}

	/**
		@param at A recording, by index into the piece.
		@return Where it goes in the file, or -1 where the file leaves it out.
	**/
	public inline function sample(at:Int):Int {
		return at < 0 || at >= sampleAt.length ? -1 : sampleAt[at];
	}

	/**
		Marks one preset as carried.

		@param song The piece.
		@param want What is carried so far.
		@param index The preset, by index into the piece.
		@param whole Whether the whole of its bank goes with it, which the converter preset in
			the rack needs and nothing else does: a drum note picks its hit by note out of that
			one bank, so the bank is the kit, while every other reference is to one preset.
	**/
	static function marks(song:Song, want:Vector<Bool>, index:Int, whole:Bool):Void {
		if (index < 0 || index >= want.length) return;

		want[index] = true;

		if (!whole) return;

		final at = song.bankOf(index);
		if (at < 0 || at >= song.banks.length || !song.banks[at].holds(index)) return;

		for (one in song.banks[at].instruments) {
			if (one >= 0 && one < want.length) want[one] = true;
		}
	}
}
