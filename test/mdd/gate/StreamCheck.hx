package mdd.gate;

import haxe.ds.Vector;
import mdd.format.Chunks;
import mdd.format.Project;
import mdd.play.Polyphony;
import mdd.play.Sequencer;
import mdd.play.Stream;
import mdd.play.Voices;
import mdd.song.edit.AddClip;
import mdd.song.edit.AddNote;
import mdd.song.Clip;
import mdd.song.edit.History;
import mdd.song.Instrument;
import mdd.song.edit.MoveNote;
import mdd.song.Note;
import mdd.song.Part;
import mdd.song.Pattern;
import mdd.song.Sample;
import mdd.song.edit.SetTempo;
import mdd.song.Song;
import mdd.song.Tempo;
import mdd.song.Track;

@:unreflective
class StreamCheck {
	static var failed:Int = 0;
	static var ran:Int = 0;

	public static function run(args:Array<String>):Int {
		failed = 0;
		ran = 0;

		Sys.println("  stream");

		timing();
		polyphony();
		identical();
		commands();
		faces();
		chunks();
		sounded();
		raced();
		sought(args);

		Sys.println("    " + (ran - failed) + " of " + ran + " checks");

		if (failed > 0) {
			Sys.println("    failed");
			return 1;
		}

		Sys.println("    passed");
		return 0;
	}

	static function held(stream:Stream, until:Int):haxe.ds.Vector<Int> {
		final shadow = new haxe.ds.Vector<Int>(512 + 8);
		for (index in 0...shadow.length) shadow[index] = -1;

		var half = 0;
		var address = -1;
		var latched = 0;

		for (index in 0...stream.count) {
			if (stream.tickAt(index) > until) break;

			final port = stream.portAt(index);
			final value = stream.valueAt(index);

			if (stream.kindAt(index) != Stream.YM) {
				if ((value & 0x80) != 0) {
					latched = (value >> 4) & 7;
					shadow[512 + latched] = (shadow[512 + latched] & 0x3F0) | (value & 0x0F);
				} else shadow[512 + latched] = (value & 0x3F) << 4
					| (shadow[512 + latched] & 0x0F);

				continue;
			}

			if ((port & 1) == 0) {
				half = (port >> 1) & 1;
				address = value;
				continue;
			}

			if (address < 0 || address == 0x28 || address == 0x2A) continue;

			shadow[(half << 8) | address] = value & 0xFF;
		}

		return shadow;
	}

