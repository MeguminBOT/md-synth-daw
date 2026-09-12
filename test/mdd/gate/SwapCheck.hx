package mdd.gate;

import haxe.ds.Vector;
import mdd.host.Canvas;
import mdd.host.Draw;
import mdd.host.Native;
import mdd.host.Sdl;
import mdd.host.Window;

/**
	What each renderer backend hands back as the buffer to draw the next frame into.

	A flip model swapchain rotates its buffers, so the one a frame starts with holds
	what was presented some number of frames ago rather than what was presented last.
	How many frames back differs by backend, and it is what decides whether a frame
	that is presented without being wholly drawn shows something stale.

	Nothing here reads the screen, which cannot be read. It reads the buffer the
	renderer is about to draw into, before anything clears it, which is the same
	rotation seen from the other side.
**/
@:unreflective
class SwapCheck {
	static inline final FRAMES = 10;
	static inline final SIDE = 320;

	/**
		Runs the probe against every backend SDL offers, or against the ones named.

		@param args Backend names, or none for all of them.
		@return Nonzero where SDL would not start.
	**/
	public static function run(args:Array<String>):Int {
		Native.ready();
		Sys.println("  swap");

		if (Sdl.init() == 0) {
			Sys.println("    SDL would not start: " + Sdl.error());
			return 1;
		}

		final names = args.length > 0 ? args : offered();

		for (name in names) probed(name);

		Sdl.quit();
		return 0;
	}

	/**
		@return Every backend name SDL was built with.
	**/
	static function offered():Array<String> {
		final out:Array<String> = [];

		for (index in 0...Sdl.renderDrivers()) {
			final name = (Sdl.renderDriver(index) : String);
			if (name != "" && name != "software") out.push(name);
		}

		return out;
	}

	/**
		Presents a run of frames, each a flat colour of its own, reading the buffer each
		one starts with before anything clears it.

		@param want Which backend to ask for.
	**/
	static function probed(want:String):Void {
		final window = Sdl.createWindow("mdd gate swap", SIDE, SIDE, 0, 0);

		if (window == null) {
			Sys.println("    " + StringTools.rpad(want, " ", 14) + "no window");
			return;
		}

		final renderer = Sdl.createRenderer(window, 0, want);

		if (renderer == null) {
			Sys.println("    " + StringTools.rpad(want, " ", 14) + "no renderer");
			Sdl.destroyWindow(window);
			return;
		}

		final got = (Sdl.rendererName(renderer) : String);

		if (got != want) {
			Sys.println("    " + StringTools.rpad(want, " ", 14) + "fell back to " + got);
			Sdl.destroyRenderer(renderer);
			Sdl.destroyWindow(window);
			return;
		}

		Sdl.showWindow(window);

		final pixels = new Vector<cpp.UInt8>(16);
		final seen:Array<Int> = [];

		for (frame in 0...FRAMES) {
			for (index in 0...pixels.length) pixels[index] = 0;

			final read = Draw.readPixels(renderer, 0, 0, 2, 2,
				cpp.Pointer.arrayElem(pixels.toData(), 0).raw);

			seen.push(read == 0 ? -1 : pixels[0]);

			final shade = mark(frame) / 255.0;
			Sdl.renderClear(renderer, shade, shade, shade, 1);
			Sdl.renderPresent(renderer);
		}

		Sys.println("    " + StringTools.rpad(got, " ", 14) + told(seen));
		Sys.println("    " + StringTools.rpad("", " ", 14) + "a clear "
			+ clipped(renderer, pixels));
		Sys.println("    " + StringTools.rpad("", " ", 14) + "a frame that draws into"
			+ " a texture part way through " + survives(renderer, pixels));

		Sdl.destroyRenderer(renderer);
		Sdl.destroyWindow(window);
	}

	/**
		@param frame Which frame.
		@return The shade that frame is cleared to, spaced so two frames are never
			mistaken for each other.
	**/
	static inline function mark(frame:Int):Int {
		return 20 + frame * 20;
	}

