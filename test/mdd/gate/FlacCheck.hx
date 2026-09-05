package mdd.gate;

import haxe.ds.Vector;
import mdd.format.Flac;
import mdd.format.Wav;

@:unreflective
class FlacCheck {
	static var ran = 0;
	static var failed = 0;

	public static function run(args:Array<String>):Int {
		var from = "";
		var into = "";
		var depth = 16;

		var at = 0;

		while (at < args.length) {
			final one = args[at];
			final held = at + 1 < args.length ? args[at + 1] : "";

			switch (one) {
				case "--wav": from = held; at++;
				case "--out": into = held; at++;
				case "--depth": depth = held == "24" ? 24 : 16; at++;
				default:
			}

			at++;
		}

		if (from != "" && into != "") return coded(from, into, depth);

		ran = 0;
		failed = 0;

		Sys.println("  flac");

		scaled();
		signed();

		Sys.println("    " + (ran - failed) + " of " + ran + " checks");
		Sys.println(failed == 0 ? "    passed" : "    failed");

		return failed == 0 ? 0 : 1;
	}

	static function says(name:String, ok:Bool, said:String):Void {
		ran++;
		if (!ok) failed++;

		Sys.println("    " + StringTools.rpad(name, " ", 40) + said + (ok ? "" : "   FAILED"));
	}

	static function scaled():Void {
		final many = 65536;

		var apart = 0;
		var worst = 0;

		for (index in 0...many) {
			final held = index - 32768;
			final back = Wav.whole(Wav.floated(held, 16), 16);

			final gap = back - held;
			if (gap != 0) apart++;

			if ((gap < 0 ? -gap : gap) > worst) worst = gap < 0 ? -gap : gap;
		}

		final ends = [-8388608, -8388607, -1, 0, 1, 8388606, 8388607];
		var deep = 0;

		for (held in ends) if (Wav.whole(Wav.floated(held, 24), 24) != held) deep++;

		says("every sample survives the trip through a float", apart == 0 && worst == 0
			&& deep == 0,
			"all " + many + " sixteen bit values came back, and " + (ends.length - deep)
			+ " of " + ends.length + " at the edges of twenty four");
	}

	static function signed():Void {
		final frames = 4096;
		final held = new Vector<cpp.Float32>(frames * 2);

		var seed = 0x1F35;

		for (index in 0...frames) {
			seed = (seed * 1103515245 + 12345) & 0x3FFFFFFF;

			held[index * 2] = Math.sin(index * 0.031);
			held[index * 2 + 1] = ((seed >> 11) % 2001 - 1000) / 1000.0;
		}

		final made = Flac.write(held, frames, 2, 44100, 16, []);

		final raw = haxe.io.Bytes.alloc(frames * 2 * 2);

		for (index in 0...frames * 2) {
			final value = Wav.whole(held[index], 16);

			raw.set(index * 2, value & 0xFF);
			raw.set(index * 2 + 1, (value >> 8) & 0xFF);
		}

		final want = haxe.crypto.Md5.make(raw);

		var same = true;
		var blank = true;

		for (index in 0...16) {
			final one = made.get(Flac.SIGNED + index);

			if (one != want.get(index)) same = false;
			if (one != 0) blank = false;
		}

		says("a flac carries the signature of its audio", same && !blank,
			"the sixteen bytes at " + Flac.SIGNED + " are the md5 of the samples that went in");
	}

	static function coded(from:String, into:String, depth:Int):Int {
		final wav = Wav.read(sys.io.File.getBytes(from));

		final many = wav.frames * wav.channels;
		final held = new Vector<cpp.Float32>(many);

		for (index in 0...many) held[index] = wav.samples[index];

		final began = haxe.Timer.stamp();
		final made = Flac.write(held, wav.frames, wav.channels, wav.rate, depth, []);
		final took = haxe.Timer.stamp() - began;

		sys.io.File.saveBytes(into, made);

		final raw = wav.frames * wav.channels * (depth >> 3);

		Sys.println("  flac          " + made.length + " bytes of " + raw + ", "
			+ Math.round(made.length * 1000.0 / raw) / 10 + " per cent, in "
			+ Math.round(took * 1000) + " ms");

		return 0;
	}
}
