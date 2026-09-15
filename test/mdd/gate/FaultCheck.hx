package mdd.gate;

import haxe.ds.Vector;
import mdd.host.Crash;
import mdd.host.Event;
import mdd.host.Native;
import mdd.host.Sdl;

@:unreflective
class FaultCheck {
	public static function run(args:Array<String>):Int {
		final kind = args.length > 0 && !StringTools.startsWith(args[0], "-") ? args[0] : "read";
		final where = Gate.root + "/export/fault.txt";

		final told = args.indexOf("--tell") >= 0 || args.indexOf("--window") >= 0;

		if (told) Crash.watch(where, "The gate", true);

		Sys.println("  fault");
		Sys.println("    stopping on purpose: " + kind);
		Sys.println("    the report goes to " + where);

		if (args.indexOf("--window") >= 0) shown();

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

	/**
		How long the window is left up before the fault, in seconds. Long enough to see it
		drawn and to see the crash window arrive over it rather than instead of it.
	**/
	static inline final WAITING = 2.5;

	/**
		Opens a window and paints it until the fault is due.

		A crash report is only half of what a fault does: the other half is the window the
		reader is looking at going away, and whether anything says why. That cannot be
		checked with no window open, because the message box has nothing to appear over and
		the desktop has no process to take the focus back from.
	**/
	static function shown():Void {
		Native.ready();

		if (Sdl.init() == 0) {
			Sys.println("    SDL would not start: " + Sdl.error());
			return;
		}

		final window = Sdl.createWindow("mdd gate fault", 900, 560, 0, 0);
		final renderer = Sdl.createRenderer(window, 1, mdd.App.PINNED);

		Sdl.showWindow(window);
		Sys.println("    a window is up, stopping in " + WAITING + " s");

		final until = Sdl.ticks() + WAITING;
		final event = new Event();

		var frames = 0;

		while (Sdl.ticks() < until) {
			while (Sdl.pollEvent(cpp.Pointer.addressOf(event).raw) != 0) {}

			final pulse = 0.25 + 0.2 * Math.sin(Sdl.ticks() * 4);

			Sdl.renderClear(renderer, pulse * 0.4, pulse * 0.1, pulse, 1);
			Sdl.renderPresent(renderer);
			frames++;
		}

		Sys.println("    " + frames + " frames drawn, faulting now");
	}

	static function read(args:Array<String>):Void {
		final at:Int = args.length > 4096 ? 8 : 0;
		final held:Int = untyped __cpp__("*(volatile unsigned char *)(size_t)({0})", at);

		Sys.println("    " + held);
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

	static inline final DEEPEST = 1 << 28;

	static var reached:Int = 0;

	static function deeper(depth:Int):Int {
		if (depth >= DEEPEST) return depth;

		final held = deeper(depth + 1);

		reached = held;
		return held;
	}

	static function far(args:Array<String>):Int {
		return 1 << 28 | args.length;
	}
}
