package mdd.gate;

class Gate {
	static final PROGRAMS:Array<String> = ["window", "paint", "lang", "ui", "psg", "chip", "audio", "stream", "spine", "automation", "fuzz", "check", "vgm", "xgm", "mix", "arrange", "tier"];

	public static var root(default, null):String = ".";

	public static function main():Void {
		final args = Sys.args();

		final flag = args.indexOf("--root");
		if (flag >= 0 && flag + 1 < args.length) {
			root = args[flag + 1];
			args.splice(flag, 2);
		}

		mdd.host.Native.ready();
		mdd.host.Crash.watch(root + "/export/fault.txt", "The gate", false);

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
			case "lang": LangCheck.run(args);
			case "ui": UiCheck.run(args);
			case "psg": PsgCheck.run(args);
			case "chip": ChipCheck.run(args);
			case "audio": AudioCheck.run(args);
			case "stream": StreamCheck.run(args);
			case "automation": AutomationCheck.run(args);
			case "spine": SpineCheck.run(args);
			case "fuzz": FuzzCheck.run(args);
			case "check": CheckCheck.run(args);
			case "vgm": VgmCheck.run(args);
			case "xgm": XgmCheck.run(args);
			case "mix": MixCheck.run(args);
			case "arrange": ArrangeCheck.run(args);
			case "tier": TierCheck.run(args);
			case "shot": ShotCheck.run(args);
			case "fault": FaultCheck.run(args);
			case "lift": LiftCheck.run(args);
			case "drift": DriftCheck.run(args);
			case _:
				Sys.println("mdd gate: no program called '" + name + "'");
				Sys.println("  known: " + PROGRAMS.join(", "));
				1;
		}
	}
}
