package mdd.app;

import mdd.Config;
import mdd.Typeface;
import mdd.host.Canvas;
import mdd.host.Event;
import mdd.host.Paths;
import mdd.host.Sdl;
import mdd.host.Window;
import mdd.ui.Flow;
import mdd.ui.Fallback;
import mdd.ui.Font;
import mdd.ui.Icons;
import mdd.ui.Metrics;
import mdd.ui.Paint;
import mdd.ui.Root;
import mdd.ui.Shell;
import mdd.ui.Theme;

@:unreflective

/**
	The window, the renderer, the faces and the root: everything between the operating
	system and the widget tree.

	It presents only a frame that was actually drawn. A flip model swap chain rotates
	buffers, so presenting a frame nothing was drawn into puts a frame from two
	presents ago on screen, and alternating the two reads as heavy flicker.
**/
final class Stage {
	static inline final IDLE = 0.002;
	static inline final ICON = 64;
	static inline final ROW = 16;

	/**
		The window.
	**/
	public var window:cpp.Star<Window> = null;

	/**
		Why the window would not open, said the way a reader who has only the program can act
		on, or an empty string where it opened. Nothing is on screen by then to say it in, so it
		is left for whoever started the program to show in a box of its own.
	**/
	public var failure(default, null):String = "";

	/**
		The renderer.
	**/
	public var renderer:cpp.Star<Canvas> = null;

	/**
		What everything is drawn with.
	**/
	public var paint:Paint;

	/**
		The top of the widget tree.
	**/
	public var root:Root;

	/**
		The zones the interface is laid out in.
	**/
	public var shell:Shell;

	/**
		What every size is multiplied by.
	**/
	public var scale:Float = 1;

	/**
		Which window events belong to.
	**/
	public var windowID:Int = 0;

	/**
		Which typeface pairing is chosen.
	**/
	public var typeface:Int = 0;

	/**
		What the text is drawn at against the rest of the interface, one being the usual size. It
		multiplies the faces only, so the rows and controls keep their size.
	**/
	public var textScale:Float = 1;

	/**
		Which icon atlas was loaded, or an empty string.
	**/
	public var iconsAt(default, null):String = "";

	/**
		Whether the window has been shown yet. It is created hidden so nothing appears
		before the first frame is drawn.
	**/
	public var shown(default, null):Bool = false;

	/**
		Called with the path of a file dropped on the window, where anything is
		listening. The event carries the path itself, so nothing is kept between
		this call and the next.
	**/
	public var onDrop:Null<String -> Void> = null;

	/**
		Called when the window comes back to the front, which is when something changed
		in another program, such as the presets folder in the file manager, is looked
		for.
	**/
	public var onFocus:Null<Void -> Void> = null;

	var icons:Null<Icons> = null;

	final spare:Fallback = new Fallback();

	var body:Null<Font> = null;
	var small:Null<Font> = null;
	var mono:Null<Font> = null;
	var large:Null<Font> = null;
	var condensed:Null<Font> = null;

	/**
		Builds a stage with nothing open.
	**/
	public function new() {}

	/**
		Which renderer backend to ask for, or an empty string for whichever SDL picks.
	**/
	public var driver:String = "";

	/**
		Whether every frame is drawn and presented, rather than only the ones where
		something changed.

		Drawing only what changed is what keeps an idle window off the processor, and
		it is the one thing this application does that an ordinary SDL program does
		not. Turning it off is how a fault that only shows while the interface is
		moving is told apart from one in the backend underneath.
	**/
	public var always:Bool = false;

	/**
		Starts SDL, opens the window and the renderer, loads the faces and the icons,
		and builds the root.

		@return False where any of that would not work.
	**/
	public function open():Bool {
		window = Sdl.createWindow(Config.TITLE, Config.WIDTH, Config.HEIGHT,
			Config.RESIZABLE ? 1 : 0, Config.HIGH_DPI ? 1 : 0);

		if (window == null) {
			return failed(Config.TITLE + " could not open a window.\n\n" + Sdl.error());
		}

		Sdl.setWindowMinimumSize(window, Config.LEAST_WIDTH, Config.LEAST_HEIGHT);
		faced();
		windowID = Sdl.windowID(window);

		renderer = Sdl.createRenderer(window, Config.VSYNC ? 1 : 0, driver);
		if (renderer == null) {
			Sdl.destroyWindow(window);

			return failed(Config.TITLE + " could not start drawing, with the graphics driver or"
				+ " without it.\n\nStarting it with --renderer=software draws without"
				+ " the graphics card.\n\n" + Sdl.error());
		}

		scale = Sdl.windowDisplayScale(window);

		final metrics = new Metrics(scale);
		shell = new Shell();
		root = new Root(shell, metrics, new Theme());
		root.flow = Sdl.reduceMotion() != 0 ? Flow.Reduced : Flow.Full;
		root.onWarp = function(x:Float, y:Float):Void Sdl.warp(window, x, y);

		if (!faces(metrics)) return false;

		paint = Paint.on(renderer, body);
		drawn();

		return true;
	}

