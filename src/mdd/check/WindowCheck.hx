package mdd.check;

import mdd.host.Canvas;
import mdd.host.Event;
import mdd.host.Native;
import mdd.host.Sdl;
import mdd.host.Window;

@:unreflective
class WindowCheck {
	static inline final FRAMES = 120;

	public static function run(args:Array<String>):Int {
		Native.ready();

		Sys.println("  window");

		if (Sdl.init() == 0) {
			Sys.println("    SDL would not start: " + Sdl.error());
			return 1;
		}

		final window = Sdl.createWindow("mdd gate window", 640, 400);
		if (window == null) {
			Sys.println("    no window: " + Sdl.error());
			Sdl.quit();
			return 1;
		}

		final renderer = Sdl.createRenderer(window, 0);
		if (renderer == null) {
			Sys.println("    no renderer: " + Sdl.error());
			Sdl.destroyWindow(window);
			Sdl.quit();
			return 1;
		}

		Sdl.showWindow(window);

		final event = new Event();
		var drawn = 0;
		var worst = 0.0;

		final began = Sdl.ticks();
		var last = began;

		while (drawn < FRAMES) {
			while (Sdl.pollEvent(cpp.Pointer.addressOf(event).raw) != 0) {}

			Sdl.renderClear(renderer, 0.08, 0.09, 0.11, 1);
			Sdl.renderPresent(renderer);

			final now = Sdl.ticks();
			final took = now - last;
			if (took > worst) worst = took;
			last = now;
			drawn++;
		}

		final spent = Sdl.ticks() - began;

		Sdl.destroyRenderer(renderer);
		Sdl.destroyWindow(window);
		Sdl.quit();

		Sys.println("    frames        " + drawn);
		Sys.println("    mean          " + round(spent * 1000 / drawn) + " ms");
		Sys.println("    worst         " + round(worst * 1000) + " ms");

		if (drawn != FRAMES) {
			Sys.println("    only " + drawn + " of " + FRAMES + " frames were drawn");
			return 1;
		}

		Sys.println("    passed");
		return 0;
	}

	static function round(value:Float):Float {
		return Math.round(value * 1000) / 1000;
	}
}
