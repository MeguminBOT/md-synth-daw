package mdd.gate;

import haxe.ds.Vector;
import mdd.host.Canvas;
import mdd.host.Draw;
import mdd.host.Native;
import mdd.host.Sdl;
import mdd.host.Window;
import mdd.ui.Colour;
import mdd.ui.Font;
import mdd.ui.Paint;

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
		How many frames of changing text are presented before the one that is read back.

		Reading a frame back flushes the queue and waits, so a run of frames that are
		only presented is the one way a check sees what the interface sees. The text has
		to change between them: a hazard in the vertices cannot show where every frame
		carries the same ones.
	**/
	static inline final PIPED = 90;

	/**
		How wide the held window is, and how tall, and how many lines of text go in it.
		Small enough to sit beside whatever else is on the screen.
	**/
	static inline final WIDE = 420;
	static inline final TALL = 300;
	static inline final ROWS = 16;

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

		var held = 0.0;
		final names:Array<String> = [];
		var at = 0;

		while (at < args.length) {
			if (args[at] == "--hold" && at + 1 < args.length) {
				held = Std.parseFloat(args[at + 1]);
				if (Math.isNaN(held)) held = 0;
				at += 2;
				continue;
			}

			names.push(args[at]);
			at++;
		}

		final want = names.length > 0 ? names : offered();

		if (held > 0) {
			for (name in want) shown(name, held);
			Sdl.quit();
			return 0;
		}

		for (name in want) probed(name);

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
		Holds a window of text up through one backend, so it can be captured from
		outside the process.

		Reading the buffer back inside the process flushes the queue and waits, and
		that is enough to make every frame come out right. What the card actually
		scans out is only visible to something else looking at the window, so this
		draws and presents and then stays up rather than reading anything.

		The window is small and never raised, so it can sit in a corner while somebody
		is working.

		@param want Which backend to ask for.
		@param seconds How long to hold it up.
	**/
	static function shown(want:String, seconds:Float):Void {
		final window = Sdl.createWindow("mdd swap " + want, WIDE, TALL, 0, 0);
		if (window == null) return;

		final renderer = Sdl.createRenderer(window, 1, want);
		if (renderer == null) {
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

		final font = Font.bake(renderer, Gate.root + "/vendor/fonts/Go-Regular.ttf", 15);

		if (font == null) {
			Sdl.destroyRenderer(renderer);
			Sdl.destroyWindow(window);
			return;
		}

		final paint = Paint.on(renderer, font);
		final white = new Colour(0xFFFFFF);
		final event = new mdd.host.Event();
		final sheet = paint.sheet(WIDE, Std.int(TALL * 0.5));

		if (sheet == null) {
			font.shut();
			Sdl.destroyRenderer(renderer);
			Sdl.destroyWindow(window);
			return;
		}

		Sdl.showWindow(window);
		Sys.println("    " + StringTools.rpad(got, " ", 14) + "held up for "
			+ seconds + " s as \"mdd swap " + got + "\"");

		final until = Sdl.ticks() + seconds;
		final rebakeAt = Sdl.ticks() + seconds * 0.4;

		var face = font;
		var frame = 0;
		var baked = false;

		while (Sdl.ticks() < until) {
			while (Sdl.pollEvent(cpp.Pointer.addressOf(event).raw) != 0) {}

			if (!baked && Sdl.ticks() > rebakeAt) {
				baked = true;

				final next = Font.bake(renderer,
					Gate.root + "/vendor/fonts/Go-Regular.ttf", 15);

				if (next != null) {
					face.shut();
					face = next;
					paint.reface(face);
					Sys.println("    " + StringTools.rpad("", " ", 14)
						+ "the face was baked again part way through");
				}
			}

			Sdl.renderClear(renderer, 0.08, 0.09, 0.11, 1);
			paint.reset();

			paint.target(sheet);
			paint.clear(0.16, 0.10, 0.10, 1);

			for (row in 0...ROWS) {
				paint.text("SHEET " + KNOWN, 4, 2 + row * 17, white, 1);
			}

			paint.flush();
			paint.target(null);

			paint.blit(sheet, 0, 0, WIDE, TALL * 0.5);

			for (row in 0...ROWS) {
				paint.text("DIRECT " + KNOWN, 6, 6 + TALL * 0.5 + row * 17, white, 1);
			}

			paint.flush();
			Sdl.renderPresent(renderer);

			frame++;
		}

		face.shut();
		Sdl.destroyRenderer(renderer);
		Sdl.destroyWindow(window);
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
		Sys.println("    " + StringTools.rpad("", " ", 14) + "text after "
			+ PIPED + " presented frames of it changing reads " + texted(renderer));

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
		Draws a run of frames of changing text, presenting each and reading none, then
		draws one known line and reads that.

		The interface draws its text as triangles out of one atlas, and the vertices
		carrying the atlas coordinates are what a backend has to get to the card
		unchanged. Where it does not, a glyph is drawn from the wrong place in the
		atlas and reads as a different letter.

		@param renderer The renderer to draw through.
		@return What the known line came out as, as a number the backends are compared
			on.
	**/
	static function texted(renderer:cpp.Star<Canvas>):String {
		final font = Font.bake(renderer, Gate.root + "/vendor/fonts/Go-Regular.ttf", 15);
		if (font == null) return "no font to draw with";

		final paint = Paint.on(renderer, font);
		final white = new Colour(0xFFFFFF);

		for (frame in 0...PIPED) {
			Sdl.renderClear(renderer, 0, 0, 0, 1);
			paint.reset();

			for (row in 0...12) {
				paint.text(shifting(frame, row), 4, 4 + row * 18, white, 1);
			}

			paint.flush();
			Sdl.renderPresent(renderer);
		}

		Sdl.renderClear(renderer, 0, 0, 0, 1);
		paint.reset();
		paint.text(KNOWN, 4, 4, white, 1);
		paint.flush();

		final lit = new Vector<cpp.UInt8>(SIDE * 24 * 4);
		final read = Draw.readPixels(renderer, 0, 0, SIDE, 24,
			cpp.Pointer.arrayElem(lit.toData(), 0).raw);

		font.shut();

		if (read == 0) return "nothing, it would not read back";

		var sum = 0;
		var on = 0;

		for (index in 0...SIDE * 24) {
			final value = lit[index * 4];
			if (value <= 40) continue;

			on++;
			sum = (sum * 31 + value * (index + 1)) & 0x3FFFFFFF;
		}

		return on + " lit, " + sum;
	}

	/**
		@param frame Which frame.
		@param row Which line of it.
		@return A line whose letters and length both move, so no two frames hand the
			card the same vertices.
	**/
	static function shifting(frame:Int, row:Int):String {
		final out = new StringBuf();
		final many = 6 + ((frame + row) % 17);

		for (at in 0...many) {
			out.addChar(33 + ((frame * 7 + row * 13 + at * 3) % 94));
		}

		return out.toString();
	}

	/**
		The line the comparison is made on, the one the interface draws over its
		channel rack and which came out wrong under vulkan.
	**/
	static inline final KNOWN = "CHANNEL RACK";

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
