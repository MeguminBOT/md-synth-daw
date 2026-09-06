package mdd.gate;

import haxe.io.Bytes;
import mdd.play.Stream;

@:unreflective
class MangleCheck {
	static inline final ROUNDS = 1500;
	static inline final PATIENCE = 60.0;

	static var failed:Int = 0;
	static var ran:Int = 0;

	public static function run(args:Array<String>):Int {
		failed = 0;
		ran = 0;

		Sys.println("  mangle");

		final at = args.indexOf("--rounds");
		final asked = at >= 0 && at + 1 < args.length ? Std.parseInt(args[at + 1]) : ROUNDS;
		final rounds = asked == null ? ROUNDS : asked;

		final sown = args.indexOf("--seed");
		final held = sown >= 0 && sown + 1 < args.length ? Std.parseInt(args[sown + 1]) : 20260906;
		final seed = held == null ? 20260906 : held;

		vgms(rounds, seed);
		xgms(rounds, seed);
		midis(rounds, seed);
		projects(rounds, seed);
		packed(rounds, seed);
		kept();
		waves(rounds, seed);
		patches(rounds, seed);

		Sys.println("    " + (ran - failed) + " of " + ran + " checks");

		if (failed > 0) {
			Sys.println("    failed");
			return 1;
		}

		Sys.println("    passed");
		return 0;
	}

	static function chewed(random:Random, whole:Bytes):Bytes {
		final most = whole.length;
		final want = random.odds(30) ? random.between(1, most) : most;
		final out = Bytes.alloc(want);

		out.blit(0, whole, 0, want < most ? want : most);

		final bites = random.between(1, 24);

		for (bite in 0...bites) {
			final where = random.upTo(want);

			switch (random.upTo(5)) {
				case 0:
					out.set(where, random.upTo(256));

				case 1:
					out.set(where, 0);

				case 2:
					out.set(where, 255);

				case 3:
					final span = random.between(1, 64);

					for (step in 0...span) {
						if (where + step >= want) break;
						out.set(where + step, random.upTo(256));
					}

				case _:
					if (where + 4 <= want) {
						for (step in 0...4) out.set(where + step, random.upTo(256));
					}
			}
		}

		return out;
	}

	static function vgms(rounds:Int, seed:Int):Void {
		final files = Fixtures.corpus();

		if (files.length == 0) {
			says("a mangled vgm never takes the process down", true, "no vgm corpus to read");
			return;
		}

		final whole = sys.io.File.getBytes(files[0]);
		final random = new Random(seed);
		final began = haxe.Timer.stamp();

		var threw = 0;
		var read = 0;

		for (round in 0...rounds) {
			final bytes = chewed(random, whole);

			try {
				final stream = new Stream(1 << 18);
				mdd.format.Vgm.read(bytes, stream);

				read++;
			} catch (e:Dynamic) {
				threw++;
			}

			if (haxe.Timer.stamp() - began > PATIENCE) break;
		}

		final spent = haxe.Timer.stamp() - began;

		says("a mangled vgm never takes the process down", spent < PATIENCE,
			rounds + " corruptions of " + Fixtures.titled(files[0]) + " in "
			+ round(spent, 2) + " s, " + read + " read through and " + threw + " refused");
	}

	static function xgms(rounds:Int, seed:Int):Void {
		final song = new mdd.song.Song("mangle", 96, 120);
		mdd.song.Shipped.into(song);

		final pattern = song.add(new mdd.song.Pattern("one", 384));

		for (step in 0...16) {
			pattern.lane(mdd.song.Part.Fm1).add(new mdd.song.Note(step * 24, 24,
				48 + step, 100));
		}

		song.track(new mdd.song.Track("track"));
		song.tracks[0].add(new mdd.song.Clip(0, 0, 384));

		final span = song.tempo.samplesAt(384);
		final made = new Stream(1 << 16);

		new mdd.play.Sequencer(song, null, mdd.play.Sequencer.CHUNK).spanned(made, 0, span);

		final whole = mdd.format.Xgm.write(song, made, 0, span, song.tempo.rate).written;

		final random = new Random(seed + 5);
		final began = haxe.Timer.stamp();

		var threw = 0;
		var read = 0;

		for (round in 0...rounds) {
			final bytes = chewed(random, whole);

			try {
				final stream = new Stream(1 << 16);
				mdd.format.Xgm.read(bytes, stream);

				read++;
			} catch (e:Dynamic) {
				threw++;
			}

			if (haxe.Timer.stamp() - began > PATIENCE) break;
		}

		final spent = haxe.Timer.stamp() - began;

		says("and a mangled xgm does not either", spent < PATIENCE,
			rounds + " corruptions of a " + whole.length + " byte xgm in " + round(spent, 2)
			+ " s, " + read + " read through and " + threw + " refused");
	}

