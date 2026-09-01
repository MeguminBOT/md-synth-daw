package mdd.gate;

import haxe.ds.Vector;
import mdd.format.Midi;
import mdd.format.Transcription;
import mdd.format.Vgm;
import mdd.format.Wav;
import mdd.host.Sdl;
import mdd.play.Render;
import mdd.play.Sequencer;
import mdd.play.Stream;
import mdd.song.Note;
import mdd.song.Part;
import mdd.song.Song;
import mdd.song.Tempo;
import mdd.view.Files;
import mdd.view.Session;

@:unreflective
class TierCheck {
	static inline final RATE = 44100;

	static var failed:Int = 0;
	static var ran:Int = 0;

	public static function run(args:Array<String>):Int {
		failed = 0;
		ran = 0;

		Sys.println("  tier");

		final at = args.indexOf("--wav");
		final into = at >= 0 && at + 1 < args.length ? args[at + 1] : "";

		round(into);
		midi();
		sampling();
		filed();
		keeping();
		levelled();

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
		Sys.println("    " + StringTools.rpad(name, " ", 40) + said + (ok ? "" : "   FAILED"));
	}

	static function levelled():Void {
		final song = mdd.gate.StreamCheck.written();
		final span = song.tempo.samplesAt(song.ends());

		final full = new Stream(262144);
		new Sequencer(song).emit(full, 0, span);

		for (index in 0...mdd.song.Part.COUNT) song.volume[index] = 40;

		final quiet = new Stream(262144);
		new Sequencer(song).emit(quiet, 0, span);

		says("a channel fader is heard", loudness(full) > loudness(quiet) * 1.5,
			"the same song renders at " + shown(loudness(full), 4) + " at full level and "
			+ shown(loudness(quiet), 4) + " with every fader at a third");

		for (index in 0...mdd.song.Part.COUNT) song.volume[index] = 0;

		final off = new Stream(262144);
		new Sequencer(song).emit(off, 0, span);

		says("and a fader down is all but silence", loudness(off) < loudness(full) * 0.2,
			"every fader at nothing renders at " + shown(loudness(off), 5)
			+ ", which is the switching transients the register writes leave behind and"
			+ " nothing that was keyed");
	}

	static function loudness(stream:Stream):Float {
		final render = new Render(RATE, Render.BLOCK);
		var done = 0;
		var most = 0.0;

		while (done < RATE * 3) {
			final from = Std.int(done * (Tempo.TICKS / RATE));
			final many = render.serve(stream, from, Render.BLOCK, 0);
			if (many <= 0) break;

			for (i in 0...many * 2) {
				final value = render.block[i] < 0 ? -render.block[i] : render.block[i];
				if (value > most) most = value;
			}

			done += many;
		}

		return most;
	}

