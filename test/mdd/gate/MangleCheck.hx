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
		shaped();
		crafted();

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

		final sequencer = new mdd.play.Sequencer(song, null, mdd.play.Sequencer.CHUNK);
		final strikes:Array<Int> = [];

		sequencer.strikes = strikes;
		sequencer.spanned(made, 0, span);

		final whole = mdd.format.Xgm.write(song, made, strikes, 0, span, song.tempo.rate).written;

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

	/**
		Reads documents that are not corruptions of a real one.

		Chewing a valid file changes bytes, so it never reaches a document whose shape is
		the attack: one that nests until the stack runs out, or one that declares a length
		it does not carry and is believed. Neither is reachable by mutation and both take
		the process down, so they are written out rather than stumbled on.
	**/
	static function shaped():Void {
		final open = new StringBuf();
		final shut = new StringBuf();

		for (step in 0...200000) {
			open.add("[");
			shut.add("]");
		}

		final deep = open.toString() + shut.toString();
		var read = false;

		try {
			mdd.format.Json.parse(deep);
			read = true;
		} catch (e:Dynamic) {}

		says("a document that nests too deep is refused", read,
			deep.length + " bytes of nothing but brackets, 200000 deep, read without faulting");

		final asked = '{"name":"huge","samples":[{"name":"one","rate":8000,"root":60,'
			+ '"loop":-1,"length":2000000000}]}';

		var held = -1;

		try {
			held = mdd.format.Project.read(asked).samples[0].length();
		} catch (e:Dynamic) {}

		says("a sample cannot declare a huge block", held >= 0 && held <= 1 << 22,
			asked.length + " bytes declaring 2000000000 samples reserved " + held);
	}

	/**
		Files built to hit one number each: a length or an offset near the top of an `Int`, where
		`at + length > file` wraps round to a negative and passes, and a value the model has no room
		for. Random corruption almost never lands on one of those, so each is written out here with
		what the reader must do with it.
	**/
	static function crafted():Void {
		final vgm = Bytes.alloc(0x40 + 8);
		vgm.blit(0, Bytes.ofString("Vgm "), 0, 4);
		vgm.setInt32(0x08, 0x150);
		vgm.setInt32(0x34, 0x0C);
		vgm.set(0x40, 0x67);
		vgm.set(0x41, 0x66);
		vgm.set(0x42, 0x00);
		vgm.setInt32(0x43, 0x7FFFFFF0);
		vgm.set(0x47, 0x66);

		final began = haxe.Timer.stamp();
		var blocked = "";

		try {
			mdd.format.Vgm.read(vgm, new Stream(1 << 10));
		} catch (e:Dynamic) {
			blocked = Std.string(e);
		}

		final took = haxe.Timer.stamp() - began;

		says("a vgm block claiming 2 GB is not read", took < 1 && blocked == "",
			"read in " + round(took * 1000, 1) + " ms" + (blocked == "" ? "" : ", but " + blocked));

		final tagged = Bytes.alloc(0x40 + 1);
		tagged.blit(0, Bytes.ofString("Vgm "), 0, 4);
		tagged.setInt32(0x08, 0x150);
		tagged.setInt32(0x14, 0x7FFFFFE0);
		tagged.setInt32(0x34, 0x0C);
		tagged.set(0x40, 0x66);

		var untagged = "";

		try {
			mdd.format.Vgm.read(tagged, new Stream(1 << 10));
		} catch (e:Dynamic) {
			untagged = Std.string(e);
		}

		says("and a tag offset past the end is passed by", untagged == "",
			untagged == "" ? "read with no tags" : "refused: " + untagged);

		final xgm = Bytes.alloc(0x108 + 4);
		xgm.blit(0, Bytes.ofString("XGM "), 0, 4);
		for (slot in 0...mdd.format.Xgm.SLOTS) xgm.setUInt16(4 + slot * 4, 0xFFFF);
		xgm.set(0x102, 1);
		xgm.setInt32(0x104, 0x7FFFFFF0);
		xgm.set(0x108, 0x00);
		xgm.set(0x109, 0x00);
		xgm.set(0x10A, 0x7F);

		var walked = -1;

		try {
			walked = mdd.format.Xgm.read(xgm, new Stream(1 << 10)).frames;
		} catch (e:Dynamic) {}

		says("an xgm claiming 2 GB reads what is there", walked == 2,
			walked < 0 ? "refused" : walked + " frames read of the 2 there");

		final midi = Bytes.alloc(14);
		midi.blit(0, Bytes.ofString("MThd"), 0, 4);
		midi.set(7, 6);
		midi.set(9, 1);
		midi.set(11, 0);

		final ppqn = mdd.format.Midi.resolution(midi);

		says("a midi counting nought ticks a beat", ppqn == mdd.format.Midi.PPQN,
			"reads as " + ppqn + " ticks a quarter note");

		final zip = Bytes.alloc(22);
		zip.setInt32(0, 0x06054B50);
		zip.setUInt16(8, 1);
		zip.setUInt16(10, 1);
		zip.setInt32(16, 0x7FFFFFF0);

		final where = Gate.root + "/export/crafted." + mdd.Config.SUFFIX;
		sys.io.File.saveBytes(where, zip);

		var refused = "";

		try {
			mdd.format.Project.openPacked(where);
		} catch (e:Dynamic) {
			refused = Std.string(e);
		}

		mdd.host.Paths.clear(where);

		says("a zip directory near 2 GB in is refused", refused.indexOf("damaged zip directory") >= 0,
			refused == "" ? "opened" : refused);

		final chunks = Bytes.alloc(4 + 8);
		chunks.blit(0, Bytes.ofString(mdd.format.Chunks.MARK), 0, 4);
		chunks.blit(4, Bytes.ofString("SMPL"), 0, 4);
		chunks.setInt32(8, 0x7FFFFFF0);

		final found = mdd.format.Chunks.read(chunks);

		says("a chunk claiming 2 GB is not allocated", found.length == 0,
			found.length + " chunks read out of a file of 12 bytes");

		final preset = new haxe.io.BytesBuffer();
		preset.addString(mdd.format.Preset.MAGIC);
		preset.addByte(0);
		preset.addByte(0);
		preset.addByte(0);
		preset.addByte(1);
		preset.addByte(0);
		preset.addByte(200);
		preset.addByte(0);
		preset.addByte(0);
		preset.addByte(0);
		preset.addByte(0);
		preset.addByte(0);
		preset.addByte(0);
		for (field in 0...mdd.song.Patch.DIALS + mdd.song.Patch.SLOTS * (mdd.song.Patch.ROWS + 1)) preset.addByte(0);
		preset.addByte(0);

		final banked = mdd.format.Preset.read(preset.getBytes());

		says("a preset for a part there is not is refused", banked == null,
			banked == null ? "not read" : "read, with a part the song has no room for");

		final number = mdd.format.Json.parse("[1e400, -1e400, 1e400]");
		final most = number.at(0).whole(0);
		final least = number.at(1).whole(0);
		final real = number.at(2).real(7);

		says("a number past any Int is held to one", most == 2147483647 && least == -2147483647 - 1
			&& real == 7, "whole " + most + " and " + least + ", real falls back to " + real);
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
