package mdd.gate;

import mdd.format.Transcription;
import mdd.format.Vgm;
import mdd.play.Stream;
import mdd.song.Part;
import sys.io.File;

/**
	What the converter ends up carrying after a file is read.

	A driver plays a handful of recordings over and over, so an import that comes
	back with scores of them has cut one drum into many rather than recognising it
	twice. This prints what was cut and how often each is played, which is what says
	whether the cutting or the matching is the part that is wrong.
**/
@:unreflective
class Hits {
	/**
		@param args The file to read.
		@return Nonzero where it would not read.
	**/
	public static function run(args:Array<String>):Int {
		if (args.length == 0) {
			Sys.println("  hits          give it a vgm file to read");
			return 1;
		}

		final name = args[0];

		if (!sys.FileSystem.exists(name)) {
			Sys.println("  hits          no file at " + name);
			return 1;
		}

		final source = new Stream(1 << 22);
		final vgm = Vgm.read(File.getBytes(name), source);

		if (vgm == null) {
			Sys.println("  hits          " + name + " is not a vgm");
			return 1;
		}

		final song = Transcription.of(source, vgm.rate, name).song;

		Sys.println("  hits");
		Sys.println("    " + name);
		Sys.println("    " + song.samples.length + " recordings, "
			+ song.instruments.length + " instruments");

		final played:Array<Int> = [for (index in 0...song.samples.length) 0];
		var notes = 0;

		for (pattern in song.patterns) {
			for (note in pattern.lane(Part.Dac).notes) {
				notes++;

				final instrument = song.instrumentAt(note.instrument);
				if (instrument == null) continue;

				final at = instrument.sample;
				if (at >= 0 && at < played.length) played[at]++;
			}
		}

		Sys.println("    " + notes + " notes on the converter");
		Sys.println("");
		Sys.println("    " + pad("recording", 12) + pad("bytes", 8) + pad("rate", 8)
			+ pad("key", 6) + "played");

		var bytes = 0;

		for (index in 0...song.samples.length) {
			final sample = song.samples[index];
			bytes += sample.length();

			if (index < 40) {
				Sys.println("    " + pad("" + index, 12) + pad("" + sample.length(), 8)
					+ pad("" + sample.rate, 8) + pad("" + sample.root, 6)
					+ played[index]);
			}
		}

		if (song.samples.length > 40) {
			Sys.println("    " + (song.samples.length - 40) + " more not listed");
		}

		Sys.println("");
		Sys.println("    " + bytes + " bytes in all");
		Sys.println("    " + spread(song));
		Sys.println("    nearest neighbour by print: " + nearest(song).join(" "));

		return 0;
	}

	/**
		@param song The piece the file became.
		@return How the lengths group, which is what says whether one drum was cut
			many times over.
	**/
	static function spread(song:mdd.song.Song):String {
		final seen:Array<Int> = [];
		final many:Array<Int> = [];

		for (sample in song.samples) {
			final round = Math.round(sample.length() / 64) * 64;
			final at = seen.indexOf(round);

			if (at < 0) {
				seen.push(round);
				many.push(1);
			} else {
				many[at]++;
			}
		}

		final out:Array<String> = [];

		for (index in 0...seen.length) {
			if (index >= 12) break;
			out.push(seen[index] + " x" + many[index]);
		}

		return "lengths to the nearest 64 bytes: " + out.join(", ")
			+ (seen.length > 12 ? ", and " + (seen.length - 12) + " more" : "");
	}

	/**
		How far each recording is from its nearest neighbour.

		A threshold is only worth what the numbers say. Where one drum has been cut
		twice the two sit very close together, and where two drums are genuinely
		different they sit far apart, so the gap between those two groups is where the
		line belongs.

		@param song The piece the file became.
		@return The distances, smallest first.
	**/
	static function nearest(song:mdd.song.Song):Array<Float> {
		final prints:Array<haxe.ds.Vector<Float>> = [];

		for (sample in song.samples) {
			final bytes:Array<Int> = [];
			for (at in 0...sample.length()) bytes.push(sample.bytes[at]);

			final print = new haxe.ds.Vector<Float>(Transcription.PRINT);
			Transcription.printed(bytes, 0, bytes.length, print);
			prints.push(print);
		}

		final out:Array<Float> = [];

		for (one in 0...prints.length) {
			var best = 9.0;

			for (two in 0...prints.length) {
				if (one == two) continue;

				final away = Transcription.apartPrints(prints[one], prints[two]);
				if (away < best) best = away;
			}

			if (best < 9.0) out.push(Math.round(best * 1000) / 1000);
		}

		out.sort(function(a:Float, b:Float):Int return a < b ? -1 : (a > b ? 1 : 0));
		return out;
	}

	static function pad(said:String, wide:Int):String {
		return StringTools.rpad(said, " ", wide);
	}
}
