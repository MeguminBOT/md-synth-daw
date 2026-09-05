package mdd.gate;

import haxe.ds.Vector;
import mdd.format.Coded;
import mdd.format.Flac;
import mdd.format.Wav;
import mdd.play.Mixdown;
import mdd.play.Mixing;
import mdd.song.Song;

@:unreflective
class MixCheck {
	static var failed:Int = 0;
	static var ran:Int = 0;

	public static function run(args:Array<String>):Int {
		failed = 0;
		ran = 0;

		Sys.println("  mix");

		final where = args.indexOf("--out");
		final into = where >= 0 && where + 1 < args.length ? args[where + 1] : "";

		shaped();
		written(into);
		bounced();
		patched();
		kitted();
		consoled(into);
		furnished();
		threaded();
		imported();

		Sys.println("    " + (ran - failed) + " of " + ran + " checks");

		if (failed > 0) {
			Sys.println("    failed");
			return 1;
		}

		Sys.println("    passed");
		return 0;
	}

	static function tone(frames:Int, rate:Int, channels:Int):Vector<cpp.Float32> {
		final held = new Vector<cpp.Float32>(frames * channels);

		for (index in 0...frames) {
			final turn = 2 * Math.PI * 440.0 * index / rate;
			final value = Math.sin(turn) * 0.5 + Math.sin(turn * 3) * 0.17;

			for (side in 0...channels) held[index * channels + side] = value;
		}

		return held;
	}

	static function shaped():Void {
		final rate = 44100;
		final held = tone(rate, rate, 2);

		final one = Wav.write(held, rate, 2, rate, 16, false);
		final two = Wav.write(held, rate, 2, rate, 24, false);
		final three = Wav.write(held, rate, 2, rate, 32, false);

		says("a wav takes its depth", one.length == 44 + rate * 4
			&& two.length == 44 + rate * 6 && three.length == 44 + rate * 8,
			"one second of stereo is " + one.length + " bytes at 16, " + two.length
			+ " at 24 and " + three.length + " at 32 float");

		final flac = Flac.write(held, rate, 2, rate, 16, ["TITLE=a tone"]);

		final vorbis = Coded.vorbis(held, rate, 2, rate, 0.6, ["TITLE=a tone"]);
		final quick = tone(48000, 48000, 2);
		final opus = Coded.opus(quick, 48000, 2, 48000, 128, ["TITLE=a tone"]);

		says("an ogg is smaller than the flac", vorbis.length > 0
			&& vorbis.getString(0, 4) == "OggS" && vorbis.length < flac.length,
			vorbis.length + " bytes of vorbis at q6 against " + flac.length + " of flac");

		says("an opus is a fraction of the wav", opus.length > 0
			&& opus.getString(0, 4) == "OggS" && opus.length < one.length / 4,
			opus.length + " bytes of opus at 128k for a second at 48000, against "
			+ one.length + " of wav and " + flac.length + " of flac, which on a tone this "
			+ (flac.length < opus.length ? "plain the lossless file beats"
				: "plain still trails") + " it");

		says("a flac is smaller than the wav it came from",
			flac.getString(0, 4) == "fLaC" && flac.length < one.length,
			flac.length + " bytes against " + one.length + ", "
			+ Math.round(flac.length * 100.0 / one.length) + " per cent of it");
	}

	static function written(into:String):Void {
		if (into == "") return;

		if (!sys.FileSystem.exists(into)) sys.FileSystem.createDirectory(into);

		final rate = 44100;
		final frames = rate * 2;
		final held = tone(frames, rate, 2);

		sys.io.File.saveBytes(into + "/tone-16.wav", Wav.write(held, frames, 2, rate, 16, false));
		sys.io.File.saveBytes(into + "/tone-24.wav", Wav.write(held, frames, 2, rate, 24, false));
		sys.io.File.saveBytes(into + "/tone-32.wav", Wav.write(held, frames, 2, rate, 32, false));

		sys.io.File.saveBytes(into + "/tone-16.flac",
			Flac.write(held, frames, 2, rate, 16, ["TITLE=a tone", "ARTIST=the gate"]));
		sys.io.File.saveBytes(into + "/tone-24.flac",
			Flac.write(held, frames, 2, rate, 24, ["TITLE=a tone"]));

		final one = new Vector<cpp.Float32>(frames);
		for (index in 0...frames) one[index] = held[index * 2];

		sys.io.File.saveBytes(into + "/tone-mono.flac",
			Flac.write(one, frames, 1, rate, 16, []));

		sys.io.File.saveBytes(into + "/tone.ogg",
			Coded.vorbis(held, frames, 2, rate, 0.6,
				["TITLE=a tone", "ARTIST=the gate", "ALBUM=Mega Drive"]));

		final fast = tone(48000 * 2, 48000, 2);

		sys.io.File.saveBytes(into + "/tone.opus",
			Coded.opus(fast, 48000 * 2, 2, 48000, 128,
				["TITLE=a tone", "ARTIST=the gate", "ALBUM=Mega Drive"]));

		Sys.println("    wrote the tones to " + into);
	}