	static function shown(value:Float, places:Int):Float {
		final scale = Math.pow(10, places);
		return Math.round(value * scale) / scale;
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

	static function keyed(stream:Stream):Array<Int> {
		final out:Array<Int> = [];

		var half = 0;
		var address = -1;

		for (index in 0...stream.count) {
			if (stream.kindAt(index) == Stream.PSG) continue;

			final port = stream.portAt(index);
			final value = stream.valueAt(index);

			if ((port & 1) == 0) {
				half = (port >> 1) & 1;
				address = value;
				continue;
			}

			if (half != 0 || address != 0x28 || (value & 0xF0) == 0) continue;

			final within = value & 3;
			if (within == 3) continue;

			out.push((stream.tickAt(index) << 4) | (within + ((value & 4) != 0 ? 3 : 0)));
		}

		return out;
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

	static function filed():Void {
		final into = Gate.root + "/export/files";

		wipe(into);
		sys.FileSystem.createDirectory(into);

		says("a suffix is added once", Files.suffixed("song", "mdd") == "song.mdd"
			&& Files.suffixed("song.mdd", "mdd") == "song.mdd"
			&& Files.suffixed("song.MDD", "mdd") == "song.MDD"
			&& Files.suffixed("song.vgm", "mdd") == "song.vgm.mdd",
			"a name without one gets it, a name with it keeps it, and a different one is kept "
			+ "and added to");

		final session = Session.started();
		final pattern = session.current();

		for (index in 0...4) {
			final part:Part = index;
			pattern.lane(part).add(new Note(index * 48, 96, 52 + index * 5, 100));
		}

		pattern.lane(Part.Dac).add(new Note(0, 48, 60, 110));
		pattern.lane(Part.Psg1).add(new Note(96, 96, 72, 100));

		final files = new Files(session);

		final saved = files.save(into + "/song");
		final vgm = files.exportVgm(into + "/song");
		final wav = files.exportWav(into + "/song");
		final mid = files.exportMidi(into + "/song");

		says("every export names itself", StringTools.endsWith(saved, ".mdd")
			&& StringTools.endsWith(vgm, ".vgm") && StringTools.endsWith(wav, ".wav")
			&& StringTools.endsWith(mid, ".mid"),
			"the project, the vgm, the wav and the midi file all took their own suffix");

		var wrote = 0;
		for (name in [saved, vgm, wav, mid]) if (sys.FileSystem.exists(name)) wrote++;

		says("every export lands", wrote == 4,
			wrote + " of 4 files are on disk, the project as a zip and the rest as themselves");

		var opened:Null<mdd.song.Song> = null;
		var brought = "";

		final reader = new Files(session);
		reader.onLoad = function(song:mdd.song.Song):Void opened = song;

		try {
			reader.load(saved);
		} catch (e:Dynamic) {
			brought = "" + e;
		}

		says("a saved project opens", opened != null && brought == "",
			brought != "" ? brought
				: opened.patterns.length + " patterns, " + opened.instruments.length
				+ " instruments, " + opened.banks.length + " banks and "
				+ opened.samples.length + " samples come back");

		says("and it is the same song",
			opened != null && mdd.format.Project.text(opened)
				== mdd.format.Project.text(session.song),
			"the written form of what came back is the written form of what went in");

		final stream = new Stream(262144);
		Vgm.read(sys.io.File.getBytes(vgm), stream);

		final wanted = new Stream(262144);
		final sequencer = new Sequencer(session.song);
		sequencer.emit(wanted, 0, session.song.tempo.samplesAt(session.song.ends()));

		says("the exported vgm plays", alike(stream, wanted) == -2,
			stream.count + " register writes read back out of the exported vgm, every one the "
			+ "same as the song makes");

		final sound = Wav.read(sys.io.File.getBytes(wav));
		var loudest = 0.0;

		for (i in 0...sound.samples.length) {
			final value = sound.samples[i] < 0 ? -sound.samples[i] : sound.samples[i];
			if (value > loudest) loudest = value;
		}

		says("the exported wav sounds", sound.channels == 2 && sound.frames > 0
			&& loudest > 0.001,
			shown(sound.frames / sound.rate, 2) + " s of stereo at " + sound.rate
			+ " Hz, loudest sample " + shown(loudest, 4));

		final back = mdd.format.Midi.read(sys.io.File.getBytes(mid), "back");
		var notes = 0;

		for (held in back.patterns) {
			for (index in 0...Part.COUNT) notes += held.lanes[index].notes.length;
		}

		says("the exported midi reads", notes > 0,
			notes + " notes come back out of the exported midi file");
	}

	static function keeping():Void {
		final into = Gate.root + "/export/keeping";

		wipe(into);
		sys.FileSystem.createDirectory(into);

		final session = Session.started();
		final files = new Files(session);

		files.every = 2;

		says("it waits its interval", !files.tick(1.0) && files.tick(1.5),
			"nothing at one second of a two second interval, and a save at two and a half");

		final made = files.save(into + "/held");

		says("and a save takes the path", files.path == made
			&& sys.FileSystem.exists(made),
			"saving by hand puts the path on the files so the next one goes there");

		says("and nothing changed means nothing written", !files.tick(3.0),
			"an interval with no edit behind it does not rewrite the file");

		session.does(new mdd.song.edit.AddNote(0, Part.Fm1,
			new mdd.song.Note(0, 48, 60, 100)));

		final was = files.kept;
		final wrote = files.tick(3.0);

		says("and an edit brings it back", wrote && files.kept == was + 1,
			"one note written, and the next interval saved it, " + files.kept
			+ " saves in all");

		final recovery = new Files(Session.started());
		recovery.every = 1;
		recovery.session.does(new mdd.song.edit.AddNote(0, Part.Fm1,
			new mdd.song.Note(0, 48, 60, 100)));

		recovery.tick(2.0);

		says("and an unsaved song has somewhere to go", recovery.recovered != ""
			&& sys.FileSystem.exists(recovery.recovered),
			"a song that was never saved by hand is kept at "
			+ Files.name(recovery.recovered));

		says("a portable copy is told by a file", !mdd.host.Settings.carried()
			|| sys.FileSystem.exists(mdd.host.Paths.beside() + "/portable.txt"),
			"settings live beside the program only when a marker beside it says so");
	}

	static function started(made:Transcription):Array<Int> {
		final out:Array<Int> = [];
		final tempo = made.song.tempo;

		for (index in 0...6) {
			for (pattern in made.song.patterns) {
				for (note in pattern.lanes[index].notes) {
					out.push((tempo.samplesAt(note.at) << 4) | index);
				}
			}
		}

		return out;
	}

	static function round(into:String):Void {
		final song = StreamCheck.written();
		final span = song.tempo.samplesAt(song.ends());

		final made = new Stream(262144);
		final sequencer = new Sequencer(song);
		sequencer.emit(made, 0, span);

		final bytes = Vgm.write(made, 0, span, song.tempo.rate);

		final back = new Stream(262144);
		final vgm = Vgm.read(bytes, back);

		says("composed and exported", made.count > 0 && bytes.length > 64,
			made.count + " register writes become a " + bytes.length + " byte vgm across "
			+ shown(span / Tempo.TICKS, 2) + " s");

		says("exported and imported", alike(made, back) == -2,
			"the vgm reads back as the same " + back.count + " writes");

		final transcribed = Transcription.of(back, vgm.rate, song.name);
		final again = new Stream(262144);
		final replay = new Sequencer(transcribed.song);

		replay.emit(again, 0, transcribed.song.tempo.samplesAt(transcribed.song.ends()));

		final wanted = keyed(made);
		final got = started(transcribed);
		final taken = [for (i in 0...got.length) false];

		final slack = Std.int(Tempo.TICKS * 60 / (transcribed.beats * 96)) + 1;

		var placed = 0;
		var worst = 0;
		var doubled = 0;

		for (i in 0...wanted.length) {
			for (j in 0...i) if (wanted[j] == wanted[i]) {
				doubled++;
				break;
			}
		}

		for (want in wanted) {
			final channel = want & 0x0F;
			final at = want >> 4;

			var best = -1;
			var near = slack + 1;

			for (i in 0...got.length) {
				if (taken[i] || (got[i] & 0x0F) != channel) continue;

				final off = (got[i] >> 4) - at;
				final size = off < 0 ? -off : off;

				if (size >= near) continue;

				near = size;
				best = i;
			}

			if (best < 0) continue;

			taken[best] = true;
			placed++;
			if (near > worst) worst = near;
		}

		says("imported and compared", placed == wanted.length - doubled && worst <= slack,
			placed + " of " + (wanted.length - doubled) + " key ons come back as a note on the "
			+ "same channel, none further than " + worst + " samples from where it was, which "
			+ "is " + shown(worst * 1000.0 / Tempo.TICKS, 2) + " ms and inside one musical tick; "
			+ doubled + " more land on a channel at the sample another already did, and cannot "
			+ "be two notes");

		says("and the notes still play", again.count > 0,
			again.count + " register writes when the imported song is played again, against "
			+ made.count + " the piece made; the difference is the polyphony policy refusing "
			+ "what one voice cannot hold");

		final frames = Std.int(span * (RATE / Tempo.TICKS));
		final sound = new Vector<cpp.Float32>(frames * 2);

		for (i in 0...sound.length) sound[i] = 0;

		final render = new Render(RATE, Render.BLOCK);
		var done = 0;
		var next = 0;

		while (done < frames) {
			final from = Std.int(done * (Tempo.TICKS / RATE));
			final many = render.serve(made, from, Render.BLOCK, 0);

			for (i in 0...many) {
				if ((done + i) * 2 + 1 >= sound.length) break;
				sound[(done + i) * 2] = render.block[i * 2];
				sound[(done + i) * 2 + 1] = render.block[i * 2 + 1];
			}

			done += many;
		}

		var loudest = 0.0;
		for (i in 0...sound.length) {
			final value = sound[i] < 0 ? -sound[i] : sound[i];
			if (value > loudest) loudest = value;
		}

		says("and it makes a sound", loudest > 0.001,
			shown(frames / RATE, 2) + " s rendered from the exported stream, loudest sample "
			+ shown(loudest, 4));

		if (into == "") return;

		sys.io.File.saveBytes(into, Wav.write(sound, frames, 2, RATE));
		Sys.println("    " + StringTools.rpad("wrote", " ", 30) + into);
	}

	static function midi():Void {
		final song = StreamCheck.written();
		final bytes = Midi.write(song);
		final back = Midi.read(bytes, song.name);

		var wanted = 0;
		final flat = song.unshared();

		for (pattern in flat.patterns) {
			for (index in 0...6) wanted += pattern.lanes[index].notes.length;
		}

		var got = 0;
		for (pattern in back.patterns) {
			for (index in 0...6) got += pattern.lanes[index].notes.length;
		}

		says("a song becomes midi", bytes.length > 22 && bytes.getString(0, 4) == "MThd",
			bytes.length + " bytes, " + (Part.COUNT + 1) + " tracks");

		says("and midi becomes a song", got == wanted,
			got + " of " + wanted + " fm notes come back, on the parts they left on");

		var same = true;
		for (i in 0...back.tempo.at.length) {
			if (Math.abs(back.tempo.bpm[i] - song.tempo.bpm[i]) > 0.5) same = false;
		}

		says("the tempo survives", back.tempo.at.length == song.tempo.at.length && same,
			back.tempo.at.length + " tempo changes at "
			+ shown(back.tempo.bpm[0], 1) + " and " + shown(back.tempo.bpm[1], 1) + " bpm");
	}

	static function sampling():Void {
		final frames = 4410;
		final made = new Vector<cpp.Float32>(frames);

		for (i in 0...frames) made[i] = Math.sin(i * 2 * Math.PI * 440 / RATE) * 0.8;

		final bytes = Wav.write(made, frames, 1, RATE);
		final wav = Wav.read(bytes);

		var worst = 0.0;
		for (i in 0...frames) {
			final off = Math.abs(wav.samples[i] - made[i]);
			if (off > worst) worst = off;
		}

		says("a wav writes and reads", wav.frames == frames && wav.rate == RATE
			&& worst < 0.0001,
			frames + " frames at " + wav.rate + " Hz, worst sample off by "
			+ shown(worst, 6));

		final held = wav.bytes(8000);
		var lowest = 255;
		var highest = 0;

		for (i in 0...held.length) {
			if (held[i] < lowest) lowest = held[i];
			if (held[i] > highest) highest = held[i];
		}

		final wanted = Math.round(frames * 8000.0 / RATE);

		says("and becomes converter bytes", lowest < 60 && highest > 195
			&& Math.abs(held.length - wanted) <= 1,
			held.length + " unsigned bytes between " + lowest + " and " + highest
			+ ", centred on 128, resampled from " + RATE + " Hz to 8000");
	}
}
