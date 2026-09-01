package mdd.gate;

import mdd.format.Transcription;
import mdd.format.Vgm;
import mdd.host.Sdl;
import mdd.play.Stream;
import mdd.song.Part;
import mdd.song.Tempo;
import sys.FileSystem;
import sys.io.File;

@:unreflective
class VgmCheck {
	static var failed:Int = 0;
	static var ran:Int = 0;

	public static function run(args:Array<String>):Int {
		failed = 0;
		ran = 0;

		Sys.println("  vgm");

		final where = args.length > 0 && !StringTools.startsWith(args[0], "--")
			? args[0] : Gate.root + "/vendor/vgm";

		if (!FileSystem.exists(where)) {
			Sys.println("    no corpus at " + where);
			Sys.println("    put vgm files there, or name a directory: mdd gate vgm <path>");
			return 1;
		}

		final files = [for (name in FileSystem.readDirectory(where))
			if (StringTools.endsWith(name.toLowerCase(), ".vgm")) name];

		files.sort(function(a:String, b:String):Int return compare(a, b));

		if (files.length == 0) {
			Sys.println("    no vgm files in " + where);
			return 1;
		}

		corpus(where, files);
		sounds(where, files);
		rated(where, files);
		sound(where, files);

		final into = args.indexOf("--wav");
		if (into >= 0 && into + 1 < args.length) written(where, files, args[into + 1]);
		transported(where, files);

		Sys.println("    " + (ran - failed) + " of " + ran + " checks");

		if (failed > 0) {
			Sys.println("    failed");
			return 1;
		}

		Sys.println("    passed");
		return 0;
	}

	static function sounds(where:String, files:Array<String>):Void {
		var loudest = 0.0;
		var raw = 0;
		var played = 0;
		var quiet = 0;
		var clipped = 0;
		var worstJump = 0.0;
		var last = 0.0;
		var heard = 0;

		for (name in files) {
			if (played >= 6) break;

			final stream = new mdd.play.Stream(1 << 22);
			mdd.format.Vgm.read(sys.io.File.getBytes(where + "/" + name), stream);

			final render = new mdd.play.Render(44100, mdd.play.Render.BLOCK);
			final span = 44100 * 4;

			var done = 0;
			var most = 0.0;

			while (done < span) {
				final from = Std.int(done * (mdd.song.Tempo.TICKS / 44100.0));
				final many = render.serve(stream, from, mdd.play.Render.BLOCK, 0);
				if (many <= 0) break;

				for (i in 0...many) {
					final held = render.block[i * 2];
					final value = held < 0 ? -held : held;

					if (value > most) most = value;
					if (value >= 0.999) clipped++;

					final away = held - last;
					final jump = away < 0 ? -away : away;
					if (jump > worstJump) worstJump = jump;

					last = held;
					heard++;
				}

				final peak = render.ym.left < 0 ? -render.ym.left : render.ym.left;
				if (peak > raw) raw = peak;

				done += many;
			}

			played++;
			if (most < 0.05) quiet++;
			if (most > loudest) loudest = most;
		}

		says("an imported vgm sounds", played > 0 && quiet == 0 && clipped == 0,
			played + " files rendered for four seconds, loudest sample " + round(loudest, 4)
			+ " with the chip reaching " + raw + ", " + quiet + " under a twentieth of full"
			+ " scale, " + clipped + " of " + heard + " samples at the ceiling and the worst"
			+ " step between neighbours " + round(worstJump, 4));
	}

	static function transported(where:String, files:Array<String>):Void {
		final wanted = ["Green Hill", "Emerald Hill", "Chemical Plant", "Star Light"];
		final said = new StringBuf();

		var played = 0;
		var quiet = 0;

		for (want in wanted) {
			var name = "";

			for (held in files) if (held.indexOf(want) >= 0) name = held;
			if (name == "") continue;

			final stream = new mdd.play.Stream(1 << 22);
			final vgm = mdd.format.Vgm.read(sys.io.File.getBytes(where + "/" + name),
				stream);

			final made = mdd.format.Transcription.of(stream, vgm.rate, name);
			final transport = new mdd.play.Transport(made.song, 1 << 18);
			final render = new mdd.play.Render(44100, mdd.play.Render.BLOCK);

			render.transport = transport;
			transport.source = stream;
			transport.play();

			var done = 0;
			var most = 0.0;
			var writes = 0;

			while (done < 44100 * 4) {
				final from = transport.advance(mdd.play.Render.BLOCK, 44100);
				final many = render.serve(transport.stream, from, mdd.play.Render.BLOCK,
					transport.entering);

				if (many <= 0) break;

				for (i in 0...many) {
					final value = render.block[i * 2];
					final much = value < 0 ? -value : value;
					if (much > most) most = much;
				}

				writes += transport.stream.count;
				done += many;
			}

			played++;
			if (most < 0.15) quiet++;

			said.add(want + " " + round(most, 3) + " over " + writes + " writes   ");
		}

		says("and playing one back is the file", played > 0 && quiet == 0,
			played + " sonic tracks driven four seconds each the way the device asks for"
			+ " them: " + said.toString());
	}