	static function bounced():Void {
		final song = new Song("a bounce", 96, 150);
		final pattern = song.add(new mdd.song.Pattern("one", 384));

		final track = song.track(new mdd.song.Track("fm"));
		track.add(new mdd.song.Clip(0, 0, 384));

		mdd.song.Shipped.into(song);

		pattern.lane(mdd.song.Part.Fm1).add(new mdd.song.Note(0, 96, 60, 127, song.rack[0]));
		pattern.lane(mdd.song.Part.Fm1).add(new mdd.song.Note(192, 96, 67, 127, song.rack[0]));

		final mixing = new Mixing();

		mixing.rate = 44100;
		mixing.padStart = 0.5;
		mixing.padEnd = 1.0;
		mixing.normalise = true;
		mixing.ceiling = -1;

		final made = Mixdown.of(song, mixing);

		final ahead = Math.round(mixing.padStart * mixing.rate);
		var quiet = true;

		for (index in 0...ahead * made.channels) if (made.samples[index] != 0) quiet = false;

		says("silence pads the front", ahead > 0 && quiet && made.frames > ahead,
			ahead + " frames of silence before " + made.frames + " in all, which is "
			+ round(made.seconds(), 2) + " s");

		final want = Math.pow(10, mixing.ceiling / 20.0);

		says("the master is normalised", Math.abs(made.peak - want) < 0.001 && made.gain > 0,
			"the loudest sample is " + round(made.peak, 4) + " against a ceiling of "
			+ mixing.ceiling + " dB, which is " + round(want, 4) + ", after a gain of "
			+ round(made.gain, 3));

		mixing.normalise = false;
		mixing.padStart = 0;
		mixing.padEnd = 0;
		mixing.stereo = false;

		final mono = Mixdown.of(song, mixing);

		says("a mono mixdown folds both sides", mono.channels == 1
			&& mono.frames * 1 == mono.samples.length,
			mono.frames + " frames of one channel, " + mono.samples.length + " samples");

		mixing.stereo = true;
		mixing.rate = 48000;

		final faster = Mixdown.of(song, mixing);

		final ogg = Coded.vorbis(faster.samples, faster.frames, faster.channels,
			faster.rate, 0.6, ["TITLE=" + song.name]);

		final opus = Coded.opus(faster.samples, faster.frames, faster.channels,
			faster.rate, 128, ["TITLE=" + song.name]);

		says("a song goes out as ogg and opus", ogg.length > 512 && opus.length > 512
			&& ogg.getString(0, 4) == "OggS" && opus.getString(0, 4) == "OggS",
			"a " + round(faster.seconds(), 2) + " s mixdown is " + ogg.length
			+ " bytes of vorbis and " + opus.length + " of opus");

		says("a mixdown takes the rate it is asked for", faster.rate == 48000
			&& faster.frames > made.frames * 0,
			faster.frames + " frames at 48000 against " + mono.frames + " at 44100, "
			+ round(faster.seconds(), 2) + " s either way");
	}

	static function brightness(made:Mixdown):Float {
		var total = 0.0;
		var edge = 0.0;

		for (index in 1...made.samples.length) {
			final one = made.samples[index];
			final gap = one - made.samples[index - 1];

			total += one * one;
			edge += gap * gap;
		}

		return total <= 0 ? 0 : edge / total;
	}

