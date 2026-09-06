package mdd.gate;

import mdd.host.Sdl;
import mdd.play.Sequencer;
import mdd.play.Stream;
import mdd.song.edit.AddPattern;
import mdd.song.Clip;
import mdd.song.edit.History;
import mdd.song.Instrument;
import mdd.song.edit.MoveClip;
import mdd.song.Note;
import mdd.song.Part;
import mdd.song.Pattern;
import mdd.song.edit.RenamePattern;
import mdd.song.edit.ResizePattern;
import mdd.song.Song;
import mdd.song.Tempo;
import mdd.song.Track;

@:unreflective
class ArrangeCheck {
	static var failed:Int = 0;
	static var ran:Int = 0;

	public static function run(args:Array<String>):Int {
		failed = 0;
		ran = 0;

		Sys.println("  arrange");

		flattened();
		transposed();
		edits();
		dropped();
		shifted();

		Sys.println("    " + (ran - failed) + " of " + ran + " checks");

		if (failed > 0) {
			Sys.println("    failed");
			return 1;
		}

		Sys.println("    passed");
		return 0;
	}

	static function says(name:String, ok:Bool, said:String):Void {
		ran++;
		if (!ok) failed++;
		Sys.println("    " + StringTools.rpad(name, " ", 34) + said + (ok ? "" : "   FAILED"));
	}

	static function round(value:Float, places:Int):Float {
		final scale = Math.pow(10, places);
		return Math.round(value * scale) / scale;
	}

	static function reused():Song {
		final song = new Song("reused", 96, 132);

		for (index in 0...Part.COUNT) {
			final part:Part = index;
			final instrument = song.instrument(new Instrument(part.name(), part));

			if (instrument.patch != null) {
				instrument.patch.algorithm = 3;
				for (slot in 0...4) {
					instrument.patch.totalLevel[slot] = instrument.patch.carries(slot) ? 10 : 30;
				}
			}

			song.rack[index] = index;
		}

		final verse = song.add(new Pattern("verse", 384));
		final chorus = song.add(new Pattern("chorus", 384));

		for (index in 0...4) {
			final part:Part = index;
			verse.lane(part).add(new Note(index * 48, 96, 52 + index * 4, 100));
			verse.lane(part).add(new Note(192 + index * 24, 48, 60 + index * 2, 80));
			chorus.lane(part).add(new Note(index * 32, 128, 57 + index * 3, 110));
		}

		verse.lane(Part.Psg1).add(new Note(0, 192, 72, 100));
		chorus.lane(Part.Noise).add(new Note(0, 48, 60, 120));

		final one = song.track(new Track("one"));
		one.add(new Clip(0, 0, 384));
		one.add(new Clip(1, 384, 384));
		one.add(new Clip(0, 768, 384, 5));
		one.add(new Clip(1, 1152, 384, -3));

		final two = song.track(new Track("two"));
		two.add(new Clip(0, 384, 384, 12));
		two.add(new Clip(0, 1152, 384, 7));

		return song;
	}

	static function poured(song:Song, into:Stream):Void {
		final sequencer = new Sequencer(song);
		final span = song.tempo.samplesAt(song.ends());

		var at = 0;
		while (at < span) {
			var until = at + 4096;
			if (until > span) until = span;

			sequencer.emit(into, at, until);
			at = until;
		}
	}

	static function alike(one:Stream, two:Stream):Int {
		if (one.count != two.count) return -1;

		for (i in 0...one.count) {
			if (one.tickAt(i) != two.tickAt(i)) return i;
			if (one.kindAt(i) != two.kindAt(i)) return i;
			if (one.portAt(i) != two.portAt(i)) return i;
			if (one.valueAt(i) != two.valueAt(i)) return i;
		}

		return -2;
	}

	static function flattened():Void {
		final song = reused();
		final flat = song.unshared();

		says("a pattern is reused", song.shares() == 4 && flat.shares() == 0,
			song.patterns.length + " patterns across 6 clips, " + song.shares()
			+ " of them reusing one; flat it is " + flat.patterns.length + " patterns and "
			+ flat.shares() + " reuses");

		final packed = new Stream(262144);
		final spread = new Stream(262144);

		final began = Sdl.ticks();
		poured(song, packed);
		poured(flat, spread);
		final spent = Sdl.ticks() - began;

		final parted = alike(packed, spread);

		says("flat plays the same", parted == -2,
			parted == -1 ? spread.count + " writes against " + packed.count
				: (parted >= 0 ? "they part at write " + parted
					: packed.count + " register writes, every one the same"));

		says("and takes the same time", spent < 1.0,
			"both arrangements streamed in " + round(spent * 1000, 1) + " ms");
	}

