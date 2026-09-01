package mdd;

import mdd.host.Canvas;
import mdd.host.Event;
import mdd.host.Native;
import mdd.host.Paths;
import mdd.host.Sdl;
import mdd.host.Window;
import mdd.ui.Font;
import mdd.ui.Metrics;
import mdd.ui.Paint;
import mdd.ui.Root;
import mdd.ui.Shell;
import mdd.ui.Theme;

@:unreflective
class App {
	var window:cpp.Star<Window>;
	var renderer:cpp.Star<Canvas>;

	var paint:Paint;
	var root:Root;
	var shell:Shell;

	var body:Null<Font> = null;
	var small:Null<Font> = null;
	var mono:Null<Font> = null;
	var large:Null<Font> = null;

	var windowID:Int = 0;
	var scale:Float = 1;
	var running:Bool = true;

	function new() {}

	public static function main():Void {
		Native.ready();

		if (Sdl.init() == 0) {
			Sys.println("mdd: SDL would not start: " + Sdl.error());
			Sys.exit(1);
		}

		final app = new App();

		if (!app.open()) {
			Sdl.quit();
			Sys.exit(1);
		}

		app.report();
		app.loop();
		app.shut();
		Sdl.quit();
	}

	function open():Bool {
		window = Sdl.createWindow(Config.TITLE, Config.WIDTH, Config.HEIGHT,
			Config.RESIZABLE ? 1 : 0, Config.HIGH_DPI ? 1 : 0);

		if (window == null) {
			Sys.println("mdd: no window: " + Sdl.error());
			return false;
		}

		Sdl.setWindowMinimumSize(window, Config.LEAST_WIDTH, Config.LEAST_HEIGHT);
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

		if (!dress(metrics)) return false;

		paint = Paint.on(renderer, body);
		measured();

		Sdl.showWindow(window);
		return true;
	}

	function dress(metrics:Metrics):Bool {
		final where = faces();

		if (where == "") {
			Sys.println("mdd: no fonts found. Run: mdd setup");
			return false;
		}

		shed();

		body = Font.bake(renderer, where + "/Go-Regular.ttf", 13 * scale);
		small = Font.bake(renderer, where + "/Go-Regular.ttf", 11 * scale);
		mono = Font.bake(renderer, where + "/Go-Mono.ttf", 12 * scale);
		large = Font.bake(renderer, where + "/Go-Mono.ttf", 19 * scale);

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

	function faces():String {
		for (where in [Paths.beside() + "/fonts", Sys.getCwd() + "/vendor/fonts",
				Paths.beside() + "/../../vendor/fonts"]) {
			if (sys.FileSystem.exists(where + "/Go-Regular.ttf")) {
				return haxe.io.Path.normalize(where);
			}
		}
		return "";
	}

	function measured():Void {
		root.resize(Sdl.outputWidth(renderer), Sdl.outputHeight(renderer));
		shell.fit(root.metrics);
	}

	function report():Void {
		Sys.println("  " + Config.TITLE + " " + Config.VERSION);
		Sys.println("  renderer      " + Sdl.rendererName(renderer));
		Sys.println("  vsync         " + Sdl.rendererVsync(renderer));
		Sys.println("  refresh       " + Sdl.displayRefresh(window) + " Hz");
		Sys.println("  window        " + Sdl.windowWidth(window) + "x"
			+ Sdl.windowHeight(window) + " logical");
		Sys.println("  drawing at    " + Sdl.outputWidth(renderer) + "x"
			+ Sdl.outputHeight(renderer) + " native pixels");
		Sys.println("  pixel density " + Sdl.pixelDensity(window));
		Sys.println("  display scale " + scale);
		Sys.println("  settings      " + Paths.settings());
	}

	function loop():Void {
		final event = new Event();

		while (running) {
			while (Sdl.pollEvent(cpp.Pointer.addressOf(event).raw) != 0) took(event);
			if (!running) break;

			draw();
		}
	}

	function took(event:Event):Void {
		switch (event.type) {
			case Sdl.EVENT_QUIT:
				running = false;

			case Sdl.EVENT_WINDOW_CLOSE:
				if (event.windowID == windowID) running = false;

			case Sdl.EVENT_WINDOW_RESIZED:
				if (event.windowID == windowID) measured();

			case Sdl.EVENT_WINDOW_SCALE_CHANGED:
				if (event.windowID != windowID) return;
				rescaled();

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
	}

	function rescaled():Void {
		final next = Sdl.windowDisplayScale(window);
		if (next == scale) return;

		scale = next;
		root.rescale(scale);
		dress(root.metrics);
		measured();
	}

	function draw():Void {
		if (!root.stale()) {
			Sdl.renderPresent(renderer);
			return;
		}

		final ground = root.theme.ground;
		Sdl.renderClear(renderer, ground.red / 255, ground.green / 255, ground.blue / 255, 1);
		root.frame(paint);
		Sdl.renderPresent(renderer);
	}

	function shut():Void {
		shed();
		Sdl.destroyRenderer(renderer);
		Sdl.destroyWindow(window);
	}
}