	static function heard(into:String):Void {
		if (into == "" || !sys.FileSystem.isDirectory(Gate.root + "/vendor/vgm")) return;

		final name = Fixtures.found("Green Hill");
		if (name == "") return;

		final source = new mdd.play.Stream(1 << 22);
		final vgm = mdd.format.Vgm.read(sys.io.File.getBytes(name), source);
		final song = mdd.format.Transcription.of(source, vgm.rate, name).song;

		final mixing = new Mixing();

		mixing.rate = 44100;
		mixing.padStart = 0;
		mixing.padEnd = 0;
		mixing.normalise = true;
		mixing.ceiling = -1;

		final named = ["chip", "model-1", "model-2"];
		final want = [mdd.play.Render.CHIP, mdd.play.Render.MODEL_ONE, mdd.play.Render.MODEL_TWO];

		for (index in 0...named.length) {
			mixing.console = want[index];

			final made = Mixdown.of(song, mixing);
			final file = into + "/green-hill-" + named[index] + ".wav";

			sys.io.File.saveBytes(file, Wav.write(made.samples, made.frames, made.channels,
				mixing.rate, 16, false));

			Sys.println("    wrote " + file + ", " + round(made.seconds(), 1) + " s, brightness "
				+ round(brightness(made), 4));
		}
	}

	static function consoled(into:String):Void {
		final song = new Song("a console", 96, 150);
		final pattern = song.add(new mdd.song.Pattern("one", 384));

		final track = song.track(new mdd.song.Track("fm"));
		track.add(new mdd.song.Clip(0, 0, 384));

		mdd.song.Shipped.into(song);

		pattern.lane(mdd.song.Part.Fm1).add(new mdd.song.Note(0, 192, 72, 127, song.rack[0]));
		pattern.lane(mdd.song.Part.Psg1).add(new mdd.song.Note(0, 192, 84, 127, song.rack[6]));

		final mixing = new Mixing();

		mixing.rate = 44100;
		mixing.normalise = false;
		mixing.padStart = 0;
		mixing.padEnd = 0;
		mixing.stereo = false;

		mixing.console = mdd.play.Render.CHIP;
		final chip = brightness(Mixdown.of(song, mixing));

		mixing.console = mdd.play.Render.MODEL_TWO;
		final two = brightness(Mixdown.of(song, mixing));

		mixing.console = mdd.play.Render.MODEL_ONE;
		final one = brightness(Mixdown.of(song, mixing));

		says("the console output stage darkens what the chip sends",
			chip > two && two > one && one > 0,
			"edge energy against total is " + round(chip, 4) + " from the chip alone, "
			+ round(two, 4) + " through a model 2 and " + round(one, 4) + " through a model 1");

		heard(into);
	}

	static function furnished():Void {
		final library = mdd.song.Library.embedded();

		final song = new Song("import", 96, 120);

		final first = library.into(song);
		final banks = song.banks.length;
		final again = library.into(song);

		says("the shipped banks are built in and land on any song",
			library.count() > 0 && first == library.count() && again == 0,
			library.count() + " presets embedded in the binary across " + library.names.length
			+ " banks, " + first + " of them added to a song read from a file and " + again
			+ " added a second time");
	}

	static function kitted():Void {
		final bytes = haxe.io.Bytes.alloc(600);
		for (at in 0...bytes.length) bytes.set(at, (at * 7) & 0xFF);

		final coded = haxe.crypto.Base64.encode(bytes);

		final said = "{\"name\": \"a kit\", \"presets\": ["
			+ "{\"name\": \"Kick 1\", \"tags\": [\"one\"], \"rate\": 16000,"
			+ " \"root\": 60, \"pcm\": \"" + coded + "\"},"
			+ "{\"name\": \"Snare 1\", \"tags\": [\"two\"], \"rate\": 8000,"
			+ " \"root\": 48, \"pcm\": \"" + coded + "\"}]}";

		final library = new mdd.song.Library();
		final many = library.reads(said);

		final song = new Song("kit", 96, 120);
		library.into(song);

		final one = song.samples.length == 0 ? null : song.samples[0];

		var same = one != null && one.length() == bytes.length;
		if (same) for (at in 0...bytes.length) if (one.bytes[at] != bytes.get(at)) same = false;

		says("a kit reads back as samples", many == 2 && song.samples.length == 2 && same
			&& one.rate == 16000,
			many + " presets read, " + song.samples.length + " samples, the first "
			+ (one == null ? 0 : one.length()) + " bytes at "
			+ (one == null ? 0 : one.rate) + " Hz, "
			+ (same ? "byte for byte" : "and the bytes do not match"));
	}