	static function rated(where:String, files:Array<String>):Void {
		if (files.length == 0) return;

		final at = [44100, 48000];
		final peaks:Array<Float> = [];
		final zeroes:Array<Int> = [];

		for (rate in at) {
			final stream = new mdd.play.Stream(1 << 22);
			mdd.format.Vgm.read(sys.io.File.getBytes(where + "/" + files[0]), stream);

			final render = new mdd.play.Render(rate, mdd.play.Render.BLOCK);
			final span = rate * 4;

			var done = 0;
			var most = 0.0;
			var crossings = 0;
			var last = 0.0;

			while (done < span) {
				final from = Std.int(done * (mdd.song.Tempo.TICKS / rate));
				final many = render.serve(stream, from, mdd.play.Render.BLOCK, 0);
				if (many <= 0) break;

				for (i in 0...many) {
					final value = render.block[i * 2];
					final much = value < 0 ? -value : value;

					if (much > most) most = much;
					if (last <= 0 && value > 0) crossings++;
					last = value;
				}

				done += many;
			}

			peaks.push(most);
			zeroes.push(crossings);
		}

		var worst = 0.0;

		for (index in 1...zeroes.length) {
			final away = zeroes[index] - zeroes[0];
			final much = (away < 0 ? -away : away) / zeroes[0];
			if (much > worst) worst = much;
		}

		says("and the same at either device rate", worst < 0.02,
			"four seconds at 44100 and 48000 cross zero " + zeroes[0] + " and " + zeroes[1]
			+ " times, " + round(worst * 100, 2) + " per cent apart, peaking at "
			+ round(peaks[0], 3) + " and " + round(peaks[1], 3));
	}

	static function written(where:String, files:Array<String>, into:String):Void {
		var name = "";

		for (held in files) if (held.indexOf("Green Hill") >= 0) name = held;
		if (name == "" && files.length > 0) name = files[0];
		if (name == "") return;

		final stream = new mdd.play.Stream(1 << 22);
		mdd.format.Vgm.read(sys.io.File.getBytes(where + "/" + name), stream);

		final render = new mdd.play.Render(44100, mdd.play.Render.BLOCK);
		final seconds = 12;
		final frames = 44100 * seconds;
		final sound = new haxe.ds.Vector<cpp.Float32>(frames * 2);

		var done = 0;

		while (done < frames) {
			final from = Std.int(done * (mdd.song.Tempo.TICKS / 44100.0));
			final many = render.serve(stream, from, mdd.play.Render.BLOCK, 0);
			if (many <= 0) break;

			for (i in 0...many) {
				if ((done + i) * 2 + 1 >= sound.length) break;
				sound[(done + i) * 2] = render.block[i * 2];
				sound[(done + i) * 2 + 1] = render.block[i * 2 + 1];
			}

			done += many;
		}

		sys.io.File.saveBytes(into, mdd.format.Wav.write(sound, frames, 2, 44100));
		Sys.println("    wrote " + seconds + " s of " + name + " to " + into);
	}

	static function sound(where:String, files:Array<String>):Void {
		final budget = new mdd.check.Budget(mdd.check.Profile.megaDrive());
		final said = new StringBuf();

		var read = 0;
		var troubled = 0;
		var worst = "";
		var most = 0;

		for (name in files) {
			if (read >= 20) break;

			final stream = new mdd.play.Stream(1 << 22);
			final vgm = mdd.format.Vgm.read(sys.io.File.getBytes(where + "/" + name),
				stream);

			final made = mdd.format.Transcription.of(stream, vgm.rate, name);

			budget.overSong(made.song);

			read++;
			if (budget.found.length == 0) continue;

			troubled++;

			said.add(name + " " + budget.found.length + "   ");

			if (budget.found.length > most) {
				most = budget.found.length;
				worst = name;
			}
		}

		says("a game vgm reads back as playable", troubled == 0,
			read + " files transcribed, " + troubled + " of them raising a warning"
			+ (most == 0 ? "" : ": " + said.toString()));
	}

