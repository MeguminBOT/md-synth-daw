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
		carried();
		reordered();
		fitted();
		dressed();
		cut();
		uniqued();
		ranged();
		reversed();
		nudged();

		Sys.println("    " + (ran - failed) + " of " + ran + " checks");

		if (failed > 0) {
			Sys.println("    failed");
			return 1;
		}

		Sys.println("    passed");
		return 0;
	}

	/**
		A sliced clip is still the same music as the one it came from, and making it
		unique is what parts them.

		Slicing cuts where a clip starts and ends, not what it plays, so both halves point
		at one pattern and a note put in either shows up in both. That is what a pattern is
		for, and it is also the thing a reader coming from another sequencer does not
		expect to be permanent.
	**/
	static function uniqued():Void {
		final song = rich();
		final history = new History();

		final clip = song.tracks[0].clips[0];
		final at = clip.at + 96;

		history.does(song, new mdd.song.edit.SliceClip(0, clip, at));

		final half = song.tracks[0].clips[1];
		final patterns = song.patterns.length;

		says("a slice leaves both halves shared",
			half.pattern == clip.pattern
				&& mdd.song.edit.UniqueClip.shares(song, half),
			"both halves play pattern " + clip.pattern + " of "
			+ patterns + ", which is what makes them the same music");

		final from = song.patternAt(clip.pattern);
		final notes = from == null ? 0 : from.lane(mdd.song.Part.Fm1).notes.length;

		history.does(song, new mdd.song.edit.UniqueClip(half));

		final made = song.patternAt(half.pattern);

		says("making one unique parts them",
			song.patterns.length == patterns + 1 && half.pattern != clip.pattern
				&& made != null && made != from,
			"pattern " + half.pattern + " of " + song.patterns.length
			+ (made == null ? "" : ", called " + made.name));

		says("the copy carries the notes",
			made != null && made.lane(mdd.song.Part.Fm1).notes.length == notes,
			(made == null ? 0 : made.lane(mdd.song.Part.Fm1).notes.length)
			+ " notes against " + notes);

		if (made != null && from != null && notes > 0) {
			made.lane(mdd.song.Part.Fm1).notes[0].pitch += 5;

			says("editing one no longer edits both",
				made.lane(mdd.song.Part.Fm1).notes[0].pitch
					!= from.lane(mdd.song.Part.Fm1).notes[0].pitch,
				"the copy moved to " + made.lane(mdd.song.Part.Fm1).notes[0].pitch
				+ " and the first stayed at " + from.lane(mdd.song.Part.Fm1).notes[0].pitch);

			made.lane(mdd.song.Part.Fm1).notes[0].pitch -= 5;
		}

		history.undo(song);

		says("undo restores the sharing",
			half.pattern == clip.pattern && song.patterns.length == patterns,
			"pattern " + half.pattern + " again, " + song.patterns.length + " patterns");
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

	static function carried():Void {
		final song = rich();
		final before = mdd.format.Project.text(song);
		final history = new History();

		final clip = song.tracks[0].clips[0];

		history.does(song, new MoveClip(0, clip, 96, 0, 1));

		final onto = song.tracks[1].clips;
		final places:Array<Int> = [];

		for (held in onto) places.push(held.at);

		var ordered = true;
		for (index in 1...onto.length) if (onto[index].at < onto[index - 1].at) ordered = false;

		says("a clip moves to another track", song.tracks[0].clips.length == 1
			&& onto.length == 2 && onto.indexOf(clip) == 0 && ordered,
			song.tracks[0].clips.length + " clip left on the first track and the second reads "
			+ places.join(", "));

		history.undo(song);

		says("and moving it back is byte for byte",
			mdd.format.Project.text(song) == before,
			"the song is " + (mdd.format.Project.text(song) == before
			? "what it was" : "not what it was"));
	}

	static function reordered():Void {
		final song = rich();
		final before = mdd.format.Project.text(song);
		final history = new History();

		final was:Array<String> = [];
		for (track in song.tracks) was.push(track.name);

		history.does(song, new mdd.song.edit.MoveTrack(0, 1));

		final now:Array<String> = [];
		for (track in song.tracks) now.push(track.name);

		says("a track moves to another row", now.length == was.length
			&& now[0] == was[1] && now[1] == was[0],
			"the rows read " + was.join(", ") + " and then " + now.join(", "));

		history.undo(song);

		says("and putting the row back is byte for byte",
			mdd.format.Project.text(song) == before,
			"the song is " + (mdd.format.Project.text(song) == before
			? "what it was" : "not what it was"));
	}

	static function dressed():Void {
		final song = rich();
		final before = mdd.format.Project.text(song);
		final history = new History();

		final fresh = song.tracks[0].colour < 0 && song.tracks[0].icon < 0
			&& song.patterns[0].colour < 0;

		history.does(song, new mdd.song.edit.ColourTrack(0, mdd.ui.Theme.FM4));
		history.does(song, new mdd.song.edit.IconTrack(0, mdd.Icon.PIANO));
		history.does(song, new mdd.song.edit.ColourPattern(0, mdd.ui.Theme.PSG2));

		final track = song.tracks[0];
		final worn = track.colour == mdd.ui.Theme.FM4 && track.icon == mdd.Icon.PIANO
			&& song.patterns[0].colour == mdd.ui.Theme.PSG2;

		final kept = mdd.format.Project.read(mdd.format.Project.text(song));
		final saved = kept.tracks[0].colour == track.colour
			&& kept.tracks[0].icon == track.icon;

		says("a track and a pattern arrive with no colour", fresh && worn && saved,
			"a fresh track has no colour and no icon, and once given one it reads back from"
			+ " the project file as " + (saved ? "the same pair" : "something else"));

		var undone = 0;
		while (history.undo(song)) undone++;

		says("and taking the colour off is byte for byte", undone == 3
			&& mdd.format.Project.text(song) == before,
			undone + " edits reverted and the song is "
			+ (mdd.format.Project.text(song) == before ? "what it was" : "not what it was"));
	}

	static function played(song:Song):Stream {
		final span = song.tempo.samplesAt(song.ends());
		final stream = new Stream(mdd.play.Mixdown.roomFor(span));

		new Sequencer(song).spanned(stream, 0, span);

		return stream;
	}

	static function apart(one:Stream, two:Stream):Int {
		if (one.count != two.count) return -1;

		for (index in 0...one.count) {
			if (one.tickAt(index) != two.tickAt(index)) return index;
			if (one.kindAt(index) != two.kindAt(index)) return index;
			if (one.portAt(index) != two.portAt(index)) return index;
			if (one.valueAt(index) != two.valueAt(index)) return index;
		}

		return -2;
	}

	static function cut():Void {
		final song = rich();
		final before = mdd.format.Project.text(song);
		final history = new History();

		final clip = song.tracks[0].clips[0];
		final was = clip.length;
		final at = clip.at + 96;

		final wasHeard = played(song);

		history.does(song, new mdd.song.edit.SliceClip(0, clip, at));

		final clips = song.tracks[0].clips;
		final halves = clips.length == 3 && clips[0] == clip
			&& clips[0].length + clips[1].length == was
			&& clips[1].at == at && clips[1].pattern == clip.pattern
			&& clips[1].transpose == clip.transpose;

		says("a sliced clip is two clips that sum to the one", halves,
			"a clip of " + was + " ticks cut at " + at + " leaves "
			+ clips[0].length + " and " + (clips.length > 1 ? clips[1].length : 0)
			+ ", the second carrying the same pattern and transpose");

		final nowHeard = played(song);
		final differs = apart(wasHeard, nowHeard);

		says("and a cut changes nothing that sounds", differs == -2,
			differs == -2 ? wasHeard.count + " register writes, the same before and after"
				: differs == -1 ? wasHeard.count + " register writes before against "
					+ nowHeard.count + " after"
				: "write " + differs + " of " + wasHeard.count + " moved from tick "
					+ wasHeard.tickAt(differs) + " to " + nowHeard.tickAt(differs));

		says("and the half after the cut starts inside the pattern",
			clips.length > 1 && clips[1].offset == at - clip.at,
			"the second half reads the pattern from tick "
			+ (clips.length > 1 ? clips[1].offset : 0) + ", which is where the cut was");

		history.undo(song);

		final back = mdd.format.Project.text(song) == before;

		says("and joining it back up is byte for byte",
			song.tracks[0].clips.length == 2 && back,
			song.tracks[0].clips.length + " clips left on the track and the song is "
			+ (back ? "what it was" : "not what it was"));
	}

	static function ranged():Void {
		final song = new Song("ranged", 96, 120);
		song.add(new Pattern("one", 384));

		final row = song.track(new Track("row"));
		for (index in 0...5) row.add(new Clip(0, index * 384, 384));

		final all = row.clips;
		final picked = new mdd.view.Picked<Clip>();

		picked.alters(all, null, all[1], false, false);
		final one = picked.count;

		picked.alters(all, all[1], all[3], true, false);
		final range = picked.count;

		picked.alters(all, all[3], all[2], false, true);
		final dropped = picked.count;

		picked.alters(all, all[3], all[2], false, true);
		final added = picked.count;

		picked.alters(all, all[3], all[0], false, false);
		final alone = picked.count;

		says("a click, a range and a toggle pick what they say",
			one == 1 && range == 3 && dropped == 2 && added == 3 && alone == 1,
			"over five clips a click takes " + one + ", a shift click three along takes "
			+ range + ", a ctrl click drops one to " + dropped + " and puts it back at "
			+ added + ", and a click away from all of them is back to " + alone);
	}

	static function wholes(held:Array<Int>, bar:Int):String {
		final out:Array<String> = [];
		for (value in held) out.push(Std.string(Math.round(value / bar)));
		return out.join(", ");
	}

	static function fitted():Void {
		final song = new Song("fitted", 96, 120);
		final bar = song.tempo.ppqn * 4;
		final pattern = song.add(new Pattern("one", bar));

		final near = new Note(0, 96, 60, 100);
		final far = new Note(bar * 2, 96, 62, 100);

		final before = mdd.format.Project.text(song);
		final history = new History();
		final grew:Array<Int> = [];

		history.does(song, new mdd.song.edit.AddNote(0, Part.Fm1, near));
		grew.push(pattern.length);

		history.does(song, new mdd.song.edit.AddNote(0, Part.Fm1, far));
		grew.push(pattern.length);

		history.does(song, new mdd.song.edit.SizeNote(0, Part.Fm1, far, 480));
		grew.push(pattern.length);

		history.does(song, new mdd.song.edit.MoveNote(0, Part.Fm1, far, bar * 4, 62));
		grew.push(pattern.length);

		history.does(song, new ResizePattern(0, bar * 9));
		grew.push(pattern.length);

		history.does(song, new mdd.song.edit.RemoveNote(0, Part.Fm1, far));
		grew.push(pattern.length);

		final want:Array<Int> = [bar, bar * 3, bar * 4, bar * 6, bar * 9, bar];

		var same = grew.length == want.length;
		for (index in 0...grew.length) if (grew[index] != want[index]) same = false;

		says("a pattern's length follows its notes", same,
			"an add, a second add two bars out, a resize, a move, a set and a remove leave it "
			+ wholes(grew, bar) + " bars, wanting " + wholes(want, bar)
			+ ", and a note of a quarter bar still holds one whole one");

		var undone = 0;
		while (history.undo(song)) undone++;

		final back = mdd.format.Project.text(song) == before;

		says("and every one of them undoes to the length it started at",
			undone == 6 && pattern.length == bar && back,
			undone + " edits reverted, the pattern back to "
			+ Math.round(pattern.length / bar) + " bar and the song "
			+ (back ? "byte for byte what it was" : "not what it was"));
	}

	static function nudged():Void {
		final song = new Song("nudged", 96, 120);
		final pattern = song.add(new Pattern("one", 384));

		pattern.lane(Part.Fm1).add(new Note(96, 48, 60, 100));

		final track = song.track(new Track("track"));
		track.add(new Clip(0, 384, 384));

		final was = track.clips[0].at + pattern.lane(Part.Fm1).notes[0].at;
		final history = new History();

		history.does(song, new mdd.song.edit.ShiftSong(-4));

		final now = track.clips[0].at + pattern.lane(Part.Fm1).notes[0].at;

		says("a nudge moves what sounds by what it says", now == was - 4,
			"a note that sounded at tick " + was + " sounds at " + now
			+ " after a nudge of four ticks earlier, so it moved by " + (was - now));

		history.undo(song);
	}

	static function rich():Song {
		final song = new Song("rich", 96, 120);
		mdd.song.Shipped.into(song);

		final one = song.add(new Pattern("one", 384));
		final two = song.add(new Pattern("two", 192));

		one.lane(Part.Fm1).add(new Note(0, 96, 60, 100));
		one.lane(Part.Fm1).add(new Note(192, 96, 64, 90));
		one.lane(Part.Psg1).add(new Note(96, 48, 72, 110));
		two.lane(Part.Fm2).add(new Note(0, 48, 55, 80));

		final line = new mdd.song.Automation(mdd.song.Automation.LEVEL, 0);

		line.add(new mdd.song.Point(0, -8));
		line.add(new mdd.song.Point(192, -2));

		one.lane(Part.Fm1).automation.push(line);

		final first = song.track(new Track("first"));
		final second = song.track(new Track("second"));

		first.add(new Clip(0, 0, 384));
		first.add(new Clip(1, 384, 192));
		second.add(new Clip(0, 192, 384));

		song.tempo.set(192, 140);

		return song;
	}

	static function reversed():Void {
		final names:Array<String> = [];
		final makers:Array<Song -> mdd.song.edit.Command> = [];

		function offer(name:String, make:Song -> mdd.song.edit.Command):Void {
			names.push(name);
			makers.push(make);
		}

		offer("AddNote", function(song) return new mdd.song.edit.AddNote(0, Part.Fm1,
			new Note(288, 48, 67, 100)));
		offer("RemoveNote", function(song) return new mdd.song.edit.RemoveNote(0, Part.Fm1,
			song.patterns[0].lane(Part.Fm1).notes[0]));
		offer("MoveNote", function(song) return new mdd.song.edit.MoveNote(0, Part.Fm1,
			song.patterns[0].lane(Part.Fm1).notes[0], 48, 65, 1));
		offer("SizeNote", function(song) return new mdd.song.edit.SizeNote(0, Part.Fm1,
			song.patterns[0].lane(Part.Fm1).notes[0], 24));
		offer("SetVelocity", function(song) return new mdd.song.edit.SetVelocity(
			song.patterns[0].lane(Part.Fm1).notes[0], 40));

		offer("AddClip", function(song) return new mdd.song.edit.AddClip(1,
			new Clip(1, 960, 192)));
		offer("RemoveClip", function(song) return new mdd.song.edit.RemoveClip(0,
			song.tracks[0].clips[0]));
		offer("MoveClip", function(song) return new mdd.song.edit.MoveClip(0,
			song.tracks[0].clips[0], 576, 3));
		offer("SizeClip", function(song) return new mdd.song.edit.SizeClip(0,
			song.tracks[0].clips[0], 96));
		offer("SliceClip", function(song) return new mdd.song.edit.SliceClip(0,
			song.tracks[0].clips[0], 96));

		offer("AddPattern", function(song) return new AddPattern(new Pattern("three", 96)));
		offer("RemovePattern", function(song) return new mdd.song.edit.RemovePattern(0));
		offer("RenamePattern", function(song) return new RenamePattern(0, "renamed"));
		offer("ResizePattern", function(song) return new ResizePattern(0, 768));
		offer("MovePattern", function(song) return new mdd.song.edit.MovePattern(0,
			Part.Psg1.index()));

		offer("MoveClip across", function(song) return new mdd.song.edit.MoveClip(0,
			song.tracks[0].clips[0], 96, 0, 1));

		offer("AddTrack", function(song) return new mdd.song.edit.AddTrack(2));
		offer("MoveTrack", function(song) return new mdd.song.edit.MoveTrack(0, 1));
		offer("RemoveTrack", function(song) return new mdd.song.edit.RemoveTrack(1));
		offer("RenameTrack", function(song) return new mdd.song.edit.RenameTrack(0, "named"));
		offer("ColourTrack", function(song) return new mdd.song.edit.ColourTrack(0,
			mdd.ui.Theme.FM4));
		offer("IconTrack", function(song) return new mdd.song.edit.IconTrack(0, mdd.Icon.PIANO));
		offer("ColourPattern", function(song) return new mdd.song.edit.ColourPattern(0,
			mdd.ui.Theme.PSG2));

		offer("AddPoint", function(song) return new mdd.song.edit.AddPoint(0, Part.Fm1,
			mdd.song.Automation.LEVEL, 0, new mdd.song.Point(96, -5)));
		offer("RemovePoint", function(song) return new mdd.song.edit.RemovePoint(0, Part.Fm1,
			mdd.song.Automation.LEVEL, 0,
			song.patterns[0].lane(Part.Fm1).automation[0].points[0]));
		offer("MovePoint", function(song) return new mdd.song.edit.MovePoint(0, Part.Fm1,
			mdd.song.Automation.LEVEL, 0,
			song.patterns[0].lane(Part.Fm1).automation[0].points[0], 48, -6));
		offer("ShapePoint", function(song) return new mdd.song.edit.ShapePoint(
			song.patterns[0].lane(Part.Fm1).automation[0].points[0],
			mdd.song.Automation.CURVE, 30, 4));
		offer("LiftAutomation", function(song) return new mdd.song.edit.LiftAutomation(0,
			Part.Fm1, mdd.song.Automation.LEVEL, 0));

		offer("SetInstrument", function(song) return new mdd.song.edit.SetInstrument(Part.Fm1,
			2));
		offer("SetTempo", function(song) return new mdd.song.edit.SetTempo(0, 96));
		offer("SetGrid", function(song) return new mdd.song.edit.SetGrid(200));
		offer("ShiftSong", function(song) return new mdd.song.edit.ShiftSong(1));

		offer("Together", function(song) {
			final group = new mdd.song.edit.Together("two notes");

			group.also(new mdd.song.edit.RemoveNote(0, Part.Fm1,
				song.patterns[0].lane(Part.Fm1).notes[0]));
			group.also(new mdd.song.edit.RemoveNote(0, Part.Fm1,
				song.patterns[0].lane(Part.Fm1).notes[1]));

			return group;
		});

		final idle:Array<String> = [];
		final broken:Array<String> = [];

		for (index in 0...makers.length) {
			final song = rich();
			final before = mdd.format.Project.text(song);
			final history = new History();

			history.does(song, makers[index](song));

			if (mdd.format.Project.text(song) == before) idle.push(names[index]);

			history.undo(song);

			if (mdd.format.Project.text(song) != before) broken.push(names[index]);
		}

		says("every edit changes the song", idle.length == 0,
			makers.length + " commands applied, " + idle.length + " left it alone"
			+ (idle.length == 0 ? "" : ": " + idle.join(", ")));

		says("and every one of them undoes byte for byte", broken.length == 0,
			(makers.length - broken.length) + " of " + makers.length
			+ " came back to what they were"
			+ (broken.length == 0 ? "" : ", these did not: " + broken.join(", ")));
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