	static function patched():Void {
		final made = new mdd.song.Patch();

		made.algorithm = 5;
		made.feedback = 6;

		for (slot in 0...mdd.song.Patch.SLOTS) {
			made.multiple[slot] = slot + 3;
			made.detune[slot] = (slot + 1) & 7;
			made.totalLevel[slot] = 17 + slot * 9;
			made.keyScale[slot] = slot & 3;
			made.attack[slot] = 31 - slot * 4;
			made.decay[slot] = 5 + slot;
			made.sustain[slot] = 9 + slot;
			made.release[slot] = 12 - slot;
			made.sustainLevel[slot] = 4 + slot;
			made.ssg[slot] = 8 + slot;
		}

		final bytes = mdd.format.Tfi.write(made);
		final back = mdd.format.Tfi.read(bytes);

		says("a tfi is forty two bytes", bytes.length == mdd.format.Tfi.BYTES,
			bytes.length + " bytes, two for the algorithm and feedback and ten for each of "
			+ mdd.song.Patch.SLOTS + " operators");

		says("and it reads back as the patch it was",
			back != null && mdd.format.Tfi.same(back, made),
			back == null ? "nothing came back"
				: "algorithm " + back.algorithm + ", feedback " + back.feedback
				+ ", and every operator field the same");

		final other = mdd.format.Tfi.read(bytes);
		other.totalLevel[2] = made.totalLevel[2] + 1;

		says("and one field apart is not the same",
			!mdd.format.Tfi.same(other, made),
			"a single total level moved by one is told apart");
	}

	static function threaded():Void {
		final song = new Song("a bounce", 96, 150);
		final pattern = song.add(new mdd.song.Pattern("one", 384 * 16));

		final track = song.track(new mdd.song.Track("fm"));
		track.add(new mdd.song.Clip(0, 0, 384 * 16));

		mdd.song.Shipped.into(song);

		for (bar in 0...16) {
			pattern.lane(mdd.song.Part.Fm1).add(new mdd.song.Note(bar * 384, 96, 60, 127,
				song.rack[0]));
		}

		final mixing = new Mixing();
		mixing.rate = 44100;

		final made = Mixdown.made();

		sys.thread.Thread.create(function():Void {
			try {
				made.runs(song, mixing);
			} catch (e:Dynamic) {
				made.stops();
			}
		});

		final began = haxe.Timer.stamp();

		var worst = 0.0;
		var spins = 0;

		while (made.reach() < 1 && haxe.Timer.stamp() - began < 30) {
			final at = haxe.Timer.stamp();
			final held:Array<mdd.song.Point> = [];

			for (index in 0...4000) held.push(new mdd.song.Point(index, index));

			final took = haxe.Timer.stamp() - at;
			if (took > worst) worst = took;

			spins++;
		}

		final over = haxe.Timer.stamp() - began;

		says("a bounce leaves the main thread running", worst < 0.2 && spins > 20
			&& made.reach() >= 1,
			spins + " rounds of allocation while it rendered, worst stall "
			+ round(worst * 1000, 1) + " ms across " + round(over, 2) + " s");
	}

