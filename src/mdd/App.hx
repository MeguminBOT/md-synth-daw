package mdd;

import mdd.host.Audio;
import mdd.host.Canvas;
import mdd.host.Device;
import mdd.host.Event;
import mdd.host.Native;
import mdd.host.Paths;
import mdd.host.Sdl;
import mdd.host.Window;
import mdd.ui.Flow;
import mdd.ui.Font;
import mdd.ui.Metrics;
import mdd.ui.Paint;
import mdd.ui.Root;
import mdd.ui.Shell;
import mdd.ui.Theme;
import mdd.check.Budget;
import mdd.check.Profile;
import mdd.play.Render;
import mdd.song.Part;
import mdd.song.Song;
import mdd.view.Centre;
import mdd.view.ChannelRack;
import mdd.ui.Choice;
import mdd.ui.Menu;
import mdd.ui.MenuBar;
import mdd.view.Dock;
import mdd.view.Files;
import mdd.view.Inspector;
import mdd.view.Session;
import mdd.view.TransportBar;

@:unreflective
class App {
	static inline final IDLE = 0.002;

	var window:cpp.Star<Window>;
	var renderer:cpp.Star<Canvas>;

	var paint:Paint;
	var root:Root;
	var shell:Shell;

	var body:Null<Font> = null;
	var small:Null<Font> = null;
	var mono:Null<Font> = null;
	var large:Null<Font> = null;

	var session:Null<Session> = null;
	var rack:Null<ChannelRack> = null;
	var centre:Null<Centre> = null;
	var inspector:Null<Inspector> = null;
	var dock:Null<Dock> = null;
	var menus:Null<MenuBar> = null;
	var files:Null<Files> = null;
	var bar:Null<TransportBar> = null;
	var budget:Null<Budget> = null;

	var speaker:cpp.Star<Device> = null;
	var render:Null<Render> = null;

	var windowID:Int = 0;
	var scale:Float = 1;
	var running:Bool = true;
	var last:Float = 0;

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
		root.flow = Sdl.reduceMotion() != 0 ? Flow.Reduced : Flow.Full;

		if (!faces(metrics)) return false;

		paint = Paint.on(renderer, body);
		dress();
		measured();
		sound();

