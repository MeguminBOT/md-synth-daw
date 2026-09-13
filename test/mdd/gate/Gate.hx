package mdd.gate;

class Gate {
	static final PROGRAMS:Array<String> = ["window", "paint", "lang", "ui", "psg", "chip", "audio", "stream", "spine", "automation", "fuzz", "check", "vgm", "xgm", "mix", "arrange", "tier", "midi", "console", "flac", "json", "type", "busy", "stems", "mangle", "presence", "shell", "update", "carry", "keys"];

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

	public static inline final SKIPPED = 2;

	static function all():Int {
		var failed = 0;
		final held:Array<String> = [];
		final grown:Array<Float> = [];

		final began = mdd.host.Usage.ram();
		var before = began;

		Sys.println("");
		for (name in PROGRAMS) {
			final code = one(name, []);

			if (code == SKIPPED) held.push(name);
			else if (code != 0) failed++;

			cpp.vm.Gc.run(true);
			cpp.vm.Gc.compact();

			final after = mdd.host.Usage.ram();

			grown.push(after - before);
			before = after;

			Sys.println("");
		}

		final rest = held.length == 0 ? "" : ", " + held.join(" and ") + " not run";

		Sys.println(failed == 0 ? "  gate passed" + rest
			: "  gate failed, " + failed + " of " + PROGRAMS.length + rest);

		final most = heaviest(grown, 3);

		Sys.println("  " + Math.round(before) + " MB held at the end against "
			+ Math.round(began) + " before the first program"
			+ (most == "" ? "" : ", grown most by " + most));

		Sys.println("");
		return failed == 0 ? 0 : 1;
	}

	/**
		Which programs left the most memory behind them. Every program runs in this one
		process, so what one does not give back is carried by every program after it,
		and the reading is what the process holds rather than what the program asked
		for.

		A collection is forced and the heap compacted before each reading, so what is
		counted is what a program still holds rather than how far the heap grew to
		serve it.

		@param grown How much each program in `PROGRAMS` grew the process by, in
			megabytes, in the same order.
		@param many How many to name.
		@return Them, largest first, or an empty string where none grew it at all.
	**/
	static function heaviest(grown:Array<Float>, many:Int):String {
		final out:Array<String> = [];
		final taken:Array<Bool> = [for (much in grown) false];

		for (round in 0...many) {
			var at = -1;

			for (index in 0...grown.length) {
				if (taken[index] || grown[index] < 1) continue;
				if (at < 0 || grown[index] > grown[at]) at = index;
			}

			if (at < 0) break;

			taken[at] = true;
			out.push(PROGRAMS[at] + " " + Math.round(grown[at]) + " MB");
		}

		return out.join(", ");
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
			case "midi": MidiCheck.run(args);
			case "mangle": MangleCheck.run(args);
			case "presence": PresenceCheck.run(args);
			case "shell": ShellCheck.run(args);
			case "update": UpdateCheck.run(args);
			case "carry": CarryCheck.run(args);
			case "keys": KitCheck.run(args);
			case "shot": ShotCheck.run(args);
			case "swap": SwapCheck.run(args);
			case "hits": Hits.run(args);
			case "fault": FaultCheck.run(args);
			case "gather": Gathered.run(args);
			case "kit": Kitted.run(args);
			case "convert": Converted.run(args);
			case "lift": LiftCheck.run(args);
			case "drift": DriftCheck.run(args);
			case "console": ConsoleCheck.run(args);
			case "flac": FlacCheck.run(args);
			case "json": JsonCheck.run(args);
			case "type": TypeCheck.run(args);
			case "busy": BusyCheck.run(args);
			case "stems": StemsCheck.run(args);
			case "pulse": PulseCheck.run(args);
			case _:
				Sys.println("mdd gate: no program called '" + name + "'");
				Sys.println("  known: " + PROGRAMS.join(", "));
				1;
		}
	}
}
