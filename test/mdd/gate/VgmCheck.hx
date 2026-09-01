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

		final where = args.length > 0 ? args[0] : Gate.root + "/vendor/vgm";

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

		Sys.println("    " + (ran - failed) + " of " + ran + " checks");

		if (failed > 0) {
			Sys.println("    failed");
			return 1;
		}

		Sys.println("    passed");
		return 0;
	}

	static function compare(a:String, b:String):Int {
		return a < b ? -1 : (a > b ? 1 : 0);
	}

	static function says(name:String, ok:Bool, said:String):Void {
		ran++;
		if (!ok) failed++;
		Sys.println("    " + StringTools.rpad(name, " ", 30) + said + (ok ? "" : "   FAILED"));
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