	static function imported():Void {
		final where = Gate.root + "/vendor/vgm";
		if (!sys.FileSystem.isDirectory(where)) return;

		var name = "";
		name = Fixtures.found("Green Hill");

		if (name == "") return;

		final source = new mdd.play.Stream(1 << 22);
		final vgm = mdd.format.Vgm.read(sys.io.File.getBytes(name), source);
		final song = mdd.format.Transcription.of(source, vgm.rate, name).song;

		final mixing = new Mixing();

		mixing.rate = 44100;
		mixing.padStart = 0;
		mixing.padEnd = 0;
		mixing.normalise = false;

		final made = Mixdown.of(song, mixing);
		final want = song.tempo.samplesAt(song.ends()) / mdd.song.Tempo.TICKS;

		var loud = 0;
		final step = made.rate;

		var quiet = 0;
		var at = 0;

		while (at + step <= made.frames) {
			var most = 0.0;

			for (index in at...at + step) {
				final value = made.samples[index * made.channels];
				final held = value < 0 ? -value : value;
				if (held > most) most = held;
			}

			if (most < 0.002) quiet++;
			at += step;
		}

		final wav = Wav.write(made.samples, made.frames, made.channels, made.rate, 16,
			false);

		final flac = Flac.write(made.samples, made.frames, made.channels, made.rate, 16,
			[]);

		final ogg = Coded.vorbis(made.samples, made.frames, made.channels, made.rate,
			0.5, []);

		final wanted = made.frames * made.channels * 2 + 44;

		says("and every writer takes it whole",
			wav.length == wanted && flac.length > wanted / 4 && ogg.length > 100000,
			"a " + round(made.seconds(), 1) + " s bounce writes " + wav.length
			+ " bytes of wav against " + wanted + " wanted, " + flac.length
			+ " of flac and " + ogg.length + " of ogg");

		mixing.kind = Mixing.OPUS;

		final over = Mixdown.of(song, mixing);
		final opus = Coded.opus(over.samples, over.frames, over.channels, over.rate,
			128, []);

		says("and opus takes a rate it knows", over.rate == 48000 && opus.length > 100000,
			round(over.seconds(), 1) + " s at " + over.rate + " Hz makes "
			+ opus.length + " bytes");

		final into = Gate.root + "/export/exported";
		if (!sys.FileSystem.exists(into)) sys.FileSystem.createDirectory(into);

		final session = new mdd.app.Session(song);
		final files = new mdd.app.Files(session);

		files.mixing.kind = Mixing.WAV;
		files.mixing.rate = 44100;
		files.mixing.padStart = 0;
		files.mixing.padEnd = 0;
		files.mixing.normalise = false;

		final one = files.exportAudio(into + "/whole");
		final two = files.exportWav(into + "/plain");
		final three = files.exportMidi(into + "/whole");

		final oneSize = one == "" ? 0 : sys.FileSystem.stat(one).size;
		final twoSize = two == "" ? 0 : sys.FileSystem.stat(two).size;
		final threeSize = three == "" ? 0 : sys.FileSystem.stat(three).size;

		says("the export menu writes the whole song",
			oneSize > wanted - 64 && twoSize > wanted - 64,
			"exportAudio wrote " + Math.round(oneSize / 1024) + " kb and exportWav "
			+ Math.round(twoSize / 1024) + " kb, against " + Math.round(wanted / 1024)
			+ " kb of song");

		final back = mdd.format.Midi.read(sys.io.File.getBytes(three), "back");

		var notes = 0;
		for (at in 0...back.patterns.length) {
			final pattern = back.patterns[at];
			for (index in 0...mdd.song.Part.COUNT) notes += pattern.lane(index).notes.length;
		}

		var kept = 0;
		for (at in 0...song.patterns.length) {
			final pattern = song.patterns[at];
			for (index in 0...mdd.song.Part.COUNT) kept += pattern.lane(index).notes.length;
		}

		final held = sys.io.File.getBytes(three);
		final division = (held.get(12) << 8) | held.get(13);

		final spans = back.tempo.samplesAt(back.ends()) / mdd.song.Tempo.TICKS;

		says("and midi carries the notes", threeSize > 1024 && notes == kept
			&& division == mdd.format.Midi.PPQN && spans > want - 2 && spans < want + 2,
			Math.round(threeSize / 1024) + " kb of midi at " + division
			+ " ticks a beat, holding " + notes + " notes against " + kept
			+ " in the song, and lasting " + round(spans, 1) + " s against "
			+ round(want, 1) + " s");

		final packed = into + "/round." + mdd.Config.SUFFIX;
		mdd.format.Project.save(song, packed);

		final again = mdd.format.Project.open(packed);
		final reopened = again == null ? 0.0
			: again.tempo.samplesAt(again.ends()) / mdd.song.Tempo.TICKS;

		says("a saved song still knows its length", again != null && reopened > want - 1,
			round(reopened, 1) + " s after a save and a load, against " + round(want, 1)
			+ " s before");

		final fresh = mdd.app.Session.started(mdd.song.Library.embedded()).song;
		final blank = fresh.tempo.samplesAt(fresh.ends()) / mdd.song.Tempo.TICKS;

		says("a new document is empty and ready",
			blank == 0 && fresh.patterns.length > 0 && fresh.tracks.length > 0,
			"a fresh document holds " + fresh.patterns.length + " empty pattern across "
			+ fresh.tracks.length + " tracks and " + round(blank, 1) + " s of arrangement");

		says("an imported song bounces whole",
			made.seconds() > want - 1 && made.seconds() < want + 1 && quiet == 0
			&& made.lost == 0,
			round(made.seconds(), 1) + " s bounced of " + round(want, 1)
			+ " s of song, " + made.writes + " writes with " + made.lost
			+ " lost, and " + quiet + " of " + Math.floor(made.frames / step)
			+ " seconds silent");
	}

	static function says(name:String, ok:Bool, said:String):Void {
		ran++;
		if (!ok) failed++;

		Sys.println("    " + StringTools.rpad(name, " ", 34) + said + (ok ? "" : "      FAILED"));
	}

	static function round(value:Float, places:Int):Float {
		final scale = Math.pow(10, places);
		return Math.round(value * scale) / scale;
	}
}