	static function midis(rounds:Int, seed:Int):Void {
		final song = new mdd.song.Song("mangle", 96, 120);
		final pattern = song.add(new mdd.song.Pattern("one", 384));

		for (step in 0...48) {
			pattern.lane(mdd.song.Part.Fm1).add(new mdd.song.Note(step * 24, 24,
				48 + (step % 24), 100));
		}

		song.track(new mdd.song.Track("track"));
		song.tracks[0].add(new mdd.song.Clip(0, 0, 384));

		final whole = mdd.format.Midi.write(song);
		final random = new Random(seed + 1);
		final began = haxe.Timer.stamp();

		var threw = 0;
		var read = 0;

		for (round in 0...rounds) {
			final bytes = chewed(random, whole);

			try {
				mdd.format.Midi.read(bytes, "mangled");
				read++;
			} catch (e:Dynamic) {
				threw++;
			}

			if (haxe.Timer.stamp() - began > PATIENCE) break;
		}

		final spent = haxe.Timer.stamp() - began;

		says("and a mangled midi does not either", spent < PATIENCE,
			rounds + " corruptions of a " + whole.length + " byte midi in " + round(spent, 2)
			+ " s, " + read + " read through and " + threw + " refused");
	}

	static function projects(rounds:Int, seed:Int):Void {
		final song = new mdd.song.Song("mangle", 96, 120);
		mdd.song.Shipped.into(song);

		final pattern = song.add(new mdd.song.Pattern("one", 384));
		pattern.lane(mdd.song.Part.Fm1).add(new mdd.song.Note(0, 96, 60, 100));

		song.track(new mdd.song.Track("track"));
		song.tracks[0].add(new mdd.song.Clip(0, 0, 384));

		final whole = haxe.io.Bytes.ofString(mdd.format.Project.text(song));
		final random = new Random(seed + 2);
		final began = haxe.Timer.stamp();

		var threw = 0;
		var read = 0;

		for (round in 0...rounds) {
			final bytes = chewed(random, whole);

			try {
				mdd.format.Project.read(bytes.toString());
				read++;
			} catch (e:Dynamic) {
				threw++;
			}

			if (haxe.Timer.stamp() - began > PATIENCE) break;
		}

		final spent = haxe.Timer.stamp() - began;

		says("and a mangled project does not either", spent < PATIENCE,
			rounds + " corruptions of a " + whole.length + " byte project in "
			+ round(spent, 2) + " s, " + read + " read through and " + threw + " refused");
	}

	static function packed(rounds:Int, seed:Int):Void {
		final song = new mdd.song.Song("mangle", 96, 120);
		mdd.song.Shipped.into(song);

		final pattern = song.add(new mdd.song.Pattern("one", 384));
		pattern.lane(mdd.song.Part.Fm1).add(new mdd.song.Note(0, 96, 60, 100));

		song.track(new mdd.song.Track("track"));
		song.tracks[0].add(new mdd.song.Clip(0, 0, 384));

		final sample = song.sample(new mdd.song.Sample("noise", 8000, 60));
		final held = new haxe.ds.Vector<Int>(512);

		for (index in 0...held.length) held[index] = (index * 37) & 255;
		sample.hold(held);

		final where = Gate.root + "/export/mangled" + "." + mdd.Config.SUFFIX;
		mdd.format.Project.savePacked(song, where);

		final whole = sys.io.File.getBytes(where);
		final random = new Random(seed + 6);
		final began = haxe.Timer.stamp();

		final many = rounds < 4 ? rounds : Std.int(rounds / 4);

		var threw = 0;
		var read = 0;

		for (round in 0...many) {
			sys.io.File.saveBytes(where, chewed(random, whole));

			try {
				mdd.format.Project.openPacked(where);
				read++;
			} catch (e:Dynamic) {
				threw++;
			}

			if (haxe.Timer.stamp() - began > PATIENCE) break;
		}

		final spent = haxe.Timer.stamp() - began;

		try {
			if (sys.FileSystem.exists(where)) sys.FileSystem.deleteFile(where);
		} catch (e:Dynamic) {}

		says("and a mangled packed project does not either", spent < PATIENCE,
			many + " corruptions of a " + whole.length + " byte project in "
			+ round(spent, 2) + " s, " + read + " read through and " + threw + " refused");
	}