	/**
		Lays the interface out for the size and density the window actually opened at.
	**/
	public function drawn():Void {
		final want = Math.round(metrics().whole(ROW));
		if (icons != null && icons.pixels == want) return;

		final where = atlases();
		if (where == "") return;

		final file = where + "/icons-" + nearest(where, want) + ".atlas";
		final made = Icons.read(renderer, file);

		if (made == null) {
			iconsAt = "none, looked in " + where;
			return;
		}

		iconsAt = made.count + " at " + made.pixels + " px, " + made.atlasWidth + "x"
			+ made.atlasHeight;

		if (icons != null) icons.shut();

		icons = made;
		root.icons = made;
	}

	/**
		@return The sizes the interface draws at.
	**/
	inline function metrics():Metrics {
		return root.metrics;
	}

	/**
		@return The folder the icon atlases are in, which is the one beside the program and no
			other, or an empty string where there is none. A build puts the atlases beside the
			binary it makes, so a copy run from the repository looks where a reader's copy looks.
	**/
	function atlases():String {
		final where = haxe.io.Path.normalize(Paths.beside() + "/icons");

		return sys.FileSystem.exists(where) ? where : "";
	}

	/**
		@param where The folder the atlases are in.
		@param want The size wanted, in pixels.
		@return The size that is actually there and closest to it.
	**/
	function nearest(where:String, want:Int):Int {
		var best = 0;

		for (name in sys.FileSystem.readDirectory(where)) {
			if (!StringTools.startsWith(name, "icons-")
				|| !StringTools.endsWith(name, ".atlas")) continue;

			final held = Std.parseInt(name.substring(6, name.length - 6));
			if (held == null) continue;

			if (best == 0) best = held;
			else if (best < want) best = held > best ? held : best;
			else if (held >= want && held < best) best = held;
		}

		return best;
	}

	/**
		Loads the faces the chosen pairing names.
	**/
	function faced():Void {
		final held = haxe.Resource.getBytes("icon");
		if (held == null || held.length != ICON * ICON * 4) return;

		Sdl.windowIcon(window, cpp.NativeArray.address(held.getData(), 0).constRaw, ICON, ICON);
	}

	/**
		Shows the window, once there is a frame to show.

		@param maximised Whether to open it maximised.
	**/
	public function show(maximised:Bool):Void {
		Sdl.showWindow(window);
		if (maximised) Sdl.maximiseWindow(window);

		shown = true;

		final event = new Event();
		while (Sdl.pollEvent(cpp.Pointer.addressOf(event).raw) != 0) took(event);

		measured();
	}

	/**
		Brings the window in front of the others, restoring it where it was minimised.
	**/
	public function raise():Void {
		if (window != null) Sdl.raiseWindow(window);
	}

	/**
		@return Whether the window is maximised.
	**/
	public function maximised():Bool {
		return Sdl.windowMaximised(window) != 0;
	}

	/**
		Records why the window would not open, and prints it for whoever started the program from a
		terminal.

		@param said What went wrong and what to do about it.
		@return False, so a failure can be returned as it is recorded.
	**/
	function failed(said:String):Bool {
		failure = said;
		Sys.println("mdd: " + StringTools.replace(said, "\n\n", " "));

		return false;
	}

	/**
		@return The folder the faces are in, which is the one beside the program and no other, or
			an empty string where it holds no face to start with. A build puts the same faces
			beside the binary it makes, so a copy run from the repository looks where a reader's
			copy looks, and a download missing its fonts cannot be covered by the ones here.
	**/
	public function fonts():String {
		final where = haxe.io.Path.normalize(Paths.beside() + "/fonts");

		return sys.FileSystem.exists(where + "/" + Typeface.SANS[0]) ? where : "";
	}

