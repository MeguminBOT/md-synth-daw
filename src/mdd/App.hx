package mdd;

import mdd.host.Canvas;
import mdd.host.Event;
import mdd.host.Native;
import mdd.host.Sdl;
import mdd.host.Window;

@:unreflective
class App {
	static inline final TITLE = "mdd";

	static inline final WIDTH = 1440;
	static inline final HEIGHT = 900;

	static inline final LEAST_WIDTH = 960;
	static inline final LEAST_HEIGHT = 600;

	static inline final BACKGROUND = 0x14181D;

	var window:cpp.Star<Window>;
	var renderer:cpp.Star<Canvas>;

	var windowID:Int = 0;
	var scale:Float = 1;
	var width:Int = 0;
	var height:Int = 0;

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
		window = Sdl.createWindow(TITLE, WIDTH, HEIGHT);
		if (window == null) {
			Sys.println("mdd: no window: " + Sdl.error());
			return false;
		}

		Sdl.setWindowMinimumSize(window, LEAST_WIDTH, LEAST_HEIGHT);
		windowID = Sdl.windowID(window);

		renderer = Sdl.createRenderer(window, 1);
		if (renderer == null) {
			Sys.println("mdd: no renderer: " + Sdl.error());
			Sdl.destroyWindow(window);
			return false;
		}

		measured();
		Sdl.showWindow(window);
		return true;
	}

	function measured():Void {
		scale = Sdl.windowDisplayScale(window);
		width = Sdl.windowPixelWidth(window);
		height = Sdl.windowPixelHeight(window);
	}

	function report():Void {
		Sys.println("  renderer      " + Sdl.rendererName(renderer));
		Sys.println("  vsync         " + Sdl.rendererVsync(renderer));
		Sys.println("  refresh       " + Sdl.displayRefresh(window) + " Hz");
		Sys.println("  window        " + Sdl.windowWidth(window) + "x" + Sdl.windowHeight(window));
		Sys.println("  pixels        " + width + "x" + height);
		Sys.println("  display scale " + scale);
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

			case Sdl.EVENT_WINDOW_RESIZED, Sdl.EVENT_WINDOW_SCALE_CHANGED:
				if (event.windowID == windowID) measured();

			case _:
		}
	}

	function draw():Void {
		Sdl.renderClear(renderer, ((BACKGROUND >> 16) & 0xFF) / 255, ((BACKGROUND >> 8) & 0xFF) / 255,
			(BACKGROUND & 0xFF) / 255, 1);
		Sdl.renderPresent(renderer);
	}

	function shut():Void {
		Sdl.destroyRenderer(renderer);
		Sdl.destroyWindow(window);
	}
}
