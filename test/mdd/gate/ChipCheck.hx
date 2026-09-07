package mdd.gate;

import haxe.io.Bytes;
import mdd.chip.Ym2612;
import sys.FileSystem;
import sys.io.File;

typedef Step = {
	final wait:Int;
	final port:Int;
	final value:Int;
}

typedef Outcome = {
	final name:String;
	final exact:Bool;
	final lag:Int;
	final mine:Array<Int>;
	final reference:Array<Int>;
	final line:String;
}

class ChipCheck {
	static inline final LAG = 32;
	static inline final SETTLE = 200;
	static inline final SAMPLES = 4000;

	public static function run(args:Array<String>):Int {
		Sys.println("  chip");

		final root = Gate.root;
		final program = reference(root);

		if (program == "") {
			Sys.println("    not run: there is no reference to measure against");
			Sys.println("    fetch it with: mdd setup --nuked");
			return Gate.SKIPPED;
		}

		final scripts = root + "/export/fixtures/scripts";
		final sounds = root + "/export/fixtures/sounds";

		final began = haxe.Timer.stamp();
		final made = Fixtures.run(scripts);
		if (!FileSystem.exists(sounds)) FileSystem.createDirectory(sounds);

		final rendered = render(program, scripts, sounds);
		final ready = haxe.Timer.stamp();

		Sys.println("    " + StringTools.rpad("fixtures", " ", 20) + made + " scripts, "
			+ rendered + " rendered again, " + seconds(ready - began) + " s");

		final only = args.length > 0 ? args[0] : "";
		final code = only == "" ? whole(scripts, sounds) : single(scripts, sounds, only);

		return code;
	}

	static function suffix():String {
		return Sys.systemName() == "Windows" ? ".exe" : "";
	}

	static function reference(root:String):String {
		final path = root + "/export/bin/opn2" + suffix();
		return FileSystem.exists(path) ? path : "";
	}

	static function render(program:String, scripts:String, sounds:String):Int {
		final plain:Array<String> = [];
		final ladder:Array<String> = [];

		for (file in FileSystem.readDirectory(scripts)) {
			if (!StringTools.endsWith(file, ".txt")) continue;

			final name = file.substr(0, file.length - 4);
			final script = scripts + "/" + file;
			final sound = sounds + "/" + name + ".pcm";

			if (FileSystem.exists(sound)
				&& FileSystem.stat(sound).mtime.getTime() >= FileSystem.stat(script).mtime.getTime()) {
				continue;
			}

			final job = script + " " + sound;
			if (StringTools.startsWith(name, "discrete-")) ladder.push(job);
			else plain.push(job);
		}

		if (plain.length == 0 && ladder.length == 0) return 0;

		final into = haxe.io.Path.directory(scripts);

		if (plain.length > 0) {
			final jobs = into + "/jobs.txt";
			File.saveContent(jobs, plain.join("\n") + "\n");
			Sys.command(program, [Std.string(SAMPLES), jobs]);
		}

		if (ladder.length > 0) {
			final jobs = into + "/jobs-ladder.txt";
			File.saveContent(jobs, ladder.join("\n") + "\n");
			Sys.command(program, [Std.string(SAMPLES), jobs, "ladder"]);
		}

		return plain.length + ladder.length;
	}

	static function whole(scripts:String, sounds:String):Int {
		final groups:Map<String, Array<Outcome>> = new Map();
		final order:Array<String> = [];

		for (file in FileSystem.readDirectory(scripts)) {
			if (!StringTools.endsWith(file, ".txt")) continue;

			final name = file.substr(0, file.length - 4);
			final sound = sounds + "/" + name + ".pcm";
			if (!FileSystem.exists(sound)) continue;

			final at = name.indexOf("-");
			final group = at < 0 ? name : name.substr(0, at);

			if (!groups.exists(group)) {
				groups.set(group, []);
				order.push(group);
			}

			groups.get(group).push(measure(name, scripts + "/" + file, sound));
		}

		order.sort(compare);

		var exact = 0;
		var total = 0;

		for (group in order) {
			final outcomes = groups.get(group);
			var kept = 0;
			for (outcome in outcomes) if (outcome.exact) kept++;

			exact += kept;
			total += outcomes.length;

			Sys.println("    " + StringTools.rpad(group, " ", 20)
				+ StringTools.lpad(Std.string(kept), " ", 4) + " of "
				+ StringTools.lpad(Std.string(outcomes.length), " ", 4) + " bit identical"
				+ (kept == outcomes.length ? "" : "   FAILED"));

			var shown = 0;
			for (outcome in outcomes) {
				if (outcome.exact || shown >= 3) continue;
				Sys.println("      " + outcome.line);
				shown++;
			}
		}

		Sys.println("    " + exact + " of " + total + " fixtures bit identical");

		if (total == 0) {
			Sys.println("    nothing was compared");
			return 1;
		}

		if (exact < total) {
			Sys.println("    failed");
			return 1;
		}

		Sys.println("    passed");
		return 0;
	}

