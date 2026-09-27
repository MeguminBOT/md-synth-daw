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
		final named = (Sdl.rendererName(renderer) : String);
		final reached = mdd.host.Requirements.reached(renderer);

		Sdl.destroyRenderer(renderer);
		Sdl.destroyWindow(window);

		final fell = fallsBack();

		Sdl.quit();

		Sys.println("    frames        " + drawn);
		Sys.println("    mean          " + round(spent * 1000 / drawn) + " ms");
		Sys.println("    worst         " + round(worst * 1000) + " ms");

		if (drawn != FRAMES) {
			Sys.println("    only " + drawn + " of " + FRAMES + " frames were drawn");
			return 1;
		}

		Sys.println("    renderer      " + named + (reached > 0
			? ", feature level " + (reached >> 8) + "_" + (reached & 0xFF) : ""));

		if (named == "direct3d11" && reached == 0) {
			Sys.println("    direct3d11 answered no feature level, so a machine short of one"
				+ " would never fall back");
			return 1;
		}

		#if windows
		if (!fell) {
			Sys.println("    a renderer the window falls back to did not say what level it reached");
			return 1;
		}
		#end

		if (!required()) return 1;

		Sys.println("    passed");
		return 0;
	}

	/**
		Makes Direct3D 11 on a window, gives it back, and makes each renderer the application
		falls back to on the same window in turn, the way a machine short of the feature level
		does. Each one made has to say what level it reached, or the window could not tell whether
		it falls short as well. One this machine cannot make is only reported, since that says
		what the machine has rather than whether the fallback works.

		@return Whether every one made said what it reached.
	**/
	static function fallsBack():Bool {
		final window = Sdl.createWindow("mdd gate fallback", 320, 200, 0, 0);
		if (window == null) return true;

		final first = Sdl.createRenderer(window, 1, "direct3d11");
		if (first != null) Sdl.destroyRenderer(first);

		var told = true;

		for (name in @:privateAccess mdd.App.FALLBACKS) {
			final made = Sdl.createRenderer(window, 1, name);
			final got = made == null ? "" : (Sdl.rendererName(made) : String);
			final level = got == name ? mdd.host.Requirements.reached(made) : 0;

			if (got == name) {
				Sdl.renderClear(made, 0, 0, 0, 1);
				Sdl.renderPresent(made);
			}

			Sys.println("    falls back    to " + name + (got != name ? ", which is not made here"
				: " at " + (level >> 8) + "." + (level & 0xFF)));

			if (got == name && level == 0) told = false;
			if (made != null) Sdl.destroyRenderer(made);
		}

		Sdl.destroyWindow(window);
		return told;
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
