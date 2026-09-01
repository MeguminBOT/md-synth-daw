package mdd.gate;

class Gate {
	static final PROGRAMS:Array<String> = ["window", "paint", "ui", "psg", "chip", "audio", "stream"];

	public static var root(default, null):String = ".";

	public static function main():Void {
		final args = Sys.args();

		final flag = args.indexOf("--root");
		if (flag >= 0 && flag + 1 < args.length) {
			root = args[flag + 1];
			args.splice(flag, 2);
		}

		if (args.length > 0 && (args[0] == "--list" || args[0] == "-l")) {
			for (name in PROGRAMS) Sys.println(name);
			return;
		}

		if (args.length == 0) {
			Sys.exit(all());
			return;
		}

		Sys.exit(one(args[0], args.slice(1)));
	}

	static function all():Int {
		var failed = 0;

		Sys.println("");
		for (name in PROGRAMS) {
			final code = one(name, []);
			if (code != 0) failed++;
			Sys.println("");
		}

		Sys.println(failed == 0 ? "  gate passed" : "  gate failed, " + failed + " of "
			+ PROGRAMS.length);
		Sys.println("");
		return failed == 0 ? 0 : 1;
	}

	static function one(name:String, args:Array<String>):Int {
		return switch (name) {
			case "window": WindowCheck.run(args);
			case "paint": PaintCheck.run(args);
			case "ui": UiCheck.run(args);
			case "psg": PsgCheck.run(args);
			case "chip": ChipCheck.run(args);
			case "audio": AudioCheck.run(args);
			case "stream": StreamCheck.run(args);
			case _:
				Sys.println("mdd gate: no program called '" + name + "'");
				Sys.println("  known: " + PROGRAMS.join(", "));
				1;
		}
	}
}