	static function compare(a:String, b:String):Int {
		return a < b ? -1 : (a > b ? 1 : 0);
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

	static function table():Float {
		var worst = 0.0;

		for (note in 24...108) {
			final block = mdd.play.Stream.blockOf(note);
			final number = mdd.play.Stream.frequencyOf(note);

			final hertz = number * (mdd.chip.Ym2612.CLOCK / mdd.chip.Ym2612.PER_SAMPLE)
				/ 1048576.0 * Math.pow(2, block - 1);

			final want = 440.0 * Math.pow(2, (note - 69) / 12.0);
			final cents = Math.abs(1200 * Math.log(hertz / want) / Math.log(2));

			if (cents > worst) worst = cents;
		}

		return worst;
	}

	static function corpus(where:String, files:Array<String>):Void {
		var read = 0;
		var writes = 0;
		var tagged = 0;
		var looped = 0;
		var sampled = 0;
		var sampleBytes = 0;
		var seconds = 0.0;
		var unknown = 0;
		var overflowed = 0;

		var same = 0;
		var parted = "";
		var loopsHold = true;

		var written = 0;
		var patches = 0;
		var worstCents = 0.0;
		var offGrid = 0;
		var onGrid = 0;
		var sounded = 0;
		var scored = 0;
		var laneless = 0;

		final began = Sdl.ticks();

		for (name in files) {
			final stream = new Stream(4194304);
			final bytes = File.getBytes(where + "/" + name);

			var vgm:Null<Vgm> = null;

			try {
				vgm = Vgm.read(bytes, stream);
			} catch (e:Dynamic) {
				says("read " + name, false, "" + e);
				continue;
			}

			read++;
			writes += stream.count;
			if (stream.dropped > 0) overflowed++;

			if (vgm.game != "" || vgm.title != "") tagged++;

			if (vgm.loopAt >= 0) {
				looped++;
				if (vgm.loopWrite < 0 || vgm.loopWrite > stream.count) loopsHold = false;
			}
			if (vgm.blocks > 0) {
				sampled++;
				sampleBytes += vgm.blockBytes;
			}

			unknown += vgm.unknown;
			seconds += vgm.samples / Vgm.TICKS;

			final until = stream.count == 0 ? 0 : stream.tickAt(stream.count - 1) + 1;
			final again = new Stream(4194304);
			final back = Vgm.write(stream, 0, until, vgm.rate);

			Vgm.read(back, again);

			final off = alike(stream, again);

			if (off == -2) same++;
			else if (parted == "") {
				parted = name + (off == -1 ? " has " + again.count + " writes against "
					+ stream.count : " parts at write " + off);
			}

			final made = Transcription.of(stream, vgm.rate, name);

			written += made.notes;
			patches += made.song.instruments.length;
			offGrid += made.offGrid;
			onGrid += made.onGrid;
			sounded += made.sounded;
			if (made.worstCents > worstCents) worstCents = made.worstCents;
			if (made.notes > 0) scored++;

			var lanes = 0;
			for (index in 0...Part.COUNT) {
				if (made.song.patterns[0].lanes[index].notes.length > 0) lanes++;
			}

			if (lanes < 2) laneless++;
		}

		final spent = Sdl.ticks() - began;

		says("every file reads", read == files.length && overflowed == 0,
			read + " of " + files.length + " vgm files read, " + writes
			+ " register writes across " + round(seconds, 1) + " s of music");

		says("the tags are there", tagged == read,
			tagged + " of " + read + " carry a gd3 tag");

		says("a loop lands in the file", loopsHold,
			looped + " of " + read + " name a loop point, and every one of them falls on a write");

		says("the samples are there", sampled > 0,
			sampled + " carry pcm data blocks, " + sampleBytes + " bytes between them");

		says("nothing was skipped", unknown == 0,
			unknown + " commands this build does not know");

		says("what is read is written", same == read,
			parted == "" ? same + " of " + read + " re-export to the same register stream"
				: parted);

		says("every file becomes notes", scored == read && laneless == 0,
			written + " notes read out of the register writes, across " + patches
			+ " patches, every file on at least two parts");

		says("a note plays at its pitch", table() < 1,
			"every note this build writes an F number for comes back within "
			+ round(table(), 3) + " cents of the note it names");

		final exact = sounded == 0 ? 0.0 : 100.0 * onGrid / sounded;
		final near = sounded == 0 ? 0.0 : 100.0 - 100.0 * offGrid / sounded;

		says("a key on names a note", near > 99,
			round(near, 2) + " per cent of " + sounded
			+ " key ons land within a quarter tone of a semitone, " + round(exact, 1)
			+ " within a cent; the game's own F number table is rounded, and the "
			+ round(100 - near, 2) + " per cent left are bends, worst " + round(worstCents, 0));

		says("it reads faster than it plays", spent < seconds,
			round(seconds, 1) + " s of music read and written back in " + round(spent, 2)
			+ " s, " + round(seconds / spent, 0) + " times faster than real time");
	}
}