		Sdl.showWindow(window);
		return true;
	}

	function dress():Void {
		session = Session.started();

		bar = new TransportBar(session);
		rack = new ChannelRack(session);
		centre = new Centre(session);
		inspector = new Inspector(session);
		dock = new Dock(session);

		shell.zone(Shell.TRANSPORT).add(bar);
		shell.zone(Shell.RAIL).add(rack);
		shell.zone(Shell.CENTRE).add(centre);
		shell.zone(Shell.INSPECTOR).add(inspector);
		shell.zone(Shell.DOCK).add(dock);

		files = new Files(session);
		files.onLoad = function(song:Song):Void loaded(song);

		menus = new MenuBar();
		shell.zone(Shell.MENU).add(menus);

		commands();

		budget = new Budget(Profile.megaDrive());
		centre.roll.budget = budget;
		dock.warnings.budget = budget;

		session.onReveal = function(found:mdd.check.Diagnostic):Void revealed(found);
		session.say("ready");

		session.onChange = function(session:Session):Void changed();
		changed();
	}

	function changed():Void {
		if (budget == null || session == null) return;

		budget.overSong(session.song);

		if (centre != null) centre.roll.invalidate();
		if (inspector != null) inspector.follow();

		if (dock != null) {
			dock.warnings.fit();
			dock.said = session.said;
			dock.invalidate();
		}
	}

	function revealed(found:mdd.check.Diagnostic):Void {
		if (centre == null || found.note == null) return;

		centre.show(Centre.ROLL);
		centre.roll.reveal(found.note.at, found.note.pitch);
		centre.roll.choose(found.note);
	}

	function commands():Void {
		final file = new Menu();

		fired(file.offer(new Choice("Open", "Ctrl+O")), function():Void
			files.ask(window, Files.OPEN));
		fired(file.offer(new Choice("Save", "Ctrl+S")), function():Void
			files.ask(window, Files.SAVE));
		file.divide();
		fired(file.offer(new Choice("Export a vgm")), function():Void
			files.ask(window, Files.VGM));
		fired(file.offer(new Choice("Export a wav")), function():Void
			files.ask(window, Files.WAV));
		fired(file.offer(new Choice("Export a midi file")), function():Void
			files.ask(window, Files.MIDI));
		file.divide();
		fired(file.offer(new Choice("Quit", "Alt+F4")), function():Void running = false);

		final edit = new Menu();

		fired(edit.offer(new Choice("Undo", "Ctrl+Z")), function():Void undone());
		fired(edit.offer(new Choice("Redo", "Ctrl+Y")), function():Void redone());

		final view = new Menu();

		fired(view.offer(new Choice("Piano roll")), function():Void centre.show(Centre.ROLL));
		fired(view.offer(new Choice("Arrangement")), function():Void
			centre.show(Centre.PLAYLIST));
		view.divide();
		fired(view.offer(new Choice("Mixer")), function():Void dock.show(Dock.MIXER));
		fired(view.offer(new Choice("Warnings")), function():Void dock.show(Dock.WARNINGS));

		menus.offer("File", file);
		menus.offer("Edit", edit);
		menus.offer("View", view);
	}

	function fired(choice:Choice, what:Void -> Void):Void {
		choice.onFire = function(chosen:Choice):Void what();
	}

	function undone():Void {
		if (session.undo()) session.say("undone");
		else session.say("nothing to undo");

		session.changed();
	}

	function redone():Void {
		if (session.redo()) session.say("redone");
		else session.say("nothing to redo");

		session.changed();
	}

	function loaded(song:Song):Void {
		if (render != null) render.transport.stop();

		session = new Session(song);
		session.onChange = function(held:Session):Void changed();
		session.onReveal = function(found:mdd.check.Diagnostic):Void revealed(found);

		files = new Files(session);
		files.onLoad = function(held:Song):Void loaded(held);

		bar = new TransportBar(session);
		rack = new ChannelRack(session);
		centre = new Centre(session);
		inspector = new Inspector(session);
		dock = new Dock(session);
		menus = new MenuBar();

		for (which in [Shell.MENU, Shell.TRANSPORT, Shell.RAIL, Shell.CENTRE, Shell.INSPECTOR,
				Shell.DOCK]) {
			final zone = shell.zone(which);
			while (zone.children.length > 0) zone.remove(zone.children[0]);
		}

		shell.zone(Shell.MENU).add(menus);
		shell.zone(Shell.TRANSPORT).add(bar);
		shell.zone(Shell.RAIL).add(rack);
		shell.zone(Shell.CENTRE).add(centre);
		shell.zone(Shell.INSPECTOR).add(inspector);
		shell.zone(Shell.DOCK).add(dock);

		centre.roll.budget = budget;
		dock.warnings.budget = budget;

		commands();

		if (render != null) render.transport = session.transport;

		measured();
		changed();
	}

	function sound():Void {
		speaker = Audio.open(0, Render.BLOCK);
		if (speaker == null) return;

		render = new Render(Audio.rate(speaker), Render.BLOCK);
		render.transport = session.transport;
		render.start(speaker);
	}

	function faces(metrics:Metrics):Bool {
		final where = fonts();

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

	function fonts():String {
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
		Sys.println("  motion        " + (root.flow == Flow.Reduced ? "reduced, as the desktop asks"
			: "full"));
		Sys.println("  settings      " + Paths.settings());
		Sys.println("  audio         " + (speaker == null ? "no device"
			: Audio.name(speaker) + ", " + Audio.rate(speaker) + " Hz"));
		Sys.println("  profile       " + budget.profile.name + ", "
			+ budget.profile.counted() + " parts");
	}

	function loop():Void {
		final event = new Event();
		last = Sdl.ticks();

		while (running) {
			while (Sdl.pollEvent(cpp.Pointer.addressOf(event).raw) != 0) took(event);
			if (!running) break;

			final now = Sdl.ticks();
			var since = now - last;
			last = now;
			if (since > 0.100) since = 0.100;

			root.advance(since);
			if (files != null && files.poll()) root.soil();
			watch();
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
		faces(root.metrics);
		measured();
	}

	function watch():Void {
		if (session == null || centre == null || rack == null) return;

		centre.playhead(session.transport.tick());

		if (render == null) return;

		var moved = false;

		for (index in 0...Part.COUNT) {
			final was = rack.levels[index];
			final now = loudness(index);
			final held = now > was ? now : was * 0.86;

			if (Math.abs(held - was) > 0.01) moved = true;
			rack.levels[index] = held;
		}

		if (moved) rack.invalidate();

		if (dock != null && dock.mixer.visible) {
			for (index in 0...Part.COUNT) dock.mixer.levels[index] = rack.levels[index];
			if (moved) dock.mixer.invalidate();
		}

		if (inspector == null || !inspector.scope.visible) return;

		for (index in 0...6) inspector.scope.feed(index, traced(index));
		inspector.scope.invalidate();
	}

	function traced(index:Int):Float {
		return render.ym.channels[index].delivered / 3000.0;
	}

	function loudness(index:Int):Float {
		if (index >= 6) return 0;

		final value = render.ym.channels[index].delivered;
		final size = value < 0 ? -value : value;

		return size / 3000.0;
	}

	function draw():Void {
		if (!root.stale()) {
			Sdl.sleep(IDLE);
			return;
		}

		final ground = root.theme.ground;
		Sdl.renderClear(renderer, ground.red / 255, ground.green / 255, ground.blue / 255, 1);
		root.frame(paint);
		Sdl.renderPresent(renderer);
	}

	function shut():Void {
		if (render != null) render.stop();
		if (speaker != null) Audio.close(speaker);

		shed();
		Sdl.destroyRenderer(renderer);
		Sdl.destroyWindow(window);
	}
}
