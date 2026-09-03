package mdd.app;

import mdd.Config;
import mdd.Typeface;
import mdd.host.Canvas;
import mdd.host.Event;
import mdd.host.Paths;
import mdd.host.Sdl;
import mdd.host.Window;
import mdd.ui.Flow;
import mdd.ui.Font;
import mdd.ui.Icons;
import mdd.ui.Metrics;
import mdd.ui.Paint;
import mdd.ui.Root;
import mdd.ui.Shell;
import mdd.ui.Theme;

@:unreflective
final class Stage {
	static inline final IDLE = 0.002;
	static inline final ICON = 64;
	static inline final ROW = 16;

	public var window:cpp.Star<Window> = null;
	public var renderer:cpp.Star<Canvas> = null;

	public var paint:Paint;
	public var root:Root;
	public var shell:Shell;

	public var scale:Float = 1;
	public var windowID:Int = 0;
	public var typeface:Int = 0;

	public var iconsAt(default, null):String = "";
	public var shown(default, null):Bool = false;

	var icons:Null<Icons> = null;

	var body:Null<Font> = null;
	var small:Null<Font> = null;
	var mono:Null<Font> = null;
	var large:Null<Font> = null;

	public function new() {}

	public function open():Bool {
		window = Sdl.createWindow(Config.TITLE, Config.WIDTH, Config.HEIGHT,
			Config.RESIZABLE ? 1 : 0, Config.HIGH_DPI ? 1 : 0);

		if (window == null) {
			Sys.println("mdd: no window: " + Sdl.error());
			return false;
		}

		Sdl.setWindowMinimumSize(window, Config.LEAST_WIDTH, Config.LEAST_HEIGHT);
		faced();
		windowID = Sdl.windowID(window);

		renderer = Sdl.createRenderer(window, Config.VSYNC ? 1 : 0);
		if (renderer == null) {
			Sys.println("mdd: no renderer: " + Sdl.error());
			Sdl.destroyWindow(window);
			return false;
		}

		scale = Sdl.windowDisplayScale(window);

		final metrics = new Metrics(scale);
		shell = new Shell();
		root = new Root(shell, metrics, new Theme());
		root.flow = Sdl.reduceMotion() != 0 ? Flow.Reduced : Flow.Full;

		if (!faces(metrics)) return false;

		paint = Paint.on(renderer, body);
		drawn();

		return true;
	}

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

	inline function metrics():Metrics {
		return root.metrics;
	}

	function atlases():String {
		for (where in [Paths.beside() + "/icons", Sys.getCwd() + "/export/icons",
				Paths.beside() + "/../../icons"]) {
			if (sys.FileSystem.exists(where)) return haxe.io.Path.normalize(where);
		}

		return "";
	}

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

	function faced():Void {
		final held = haxe.Resource.getBytes("icon");
		if (held == null || held.length != ICON * ICON * 4) return;

		Sdl.windowIcon(window, cpp.NativeArray.address(held.getData(), 0).constRaw, ICON, ICON);
	}

	public function show(maximised:Bool):Void {
		Sdl.showWindow(window);
		if (maximised) Sdl.maximiseWindow(window);

		shown = true;

		final event = new Event();
		while (Sdl.pollEvent(cpp.Pointer.addressOf(event).raw) != 0) took(event);

		measured();
	}

	public function maximised():Bool {
		return Sdl.windowMaximised(window) != 0;
	}

	public function fonts():String {
		for (where in [Paths.beside() + "/fonts", Sys.getCwd() + "/vendor/fonts",
				Paths.beside() + "/../../vendor/fonts"]) {
			if (sys.FileSystem.exists(where + "/Go-Regular.ttf")) {
				return haxe.io.Path.normalize(where);
			}
		}
		return "";
	}

	function paired(where:String):Int {
		if (typeface < 0 || typeface >= Typeface.COUNT) return 0;

		if (!sys.FileSystem.exists(where + "/" + Typeface.SANS[typeface])
			|| !sys.FileSystem.exists(where + "/" + Typeface.MONO[typeface])) return 0;

		return typeface;
	}

	public function faces(metrics:Metrics):Bool {
		final where = fonts();

		if (where == "") {
			Sys.println("mdd: no fonts found. Run: mdd setup");
			return false;
		}

		shed();

		final pairing = paired(where);
		final sans = where + "/" + Typeface.SANS[pairing];
		final fixed = where + "/" + Typeface.MONO[pairing];

		body = Font.bake(renderer, sans, 15 * scale);
		small = Font.bake(renderer, sans, 13 * scale);
		mono = Font.bake(renderer, fixed, 14 * scale);
		large = Font.bake(renderer, fixed, 21 * scale);

		if (body == null || small == null || mono == null || large == null) {
			Sys.println("mdd: the fonts would not bake");
			return false;
		}

		metrics.dress(body, small, mono, large);
		if (paint != null) paint.reface(body);
		return true;
	}

	function shed():Void {
		if (body != null) body.shut();
		if (small != null) small.shut();
		if (mono != null) mono.shut();
		if (large != null) large.shut();

		body = null;
		small = null;
		mono = null;
		large = null;
	}

	public function measured():Void {
		root.resize(Sdl.outputWidth(renderer), Sdl.outputHeight(renderer));
		shell.fit(root.metrics);
	}

	public function redressed():Void {
		if (!faces(root.metrics)) return;

		drawn();
		measured();
		root.reshape();
	}

	public function densified(much:Float):Void {
		root.rescale(scale * much);
		faces(root.metrics);
		drawn();
		measured();
	}

	public function rescaled():Void {
		final next = Sdl.windowDisplayScale(window);
		if (next == scale) return;

		scale = next;
		root.rescale(scale);
		faces(root.metrics);
		drawn();
		measured();
	}

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

			case Sdl.EVENT_MOUSE_MOVE:
				root.moved(event.x, event.y, event.mods);

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

			case _:
		}

		return true;
	}

	public function draw():Void {
		if (!root.stale()) {
			Sdl.sleep(IDLE);
			return;
		}

		final ground = root.theme.ground;
		Sdl.renderClear(renderer, ground.red / 255, ground.green / 255, ground.blue / 255, 1);
		root.frame(paint);
		Sdl.renderPresent(renderer);
	}

	public function shut():Void {
		if (icons != null) icons.shut();

		shed();
		Sdl.destroyRenderer(renderer);
		Sdl.destroyWindow(window);
	}
}