	/**
		@param where The folder the faces are in.
		@return Which pairing is actually present, falling back where the chosen one is not there.
	**/
	function paired(where:String):Int {
		if (typeface < 0 || typeface >= Typeface.COUNT) return 0;

		if (!sys.FileSystem.exists(where + "/" + Typeface.SANS[typeface])
			|| !sys.FileSystem.exists(where + "/" + Typeface.MONO[typeface])) return 0;

		return typeface;
	}

	/**
		Bakes the four faces at the current density and hands them to the metrics.

		@param metrics The sizes to dress.
		@return False where any of them would not bake.
	**/
	public function faces(metrics:Metrics):Bool {
		final where = fonts();

		if (where == "") {
			return failed(Config.TITLE + " could not find its fonts.\n\nIt reads them from"
				+ " the fonts folder beside the program, so the folder it came in has to be kept"
				+ " whole: extract everything from the download, not the program on its own.\n\nIt"
				+ " looked in " + haxe.io.Path.normalize(Paths.beside() + "/fonts") + ".");
		}

		shed();

		final fetched = mdd.app.Faces.keptFolder();

		for (name in Typeface.FALLBACK) {
			spare.adds(where + "/" + name);
			spare.adds(fetched + "/" + name);
		}

		if (!baked(metrics, where, scale * textScale)) {
			return failed(Config.TITLE + " found its fonts but could not read them. One of them"
				+ " may be damaged: extracting the download again replaces them.\n\nThey are"
				+ " in " + where + ".");
		}

		body = metrics.body;
		small = metrics.small;
		mono = metrics.mono;
		large = metrics.large;
		condensed = metrics.condensed;

		if (paint != null) paint.reface(body);
		return true;
	}

	/**
		Bakes the faces again at a density of their own, for a picture drawn off the window at a
		scale the window is not at, which a video is. Nothing else holds them, so the caller gives
		them back through `shuts` once it is done.

		@param density What to multiply every design size by.
		@return The sizes, dressed, or null where the faces would not bake.
	**/
	public function bakes(density:Float):Null<Metrics> {
		final where = fonts();
		if (where == "") return null;

		final held = new Metrics(density);
		return baked(held, where, density) ? held : null;
	}

	/**
		Gives back the faces `bakes` made. The window's own sizes are left alone.

		@param metrics The sizes `bakes` returned.
	**/
	public function shuts(metrics:Metrics):Void {
		if (root != null && metrics == root.metrics) return;

		if (metrics.body != null) metrics.body.shut();
		if (metrics.small != null) metrics.small.shut();
		if (metrics.mono != null) metrics.mono.shut();
		if (metrics.large != null) metrics.large.shut();
		if (metrics.condensed != null) metrics.condensed.shut();
	}

	/**
		Bakes the five faces at a density and dresses a set of sizes in them, chained to the
		fallback faces. Where any of them will not bake, the ones that did are given back and the
		sizes are left as they were.

		@param metrics The sizes to dress.
		@param where The folder the faces are in.
		@param density What to multiply every design size by.
		@return Whether they all baked.
	**/
	function baked(metrics:Metrics, where:String, density:Float):Bool {
		final pairing = paired(where);
		final sans = where + "/" + Typeface.SANS[pairing];
		final fixed = where + "/" + Typeface.MONO[pairing];

		final text = Font.bake(renderer, sans, 15 * density);
		final lesser = Font.bake(renderer, sans, 13 * density);
		final digits = Font.bake(renderer, fixed, 14 * density);
		final heading = Font.bake(renderer, fixed, 21 * density);

		final narrow = mdd.Typeface.CONDENSED == "" ? null
			: Font.bake(renderer, where + "/" + mdd.Typeface.CONDENSED, 13 * density);

		if (text == null || lesser == null || digits == null || heading == null) {
			if (text != null) text.shut();
			if (lesser != null) lesser.shut();
			if (digits != null) digits.shut();
			if (heading != null) heading.shut();
			if (narrow != null) narrow.shut();

			return false;
		}

		text.chains(spare);
		lesser.chains(spare);
		digits.chains(spare);
		heading.chains(spare);
		if (narrow != null) narrow.chains(spare);

		metrics.dress(text, lesser, digits, heading, narrow);
		return true;
	}