	static function compare(a:String, b:String):Int {
		return a < b ? -1 : (a > b ? 1 : 0);
	}

	static function single(scripts:String, sounds:String, name:String):Int {
		final script = scripts + "/" + name + ".txt";
		final sound = sounds + "/" + name + ".pcm";

		if (!FileSystem.exists(script) || !FileSystem.exists(sound)) {
			Sys.println("    no fixture called '" + name + "'");
			return 1;
		}

		final outcome = measure(name, script, sound);
		Sys.println("    " + outcome.line);

		if (outcome.exact) {
			Sys.println("    passed");
			return 0;
		}

		final mine = outcome.mine;
		final theirs = outcome.reference;
		final until = (mine.length < theirs.length ? mine.length : theirs.length) - outcome.lag;

		Sys.println("      sample      mine     reference");
		var shown = 0;

		for (i in SETTLE...until) {
			if (mine[i] == theirs[i + outcome.lag]) continue;

			Sys.println("      " + StringTools.lpad(Std.string(i), " ", 6)
				+ StringTools.lpad(Std.string(mine[i]), " ", 10)
				+ StringTools.lpad(Std.string(theirs[i + outcome.lag]), " ", 14));

			if (++shown >= 16) break;
		}

		Sys.println("    failed");
		return 1;
	}

	static function measure(name:String, script:String, reference:String):Outcome {
		final steps = parse(File.getContent(script));
		final theirs = samplesOf(File.getBytes(reference));
		final mine = played(steps, theirs.length, StringTools.startsWith(name, "discrete-"));

		final count = mine.length < theirs.length ? mine.length : theirs.length;

		if (count <= SETTLE) {
			return {
				name: name, exact: false, lag: 0, mine: mine, reference: theirs,
				line: StringTools.rpad(name, " ", 22) + "nothing to compare"
			};
		}

		var best = exactness(mine, theirs, 0);
		var lag = 0;

		if (best < 1) {
			for (at in 1...LAG + 1) {
				final share = exactness(mine, theirs, at);
				if (share > best) {
					best = share;
					lag = at;
				}
			}
		}

		var worst = 0;
		final until = count - lag;

		for (i in SETTLE...until) {
			final off = mine[i] - theirs[i + lag];
			final size = off < 0 ? -off : off;
			if (size > worst) worst = size;
		}

		var line = StringTools.rpad(name, " ", 22)
			+ "exact " + StringTools.lpad(round(best * 100), " ", 8) + "%"
			+ "   worst " + StringTools.lpad(Std.string(worst), " ", 4)
			+ "   lag " + StringTools.lpad(Std.string(lag), " ", 3);

		if (silent(mine)) line += "   THIS MADE NO SOUND";

		return {
			name: name, exact: best >= 1 && lag == 0, lag: lag,
			mine: mine, reference: theirs, line: line
		};
	}

	static function parse(text:String):Array<Step> {
		final out:Array<Step> = [];

		for (line in text.split("\n")) {
			final bits = StringTools.trim(line).split(" ");
			if (bits.length < 3) continue;

			out.push({
				wait: Std.parseInt(bits[0]),
				port: Std.parseInt(bits[1]),
				value: Std.parseInt(bits[2])
			});
		}

		return out;
	}

	static function samplesOf(bytes:Bytes):Array<Int> {
		final out:Array<Int> = [];

		var at = 0;
		while (at + 3 < bytes.length) {
			final value = bytes.getUInt16(at);
			out.push(value >= 0x8000 ? value - 0x10000 : value);
			at += 4;
		}

		return out;
	}

	static function played(steps:Array<Step>, count:Int, discrete:Bool):Array<Int> {
		final chip = new Ym2612();
		chip.discrete = discrete;

		final out:Array<Int> = [];

		for (step in steps) {
			for (i in 0...step.wait) {
				if (out.length >= count) break;
				chip.sample();
				out.push(chip.left);
			}
			chip.write(step.port, step.value);
		}

		while (out.length < count) {
			chip.sample();
			out.push(chip.left);
		}

		return out;
	}

	static function exactness(mine:Array<Int>, reference:Array<Int>, lag:Int):Float {
		final until = (mine.length < reference.length ? mine.length : reference.length) - lag;
		if (until - SETTLE < 16) return -1;

		var same = 0;
		for (i in SETTLE...until) if (mine[i] == reference[i + lag]) same++;
		return same / (until - SETTLE);
	}

	static function silent(samples:Array<Int>):Bool {
		for (sample in samples) if (sample != 0) return false;
		return true;
	}

	static function round(value:Float):String {
		return Std.string(Math.round(value * 1000) / 1000);
	}

	static function seconds(value:Float):String {
		return Std.string(Math.round(value * 10) / 10);
	}
}