	static function kept():Void {
		final song = new mdd.song.Song("kept", 96, 120);
		mdd.song.Shipped.into(song);

		final pattern = song.add(new mdd.song.Pattern("one", 384));
		pattern.lane(mdd.song.Part.Fm1).add(new mdd.song.Note(0, 96, 60, 100));

		song.track(new mdd.song.Track("track"));
		song.tracks[0].add(new mdd.song.Clip(0, 0, 384));

		final where = Gate.root + "/export/kept" + "." + mdd.Config.SUFFIX;
		final aside = where + ".part";

		mdd.format.Project.savePacked(song, where);

		final was = sys.io.File.getBytes(where);
		final tidy = !sys.FileSystem.exists(aside);

		sys.FileSystem.createDirectory(aside);

		song.add(new mdd.song.Pattern("two", 384));

		var threw = false;

		try {
			mdd.format.Project.savePacked(song, where);
		} catch (e:Dynamic) {
			threw = true;
		}

		final now = sys.io.File.getBytes(where);
		final same = now.compare(was) == 0;

		try {
			sys.FileSystem.deleteDirectory(aside);
			sys.FileSystem.deleteFile(where);
		} catch (e:Dynamic) {}

		says("a save that fails leaves the old file alone", threw && same && tidy,
			"the write refused and the " + was.length + " bytes already on disk are "
			+ (same ? "byte for byte what they were" : "not what they were")
			+ ", with no partial file left behind by the save that worked");
	}

	static function waves(rounds:Int, seed:Int):Void {
		final frames = 2000;
		final samples = new haxe.ds.Vector<cpp.Float32>(frames);

		for (index in 0...frames) samples[index] = Math.sin(index * 0.05);

		final whole = mdd.format.Wav.write(samples, frames, 1, 16000, 16, false);
		final random = new Random(seed + 3);
		final began = haxe.Timer.stamp();

		var threw = 0;
		var read = 0;

		for (round in 0...rounds) {
			final bytes = chewed(random, whole);

			try {
				mdd.format.Wav.read(bytes);
				read++;
			} catch (e:Dynamic) {
				threw++;
			}

			if (haxe.Timer.stamp() - began > PATIENCE) break;
		}

		final spent = haxe.Timer.stamp() - began;

		says("and a mangled wav does not either", spent < PATIENCE,
			rounds + " corruptions of a " + whole.length + " byte wav in " + round(spent, 2)
			+ " s, " + read + " read through and " + threw + " refused");
	}

	static function patches(rounds:Int, seed:Int):Void {
		final whole = mdd.format.Tfi.write(new mdd.song.Patch());
		final random = new Random(seed + 4);
		final began = haxe.Timer.stamp();

		var threw = 0;
		var read = 0;

		for (round in 0...rounds) {
			final bytes = chewed(random, whole);

			try {
				mdd.format.Tfi.read(bytes);
				read++;
			} catch (e:Dynamic) {
				threw++;
			}

			if (haxe.Timer.stamp() - began > PATIENCE) break;
		}

		final spent = haxe.Timer.stamp() - began;

		says("and a mangled tfi does not either", spent < PATIENCE,
			rounds + " corruptions of a " + whole.length + " byte tfi in " + round(spent, 2)
			+ " s, " + read + " read through and " + threw + " refused");
	}

	static function says(name:String, ok:Bool, said:String):Void {
		ran++;
		if (!ok) failed++;

		Sys.println("    " + StringTools.rpad(name, " ", 44) + said + (ok ? "" : "   FAILED"));
	}

	static function round(value:Float, places:Int):Float {
		final scale = Math.pow(10, places);
		return Math.round(value * scale) / scale;
	}
}
