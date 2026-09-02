package mdd.gate;

import haxe.ds.Vector;
import mdd.host.Crash;
import mdd.song.Song;

@:unreflective
class FaultCheck {
	public static function run(args:Array<String>):Int {
		final kind = args.length > 0 && !StringTools.startsWith(args[0], "-") ? args[0] : "read";
		final where = Gate.root + "/export/fault.txt";

		if (args.indexOf("--tell") >= 0) Crash.watch(where, "The gate", true);

		Sys.println("  fault");
		Sys.println("    stopping on purpose: " + kind);
		Sys.println("    the report goes to " + where);

		switch (kind) {
			case "read": read(args);
			case "write": write(args);
			case "overflow": Sys.println("    " + deeper(args.length));
			case "thread": elsewhere(args);
			case _:
				Sys.println("    no fault called '" + kind + "'");
				Sys.println("    known: read, write, overflow, thread");
				return 1;
		}

		Sys.println("    it did not stop, which is itself a failure");
		return 1;
	}

	static function read(args:Array<String>):Void {
		final held = never(args);
		Sys.println("    " + held.name);
	}

	static function write(args:Array<String>):Void {
		final room = new Vector<Int>(4);
		room[far(args)] = 1;
		Sys.println("    " + room[0]);
	}

	static function elsewhere(args:Array<String>):Void {
		sys.thread.Thread.create(function():Void {
			Crash.thread("a thread the gate made");
			read(args);
		});

		while (true) Sys.sleep(0.05);
	}

	static function deeper(depth:Int):Int {
		return depth + deeper(depth + 1);
	}

	static function never(args:Array<String>):Null<Song> {
		return args.length > 4096 ? new Song() : null;
	}

	static function far(args:Array<String>):Int {
		return 1 << 28 | args.length;
	}
}