	/**
		Gives the baked faces back.
	**/
	function shed():Void {
		if (body != null) body.shut();
		if (small != null) small.shut();
		if (mono != null) mono.shut();
		if (large != null) large.shut();
		if (condensed != null) condensed.shut();

		body = null;
		small = null;
		mono = null;
		large = null;
		condensed = null;
	}

	/**
		Reads the window size again and lays the interface out to it.
	**/
	public function measured():Void {
		root.resize(Sdl.outputWidth(renderer), Sdl.outputHeight(renderer));
		shell.fit(root.metrics);
	}

	/**
		Bakes the faces again, which changing the pairing or the density needs.
	**/
	public function redressed():Void {
		if (!faces(root.metrics)) return;

		drawn();
		measured();
		root.reshape();
	}

	/**
		Reads the fallback faces from disk again and bakes everything, which a face fetched
		since they were read needs: the list already names where it would be, but a face is
		only looked for when the list is first read, and every glyph that missed before is
		remembered as missing until the faces are baked again.
	**/
	public function refaced():Void {
		spare.shut();

		if (!faces(root.metrics)) return;

		drawn();
		measured();
		root.reshape();
	}

	/**
		Changes the density everything is drawn at.

		@param much The new scale.
	**/
	public function densified(much:Float):Void {
		root.rescale(scale * much);
		faces(root.metrics);
		drawn();
		measured();
	}

	/**
		Bakes the faces and reloads the icons at the new density, and lays out again.
	**/
	function rescaled():Void {
		final next = Sdl.windowDisplayScale(window);
		if (next == scale) return;

		scale = next;
		root.rescale(scale);
		faces(root.metrics);
		drawn();
		measured();
	}

	/**
		Turns one system event into whatever the interface should do with it.

		@param event The event.
		@return False where the event was the window closing.
	**/
	public function took(event:Event):Bool {
		switch (event.type) {
			case Sdl.EVENT_QUIT:
				return false;

			case Sdl.EVENT_WINDOW_CLOSE:
				if (event.windowID == windowID) return false;

			case Sdl.EVENT_WINDOW_RESIZED:
				if (event.windowID == windowID) measured();

			case Sdl.EVENT_WINDOW_SCALE_CHANGED:
				if (event.windowID == windowID) rescaled();

			case Sdl.EVENT_WINDOW_EXPOSED:
				root.soil();

			case Sdl.EVENT_WINDOW_FOCUS_GAINED:
				final held = onFocus;
				if (held != null && event.windowID == windowID) held();

			case Sdl.EVENT_WINDOW_FOCUS_LOST:
				if (event.windowID == windowID) root.lets();

			case Sdl.EVENT_MOUSE_MOVE:
				root.moved(event.x, event.y, event.mods, event.code);

			case Sdl.EVENT_MOUSE_DOWN:
				root.pressed(event.x, event.y, event.code, event.mods, event.value);

			case Sdl.EVENT_MOUSE_UP:
				root.released(event.x, event.y, event.code, event.mods);

			case Sdl.EVENT_MOUSE_WHEEL:
				root.turned(event.x, event.y, event.mods);

			case Sdl.EVENT_KEY_DOWN:
				root.key(true, event.code, event.mods, event.value != 0);

			case Sdl.EVENT_KEY_UP:
				root.key(false, event.code, event.mods);

			case Sdl.EVENT_TEXT:
				root.said(Sdl.eventText(cpp.Pointer.addressOf(event).constRaw), event.mods);

			case Sdl.EVENT_DROP_FILE:
				final held = onDrop;
				if (held != null && event.windowID == windowID) {
					held(Sdl.eventText(cpp.Pointer.addressOf(event).constRaw));
				}

			case _:
		}

		return true;
	}

	/**
		Draws one frame and presents it, and does neither where nothing changed.

		@return Whether a frame was actually drawn.
	**/
	public function draw():Bool {
		if (always) root.soil();

		if (!root.stale()) {
			Sdl.sleep(IDLE);
			return false;
		}

		final ground = root.theme.ground;
		Sdl.renderClear(renderer, ground.red / 255, ground.green / 255, ground.blue / 255, 1);
		root.frame(paint);
		Sdl.renderPresent(renderer);

		return true;
	}

	/**
		Gives the faces, the icons, the renderer and the window back, in that order.
	**/
	public function shut():Void {
		if (icons != null) icons.shut();

		spare.shut();
		shed();
		Sdl.freeCursors();
		Sdl.destroyRenderer(renderer);
		Sdl.destroyWindow(window);
	}
}
