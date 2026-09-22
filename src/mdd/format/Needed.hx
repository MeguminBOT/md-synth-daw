package mdd.format;

import haxe.ds.Vector;
import mdd.song.Automation;
import mdd.song.Instrument;
import mdd.song.Part;
import mdd.song.Sample;
import mdd.song.Song;

/**
	What of a piece a file has to carry, and where each part of it goes in the file.

	A file is the piece, and the piece is what it plays: its rack, every preset a note or a preset
	lane names, whether the lane sits in a pattern or in an automation clip, and the whole of the
	bank the converter preset in the rack sits in, because a kit is picked by note out of a bank
	rather than by index. Nothing else is written. A preset loaded into a channel and then swapped
	for another is left behind, and so is whatever the browser was offering, because the library
	offers it again on any machine that has it and nothing in the piece plays it.

	A recording is carried where a preset that is carried plays it, and one nothing names at all is
	carried too, because nothing else says it was wanted.

	The same list is what the preset browser shows as the piece's own.
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
	public static function of(song:Song):Needed {
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
				for (line in lane.automation) swaps(song, want, line);
			}
		}

		for (track in song.tracks) {
			for (clip in track.clips) {
				final line = clip.line;
				if (clip.automates() && line != null) swaps(song, want, line);
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
		Marks every preset a preset lane swaps in as carried. Any other lane names no preset.

		@param song The piece.
		@param want What is carried so far.
		@param line A lane.
	**/
	static function swaps(song:Song, want:Vector<Bool>, line:Automation):Void {
		if (line.target != Automation.INSTRUMENT) return;

		for (point in line.points) marks(song, want, point.value, false);
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