	static function sought(args:Array<String>):Void {
		final where = Gate.root + "/vendor/vgm";
		if (!sys.FileSystem.isDirectory(where)) return;

		var name = "";
		for (found in sys.FileSystem.readDirectory(where)) {
			if (found.indexOf("Green Hill") >= 0) name = found;
		}

		if (name == "") return;

		final source = new Stream(1 << 22);
		final vgm = mdd.format.Vgm.read(sys.io.File.getBytes(where + "/" + name), source);
		final song = mdd.format.Transcription.of(source, vgm.rate, name).song;

		final into = Tempo.TICKS * 8;

		final whole = new Stream(1 << 21);
		new Sequencer(song).spanned(whole, 0, into);

		final after = new Stream(1 << 20);

		after.reset(into);
		if (args.indexOf("--raw") < 0) new Sequencer(song).prime(after, into);

		final one = held(whole, into);
		final two = held(after, into);

		var apart = 0;
		var first = -1;

		for (index in 0...one.length) {
			if (one[index] == two[index]) continue;
			if (one[index] < 0 || two[index] < 0) continue;

			apart++;
			if (first < 0) first = index;
		}

		says("a seek leaves the chip where playing there would", apart == 0,
			apart + " of the registers the song sets differ from what playing to eight"
			+ " seconds would have left" + (first < 0 ? "" : ", the first being "
			+ StringTools.hex(first, 3)));
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

	public static function written():Song {
		final song = new Song("a measured song", 96, 120);

		final lead = song.instrument(new Instrument("lead", Part.Fm1));
		lead.patch.algorithm = 2;
		lead.patch.feedback = 5;

		for (slot in 0...4) {
			lead.patch.detune[slot] = slot;
			lead.patch.multiple[slot] = 1 + slot;
			lead.patch.totalLevel[slot] = slot == 3 ? 8 : 32;
			lead.patch.attack[slot] = 28;
			lead.patch.decay[slot] = 12;
			lead.patch.sustain[slot] = 4;
			lead.patch.sustainLevel[slot] = 3;
			lead.patch.release[slot] = 7;
			lead.patch.tremolo[slot] = slot == 1;
		}

		final square = song.instrument(new Instrument("square", Part.Psg1));
		square.envelope.steps.push(0);
		square.envelope.steps.push(1);
		square.envelope.steps.push(3);
		square.envelope.steps.push(6);
		square.envelope.loop = 2;
		square.envelope.speed = 1;

		final hiss = song.instrument(new Instrument("hiss", Part.Noise));
		hiss.envelope.steps.push(0);
		hiss.envelope.steps.push(4);
		hiss.envelope.noise = 6;

		final kit = song.instrument(new Instrument("kit", Part.Dac));
		final sample = song.sample(new Sample("snare", 8000, 60));

		final bytes = new Vector<Int>(240);
		var seed = 0x1234;

		for (i in 0...bytes.length) {
			seed = (seed * 1103515245 + 12345) & 0x3FFFFFFF;
			bytes[i] = 0x80 + ((seed >> 7) % 60) - 30;
		}

		sample.hold(bytes);
		kit.sample = 0;

		for (index in 0...Part.COUNT) {
			final part:Part = index;
			song.rack[index] = part.fm() ? 0 : (part.square() ? 1 : (part.noise() ? 2 : 3));
		}

		final pattern = song.add(new Pattern("verse", 384));

		for (index in 0...6) {
			final part:Part = index;
			pattern.lane(part).add(new Note(index * 24, 72, 48 + index * 5, 90 + index * 4));
			pattern.lane(part).add(new Note(192 + index * 12, 48, 60 + index * 3, 70));
		}

		pattern.lane(Part.Fm1).add(new Note(60, 96, 67, 110));

		for (index in 6...9) {
			final part:Part = index;
			pattern.lane(part).add(new Note(index * 16, 96, 55 + index, 100));
		}

		pattern.lane(Part.Noise).add(new Note(0, 48, 60, 120));
		pattern.lane(Part.Dac).add(new Note(96, 48, 60, 127));
		pattern.lane(Part.Dac).add(new Note(288, 48, 60, 100));

		final second = song.add(new Pattern("chorus", 384));
		for (index in 0...4) {
			final part:Part = index;
			second.lane(part).add(new Note(index * 48, 144, 55 + index * 4, 100));
		}

		final track = song.track(new Track("one"));
		track.add(new Clip(0, 0, 384));
		track.add(new Clip(1, 384, 384, 3));

		final other = song.track(new Track("two"));
		other.add(new Clip(0, 192, 384, -5));

		song.tempo.set(288, 168.5);
		return song;
	}

	static function timing():Void {
		final tempo = new Tempo(96, 120);

		final quarter = tempo.samplesAt(96);
		final bar = tempo.samplesAt(384);

		says("a beat is a beat", quarter == 22050 && bar == 88200,
			"120 bpm puts a quarter at " + quarter + " samples and a bar at " + bar);

		tempo.set(384, 240);
		final later = tempo.samplesAt(384 + 96);

		says("a tempo change lands", later == 88200 + 11025,
			"the beat after the change is " + (later - bar) + " samples, half the one before");

		var walked = true;
		for (tick in 0...600) {
			if (tempo.tickAt(tempo.samplesAt(tick)) != tick) walked = false;
		}

		says("ticks round trip", walked, "600 ticks convert to samples and back unchanged");

		var rising = true;
		var last = -1;
		for (tick in 0...600) {
			final now = tempo.samplesAt(tick);
			if (now < last) rising = false;
			last = now;
		}

		says("time only moves on", rising, "no tick maps behind the one before it");
	}

	static function polyphony():Void {
		final pattern = new Pattern("overlap", 384);
		final lane = pattern.lane(Part.Fm1);

		lane.add(new Note(0, 96, 60, 100));
		lane.add(new Note(48, 96, 64, 100));
		lane.add(new Note(192, 48, 67, 100));

		final voices = new Voices();

		voices.policy = Polyphony.Strict;
		voices.resolve(lane);
		final strict = voices.count;
		final refused = voices.refused;

		voices.policy = Polyphony.Stealing;
		voices.resolve(lane);
		final stealing = voices.count;
		final cut = voices.count > 0 ? voices.endAt(0) : -1;

		voices.policy = Polyphony.Arpeggio;
		voices.arpeggio = 6;
		voices.resolve(lane);
		final arpeggio = voices.count;

		var overlapping = false;
		for (i in 1...voices.count) {
			if (voices.startAt(i) < voices.endAt(i - 1)) overlapping = true;
		}

		says("strict refuses", strict == 2 && refused == 1,
			strict + " of 3 notes sound, " + refused + " refused for overlapping");

		says("stealing cuts", stealing == 3 && cut == 48,
			"all 3 sound and the first is cut at " + cut + " where the second starts");

		says("arpeggio alternates", arpeggio > 3 && !overlapping,
			arpeggio + " slices, none overlapping");
	}

	static function poured(song:Song, span:Int, block:Int, into:Stream):Void {
		final sequencer = new Sequencer(song);
		var at = 0;

		while (at < span) {
			var until = at + block;
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

	static function raced():Void {
		final session = mdd.view.Session.started();
		final render = new mdd.play.Render(44100, mdd.play.Render.BLOCK);

		render.transport = session.transport;
		session.transport.play();

		final blocks = new haxe.atomic.AtomicInt(0);
		final alive = new haxe.atomic.AtomicInt(1);

		sys.thread.Thread.create(function():Void {
			while (alive.load() == 1) {
				final from = session.transport.advance(mdd.play.Render.BLOCK, 44100);
				render.serve(session.transport.stream, from, mdd.play.Render.BLOCK,
					session.transport.entering, true);
				blocks.add(1);
			}
		});

		var made = 0;
		var dropped = 0;

		for (round in 0...3000) {
			if (round % 40 == 0) Sys.sleep(0.001);

			final part:Part = round % 6;
			final note = new Note((round * 7) % 384, 24, 48 + (round % 24), 100);

			session.does(new AddNote(session.pattern, part, note));
			made++;

			if (round % 3 != 0) continue;

			session.does(new mdd.song.edit.RemoveNote(session.pattern, part, note));
			dropped++;
		}

		alive.store(0);
		Sys.sleep(0.05);

		var left = 0;
		final pattern = session.current();

		if (pattern != null) {
			for (index in 0...Part.COUNT) left += pattern.lane(index).notes.length;
		}

		says("the song survives being edited while it plays", left == made - dropped
			&& blocks.load() > 0,
			made + " notes written and " + dropped + " taken back while the render thread"
			+ " served " + blocks.load() + " blocks of the same song, leaving " + left
			+ " of an expected " + (made - dropped));
	}

	static function sounded():Void {
		final stream = new Stream(8192);
		final held = new mdd.play.Sounding();

		final wanted:Array<Int> = [];
		final parts:Array<Int> = [];

		for (index in 0...6) {
			final part:Part = index;
			final note = 48 + index * 5;

			stream.tune(index * 100, part, note);
			stream.keyOn(index * 100, part);

			wanted.push(note);
			parts.push(index);
		}

		for (index in 6...9) {
			final part:Part = index;
			final note = 60 + (index - 6) * 7;

			stream.square(index * 100, part, note);
			stream.attenuate(index * 100, part, 0);

			wanted.push(note);
			parts.push(index);
		}

		held.take(stream, 0);

		var right = 0;
		var worst = 0;

		for (at in 0...parts.length) {
			final index = parts[at];
			final away = held.notes[index] - wanted[at];
			final much = away < 0 ? -away : away;

			if (much == 0) right++;
			if (much > worst) worst = much;
		}

		says("the stream says what sounds", right == parts.length && worst == 0,
			right + " of " + parts.length + " notes read back off the register writes alone, "
			+ "on the part that was keyed");

		var on = 0;
		for (index in 0...9) if (held.keyed[index]) on++;

		says("and which of them are keyed", on == 9, on + " of 9 parts keyed on");

		for (index in 0...6) stream.keyOff(1000, index);
		for (index in 6...9) stream.attenuate(1000, index, 15);

		held.take(stream, 0);

		var still = 0;
		for (index in 0...9) if (held.keyed[index]) still++;

		says("and when they stop", still == 0, "every part reads silent after key off");
	}

	static function identical():Void {
		final song = written();
		final span = song.tempo.samplesAt(song.ends());

		final offline = new Stream(262144);
		poured(song, span, span, offline);

		says("the stream is made", offline.count > 0 && offline.dropped == 0,
			offline.count + " register writes across " + round(span / Tempo.TICKS, 2)
			+ " s of song");

		for (block in [128, 256, 1024, 4099]) {
			final live = new Stream(262144);
			poured(song, span, block, live);

			final parted = alike(offline, live);

			final said = parted == -1
				? live.count + " writes against " + offline.count
				: (parted >= 0 ? "they part at write " + parted
					: live.count + " writes, every one the same");

			says("live at " + block, parted == -2, said);
		}

		final quiet = new Stream(262144);
		song.muted[Part.Fm1.index()] = true;
		poured(song, span, span, quiet);
		song.muted[Part.Fm1.index()] = false;

		says("a mute is heard", quiet.count < offline.count,
			"muting FM1 drops " + (offline.count - quiet.count) + " writes");
	}

	static function faces():Void {
		final song = written();
		final said = Project.text(song);

		final again = Project.read(said);
		Project.unbulk(again, Project.bulk(song));

		says("the structure returns", Project.text(again) == said,
			said.length + " bytes of json written, read and written again unchanged");

		final root = Gate.root + "/export/project";
		final folder = root + "/exploded";
		final packed = root + "/packed.mdd";

		if (sys.FileSystem.exists(folder)) wipe(folder);
		if (sys.FileSystem.exists(packed)) sys.FileSystem.deleteFile(packed);

		Project.saveFolder(song, folder);
		Project.savePacked(song, packed);

		final opened = Project.openFolder(folder);
		final unpacked = Project.openPacked(packed);

		says("the folder returns", Project.text(opened) == said && sameSamples(song, opened),
			"project.json, chunks and " + song.samples.length + " sample file read back the same");

		says("the zip returns", Project.text(unpacked) == said && sameSamples(song, unpacked),
			"the same layout inside a zip reads back the same");

		final live = new Stream(262144);
		final span = song.tempo.samplesAt(song.ends());
		poured(song, span, span, live);

		final other = new Stream(262144);
		poured(unpacked, span, span, other);

		says("what it plays returns", alike(live, other) == -2,
			"a song read back from a zip makes the same " + live.count + " register writes");
	}

	static function sameSamples(one:Song, two:Song):Bool {
		if (one.samples.length != two.samples.length) return false;

		for (index in 0...one.samples.length) {
			final left = one.samples[index];
			final right = two.samples[index];

			if (left.length() != right.length()) return false;
			for (i in 0...left.length()) if (left.bytes[i] != right.bytes[i]) return false;
		}

		return true;
	}

	static function wipe(path:String):Void {
		if (!sys.FileSystem.exists(path)) return;

		if (!sys.FileSystem.isDirectory(path)) {
			sys.FileSystem.deleteFile(path);
			return;
		}

		for (entry in sys.FileSystem.readDirectory(path)) wipe(path + "/" + entry);
		sys.FileSystem.deleteDirectory(path);
	}

	static function chunks():Void {
		final out = new Chunks();

		out.add("SMPL", haxe.io.Bytes.ofString("one"));
		out.add("WHAT", haxe.io.Bytes.ofString("a tag from a newer build"));
		out.add("SMPL", haxe.io.Bytes.ofString("two"));

		final read = Chunks.read(out.bytes());
		final samples = Chunks.of(read, "SMPL");

		says("chunks are read", read.length == 3 && samples.length == 2,
			read.length + " chunks, " + samples.length + " of them samples");

		says("an odd chunk pads", samples.length == 2
			&& samples[0].body.toString() == "one" && samples[1].body.toString() == "two",
			"a three byte body is padded and the chunk after it still lands");

		says("an unknown tag is skipped", Chunks.of(read, "NOPE").length == 0
			&& samples[1].body.toString() == "two",
			"a tag this build does not know does not stop the ones it does");
	}

	static function commands():Void {
		final song = written();
		final history = new History();

		final before = Project.text(song);

		final note = new Note(120, 48, 72, 100);
		history.does(song, new AddNote(0, Part.Fm2, note));
		history.does(song, new MoveNote(0, Part.Fm2, note, 168, 76));
		history.does(song, new SetTempo(192, 96.5));
		history.does(song, new AddClip(0, new Clip(1, 768, 384)));
		history.does(song, new mdd.song.edit.AddPattern(
			new mdd.song.Pattern("spare", 384)));
		history.does(song, new mdd.song.edit.RemovePattern(0));

		final after = Project.text(song);

		var undone = 0;
		while (history.undo(song)) undone++;

		final back = Project.text(song);

		var redone = 0;
		while (history.redo(song)) redone++;

		final again = Project.text(song);

		says("edits change the song", before != after,
			"six edits move the song by " + Math.round(Math.abs(after.length - before.length))
			+ " bytes of written state");

		says("undo returns it", back == before,
			undone + " reverts put the song back byte for byte");

		says("the stack knows", undone == 6 && redone == 6,
			undone + " undone and " + redone
			+ " redone, and nothing left waiting either way");

		says("redo repeats it", again == after,
			redone + " replays put it back where the edits left it");
	}
}
