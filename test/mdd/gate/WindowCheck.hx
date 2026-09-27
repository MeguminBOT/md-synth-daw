package mdd.gate;

import mdd.host.Event;
import mdd.host.Native;
import mdd.host.Sdl;

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

		final window = Sdl.createWindow("mdd gate window", 640, 400, 0, 0);
		if (window == null) {
			Sys.println("    no window: " + Sdl.error());
			Sdl.quit();
			return 1;
		}

		final renderer = Sdl.createRenderer(window, 0, mdd.App.PINNED);
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

		if (!required()) return 1;

		Sys.println("    passed");
		return 0;
	}

	/**
		What `--requirements` writes for the installer has a line for every renderer the
		application offers, each saying `0`, `1` or a version, and on Windows the graphics memory
		as well. It is read for its shape rather than its values, which are this machine's.

		@return Whether it is all there.
	**/
	static function required():Bool {
		final written = Gate.root + "/export/requirements.txt";
		final wrote = mdd.host.Requirements.write(written);
		final lines = wrote == 0 && sys.FileSystem.exists(written)
			? sys.io.File.getContent(written).split("\n") : [];

		final offered = mdd.App.offered();
		final shaped = ~/^(0|1|[0-9]+\.[0-9]+)$/;
		var found = 0;
		var made = 0;
		var graphics = -1;

		for (line in lines) {
			final split = line.indexOf(" ");
			if (split < 0) continue;

			final name = line.substr(0, split);
			final value = StringTools.trim(line.substr(split + 1));

			if (name == "graphics") {
				final parsed = Std.parseInt(value);
				graphics = parsed == null ? -1 : parsed;
			}
			if (offered.indexOf(name) < 0 || !shaped.match(value)) continue;

			found++;
			if (value != "0") made++;
		}

		Sys.println("    requirements  " + found + " of " + offered.length + " renderers written, "
			+ made + " made, " + graphics + " MB of graphics memory");

		#if windows
		if (graphics < 0) {
			Sys.println("    requirements left out the graphics memory");
			return false;
		}
		#end

		if (found != offered.length) {
			Sys.println("    requirements left out " + (offered.length - found) + " renderers");
			return false;
		}

		return true;
	}

	static function round(value:Float):Float {
		return Math.round(value * 1000) / 1000;
	}
}