	/**
		Works out how far back the buffer a frame starts with was presented.

		The first few readings are of buffers nothing has been presented into yet, and
		they read as nought. How many of those there are is the depth of the chain, so
		they are counted rather than skipped.

		@param seen What each frame read before it cleared anything.
		@return What that says about the rotation.
	**/
	static function told(seen:Array<Int>):String {
		var back = -1;
		var steady = true;

		for (frame in 0...seen.length) {
			if (seen[frame] <= 0) continue;

			var found = -1;

			for (age in 1...frame + 1) {
				if (seen[frame] == mark(frame - age)) {
					found = age;
					break;
				}
			}

			if (found < 0) {
				return "read " + held(seen) + ", which is no frame it presented";
			}

			if (back < 0) back = found;
			else if (found != back) steady = false;
		}

		if (back < 0) return "never read a frame it presented: " + held(seen);
		if (!steady) return "rotates unevenly: " + held(seen);

		return back + " deep, so a frame presented without being wholly drawn shows the"
			+ " one " + back + " before it";
	}

	/**
		Whether what a frame has already drawn survives a turn through a texture.

		A sheet bakes itself into a texture of its own part way through the frame and
		then goes back to the window. Backends that record a render pass have to end
		one and begin another to do it, and what the frame had already put in the
		window is lost where the second pass does not load it back.

		@param renderer The renderer to ask.
		@param pixels Somewhere to read into, at least four pixels wide.
		@return Whether the window kept what was drawn before the turn.
	**/
	static function survives(renderer:cpp.Star<Canvas>, pixels:Vector<cpp.UInt8>):String {
		Sdl.renderClear(renderer, 0.8, 0.8, 0.8, 1);

		final sheet = Draw.createTarget(renderer, 32, 32);
		if (sheet == null) return "could not be tried: no target texture";

		Draw.setTarget(renderer, sheet);
		Sdl.renderClear(renderer, 0, 0, 0, 1);
		Draw.setTarget(renderer, null);

		for (index in 0...pixels.length) pixels[index] = 0;

		final read = Draw.readPixels(renderer, SIDE - 2, SIDE - 2, 2, 2,
			cpp.Pointer.arrayElem(pixels.toData(), 0).raw);

		Draw.destroyTexture(sheet);

		if (read == 0) return "could not be read back";

		return pixels[0] > 128 ? "keeps what it had already drawn"
			: "LOSES what it had already drawn, read " + pixels[0];
	}

	/**
		Whether a clear reaches past a clip that is still set.

		The frame clears before the paint stack unwinds, so a clip left on the renderer
		by the frame before would hold the clear to it and leave the rest of the window
		showing whatever the chain rotated in.

		@param renderer The renderer to ask.
		@param pixels Somewhere to read into, at least four pixels wide.
		@return Whether it covered the whole target or only the clip.
	**/
	static function clipped(renderer:cpp.Star<Canvas>, pixels:Vector<cpp.UInt8>):String {
		Sdl.renderClear(renderer, 0, 0, 0, 1);
		Sdl.setClip(renderer, 0, 0, 8, 8);
		Sdl.renderClear(renderer, 1, 1, 1, 1);
		Sdl.clearClip(renderer);

		for (index in 0...pixels.length) pixels[index] = 0;

		final read = Draw.readPixels(renderer, SIDE - 2, SIDE - 2, 2, 2,
			cpp.Pointer.arrayElem(pixels.toData(), 0).raw);

		if (read == 0) return "could not be read back";

		return pixels[0] > 128 ? "reaches past a clip that is set"
			: "is held to a clip that is set";
	}

	/**
		@param seen What each frame read.
		@return Them in order, short enough to read on one line.
	**/
	static function held(seen:Array<Int>):String {
		final out:Array<String> = [];
		for (value in seen) out.push("" + value);

		return out.join(" ");
	}
}