	static function transposed():Void {
		final song = reused();
		final flat = song.unshared();

		var lowest = 127;
		var highest = 0;

		for (pattern in flat.patterns) {
			for (index in 0...Part.COUNT) {
				for (note in pattern.lanes[index].notes) {
					if (note.pitch < lowest) lowest = note.pitch;
					if (note.pitch > highest) highest = note.pitch;
				}
			}
		}

		var packedLowest = 127;
		var packedHighest = 0;

		for (pattern in song.patterns) {
			for (index in 0...Part.COUNT) {
				for (note in pattern.lanes[index].notes) {
					if (note.pitch < packedLowest) packedLowest = note.pitch;
					if (note.pitch > packedHighest) packedHighest = note.pitch;
				}
			}
		}

		says("transposing moves the notes", highest - lowest > packedHighest - packedLowest,
			"the flat song spans notes " + lowest + " to " + highest + ", the packed one "
			+ packedLowest + " to " + packedHighest + ", because the transposes are in the notes");
	}

	static function dropped():Void {
		final song = new Song("dropped", 96, 120);

		song.add(new Pattern("gone", 384));
		song.add(new Pattern("kept", 384));

		final track = song.track(new Track("track"));

		track.add(new Clip(0, 0, 384));
		track.add(new Clip(1, 384, 384));
		track.add(new Clip(0, 768, 384));
		track.add(new Clip(0, 1152, 384));

		final before = mdd.format.Project.text(song);
		final history = new History();

		history.does(song, new mdd.song.edit.RemovePattern(0));

		final left = track.clips.length;

		history.undo(song);

		var ordered = true;
		for (index in 1...track.clips.length) {
			if (track.clips[index].at < track.clips[index - 1].at) ordered = false;
		}

		final places:Array<Int> = [];
		for (clip in track.clips) places.push(clip.at);

		says("removing a pattern takes its clips with it", left == 1,
			left + " of 4 clips left on the track after the pattern three of them used"
			+ " was removed");

		says("and undoing puts them back in order", ordered
			&& track.clips.length == 4 && mdd.format.Project.text(song) == before,
			"the track reads " + places.join(", ") + " after the undo, and the song is "
			+ (mdd.format.Project.text(song) == before ? "byte for byte what it was"
			: "not what it was"));
	}

	static function shifted():Void {
		final song = new Song("shifted", 96, 120);
		final pattern = song.add(new Pattern("both", 384));

		pattern.lane(Part.Fm1).add(new Note(96, 48, 60, 100));
		pattern.lane(Part.Fm1).add(new Note(288, 48, 62, 100));

		pattern.lane(Part.Psg1).add(new Note(0, 48, 72, 100));
		pattern.lane(Part.Psg1).add(new Note(192, 48, 74, 100));

		final before = mdd.format.Project.text(song);
		final history = new History();

		history.does(song, new mdd.song.edit.MovePattern(0, Part.Psg1.index()));

		final held = pattern.lane(Part.Psg1).notes;
		final places:Array<Int> = [];

		var ordered = true;

		for (index in 0...held.length) {
			places.push(held[index].at);
			if (index > 0 && held[index].at < held[index - 1].at) ordered = false;
		}

		says("a pattern moved onto a busy channel keeps its notes in order",
			held.length == 4 && ordered,
			held.length + " notes on PSG1 reading " + places.join(", "));

		history.undo(song);

		says("and moving it back leaves the song as it was",
			mdd.format.Project.text(song) == before,
			"the song is " + (mdd.format.Project.text(song) == before
			? "byte for byte what it was" : "not what it was"));
	}

	static function edits():Void {
		final song = reused();
		final history = new History();

		final before = mdd.format.Project.text(song);

		history.does(song, new AddPattern(new Pattern("bridge", 192)));
		history.does(song, new RenamePattern(0, "the verse"));
		history.does(song, new ResizePattern(1, 768));
		history.does(song, new MoveClip(0, song.tracks[0].clips[2], 960, 2));
		history.does(song, new mdd.song.edit.SizeClip(0, song.tracks[0].clips[2], 240));

		final after = mdd.format.Project.text(song);

		var undone = 0;
		while (history.undo(song)) undone++;

		says("an arrangement edit stacks", before != after && undone == 5,
			undone + " arrangement edits made and " + undone + " reverted");

		says("and reverts byte for byte", mdd.format.Project.text(song) == before,
			"the song is what it was before the pattern, the rename, the resize, the move and the stretch");
	}
}
