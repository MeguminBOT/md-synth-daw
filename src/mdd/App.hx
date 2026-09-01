package mdd;

import mdd.host.Audio;
import mdd.host.Canvas;
import mdd.host.Device;
import mdd.host.Event;
import mdd.host.Instance;
import mdd.host.Native;
import mdd.host.Paths;
import mdd.host.Settings;
import mdd.host.Update;
import mdd.host.Sdl;
import mdd.host.Window;
import mdd.ui.Flow;
import mdd.ui.Font;
import mdd.ui.Key;
import mdd.ui.Mod;
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
import mdd.ui.control.Choice;
import mdd.ui.control.Menu;
import mdd.ui.control.MenuBar;
import mdd.view.Dock;
import mdd.view.Files;
import mdd.view.Inspector;
import mdd.view.Notice;
import mdd.view.Preferences;
import mdd.view.Rail;
import mdd.view.Session;
import mdd.view.Locale;
import mdd.view.Languages;
import mdd.view.TransportBar;
import mdd.view.Welcome;

@:unreflective
class App {
	static inline final IDLE = 0.002;
	static inline final LOCK = "-running";
	static inline final ICON = 64;

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
	var rail:Null<Rail> = null;
	var rack:Null<ChannelRack> = null;
	var centre:Null<Centre> = null;
	var inspector:Null<Inspector> = null;
	var dock:Null<Dock> = null;
	var menus:Null<MenuBar> = null;
	var files:Null<Files> = null;
	var preferences:Null<Preferences> = null;
	var settings:Null<Settings> = null;
	var update:Null<Update> = null;
	var notice:Null<Notice> = null;
	var welcome:Null<Welcome> = null;
	var firstRun:Bool = false;
	var bar:Null<TransportBar> = null;
	var budget:Null<Budget> = null;

	var speaker:cpp.Star<Device> = null;
	var render:Null<Render> = null;

	var seen:Int = 0;
	var heard:Int = 0;
	final sounding:mdd.play.Sounding = new mdd.play.Sounding();
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

		if (Instance.claim(Config.SHORT + LOCK) == 0) {
			Sdl.message(Config.TITLE, Config.TITLE + " is already running.");
			Sdl.quit();
			Sys.exit(0);
		}

		final app = new App();

		if (!app.open()) {
			Instance.release();
			Sdl.quit();
			Sys.exit(1);
		}

		app.report();

		try {
			app.loop();
			app.shut();
		} catch (e:haxe.Exception) {
			recorded(e);
			Instance.release();
			Sdl.quit();
			Sys.exit(2);
		}

		Instance.release();
		Sdl.quit();
	}

	static function recorded(e:haxe.Exception):Void {
		final said = new StringBuf();

		said.add(Config.TITLE + " " + Config.VERSION + " stopped at " + Date.now() + "
");
		said.add(e.message + "

");
		said.add(haxe.CallStack.toString(e.stack) + "
");

		Sys.println("mdd: " + e.message);
		Sys.println(haxe.CallStack.toString(e.stack));

		try {
			final where = Paths.within("logs") + "/crash.txt";
			sys.io.File.saveContent(where, said.toString());
			Sys.println("mdd: written to " + where);
		} catch (held:haxe.Exception) {}
	}

	function open():Bool {
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
		dress();
		measured();
		sound();

		Sdl.showWindow(window);
		return true;
	}

	function faced():Void {
		final held = haxe.Resource.getBytes("icon");
		if (held == null || held.length != ICON * ICON * 4) return;

		Sdl.windowIcon(window, cpp.NativeArray.address(held.getData(), 0).constRaw, ICON, ICON);
	}

	function dress():Void {
		session = Session.started();

		bar = new TransportBar(session);
		rail = new Rail(session);
		rack = rail.rack;
		centre = new Centre(session);
		inspector = new Inspector(session);
		dock = new Dock(session);

		shell.zone(Shell.TRANSPORT).add(bar);
		shell.zone(Shell.RAIL).add(rail);
		shell.zone(Shell.CENTRE).add(centre);
		shell.zone(Shell.INSPECTOR).add(inspector);
		shell.zone(Shell.DOCK).add(dock);

		files = new Files(session);
		files.onLoad = function(song:Song):Void loaded(song);

		menus = new MenuBar();
		shell.zone(Shell.MENU).add(menus);


		preferences = new Preferences(session);
		preferences.onScale = function(much:Float):Void densified(much);
		preferences.onTypeface = function(which:Int):Void redressed();
		preferences.onKeep = function():Void keeps();
		preferences.onKeeping = function(every:Float):Void files.every = every;

		preferences.onSpeak = function(code:String):Void {
			Languages.speak(root.translation, code);
			settings.put("language", code);

			relabel();
			root.reshape();
		};

		update = new Update(Config.GITHUB, Config.VERSION);

		notice = new Notice(session);
		notice.update = update;
		notice.onTake = function():Void fetching();
		notice.onNever = function():Void {
			settings.flag("update", false);
			settings.save();
		};

		settings = new Settings();
		settings.load();

		firstRun = settings.of("language", "") == "";
		spoken();
		remembered();



		commands();
		root.onChord = function(code:Key, mods:Mod):Bool return chorded(code, mods);

		budget = new Budget(Profile.megaDrive());
		centre.roll.budget = budget;
		rail.hardware.budget = budget;
		centre.samples.budget = budget;
		centre.samples.onImport = function():Void files.ask(window, Files.READ_WAV);
		inspector.samples.onImport = function():Void files.ask(window, Files.READ_WAV);
		inspector.samples.budget = budget;
		dock.warnings.budget = budget;

		session.onReveal = function(found:mdd.check.Diagnostic):Void revealed(found);
		session.say(root.translate(Locale.READY));

		keeps();
		greeting();
		handed();

		session.onChange = function(session:Session):Void changed();
		changed();
	}

	function handed():Void {
		for (arg in Sys.args()) {
			if (StringTools.startsWith(arg, "-")) continue;
			if (!sys.FileSystem.exists(arg)) continue;

			opens(arg);
			return;
		}
	}

	public function opens(where:String):Void {
		final suffix = haxe.io.Path.extension(where).toLowerCase();

		try {
			switch (suffix) {
				case "vgm", "vgz": files.readVgm(where);
				case "mid", "midi": files.readMidi(where);
				case "wav": files.readWav(where);
				case _: files.load(where);
			}
		} catch (e:Dynamic) {
			session.say("that would not open: " + e);
		}

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

		fired(file.offer(new Choice(root.translate(Locale.FILE_OPEN), "Ctrl+O")), function():Void
			files.ask(window, Files.OPEN));
		fired(file.offer(new Choice(root.translate(Locale.FILE_SAVE), "Ctrl+S")), function():Void
			keeping());
		fired(file.offer(new Choice(root.translate(Locale.FILE_SAVE_AS))), function():Void
			files.ask(window, Files.SAVE));
		file.divide();

		final looking = file.offer(new Choice(root.translate(Locale.FILE_UPDATE)));

		if (update.possible()) fired(looking, function():Void looks());
		else {
			looking.enabled = false;
			looking.reason = root.translate(Locale.FILE_NO_UPDATE);
		}

		file.divide();
		fired(file.offer(new Choice(root.translate(Locale.FILE_PREFERENCES), "Ctrl+,")),
			function():Void opened());
		file.divide();
		fired(file.offer(new Choice(root.translate(Locale.FILE_QUIT), "Alt+F4")), function():Void
			running = false);

		final edit = new Menu();

		fired(edit.offer(new Choice(root.translate(Locale.EDIT_UNDO), "Ctrl+Z")), function():Void
			undone());
		fired(edit.offer(new Choice(root.translate(Locale.EDIT_REDO), "Ctrl+Y")), function():Void
			redone());
		edit.divide();
		fired(edit.offer(new Choice(root.translate(Locale.EDIT_PLAY), "Space")), function():Void
			bar.press(TransportBar.PLAY));
		fired(edit.offer(new Choice(root.translate(Locale.EDIT_STOP), "Ctrl+Space")),
			function():Void bar.press(TransportBar.STOP));

		menus.offer(root.translate(Locale.MENU_FILE), file);
		menus.offer(root.translate(Locale.MENU_EDIT), edit);
		menus.offer(root.translate(Locale.MENU_PATTERN), patternMenu());
		menus.offer(root.translate(Locale.MENU_CHANNELS), channelsMenu());
		menus.offer(root.translate(Locale.MENU_INSTRUMENT), instrumentMenu());
		menus.offer(root.translate(Locale.MENU_IMPORT), importMenu());
		menus.offer(root.translate(Locale.MENU_EXPORT), exportMenu());
		menus.offer(root.translate(Locale.MENU_VIEW), viewMenu());
		menus.offer(root.translate(Locale.MENU_HELP), helpMenu());

		menus.trailing.resize(0);
		menus.trailing.push(root.translate(Locale.FILE_OPEN));
		menus.trailing.push(root.translate(Locale.FILE_SAVE));
		menus.trailing.push(root.translate(Locale.FILE_PREFERENCES));

		menus.onTrailing = function(which:Int):Void {
			switch (which) {
				case 0: files.ask(window, Files.OPEN);
				case 1: keeping();
				case _: opened();
			}
		};
	}

	function patternMenu():Menu {
		final held = new Menu();

		fired(held.offer(new Choice(root.translate(Locale.PATTERN_ADD))), function():Void
			dock.patterns.added());
		fired(held.offer(new Choice(root.translate(Locale.PATTERN_DUPLICATE))), function():Void
			dock.patterns.duplicated(session.pattern));
		fired(held.offer(new Choice(root.translate(Locale.PATTERN_RENAME))), function():Void
			dock.patterns.renamed(session.pattern));
		fired(held.offer(new Choice(root.translate(Locale.PATTERN_INSERT))), function():Void
			dock.patterns.inserted(session.pattern));
		fired(held.offer(new Choice(root.translate(Locale.PATTERN_DELETE))), function():Void
			dock.patterns.dropped(session.pattern));
		held.divide();
		fired(held.offer(new Choice(root.translate(Locale.PATTERN_CLEAR))), function():Void
			emptied());
		held.divide();
		fired(held.offer(new Choice(root.translate(Locale.VIEW_PATTERNS))), function():Void
			dock.show(Dock.PATTERNS));

		return held;
	}

	function channelsMenu():Menu {
		final held = new Menu();

		fired(held.offer(new Choice(root.translate(Locale.CHANNELS_UNMUTE))), function():Void {
			for (index in 0...Part.COUNT) session.song.muted[index] = false;
			session.changed();
		});

		fired(held.offer(new Choice(root.translate(Locale.CHANNELS_UNSOLO))), function():Void {
			for (index in 0...Part.COUNT) session.song.soloed[index] = false;
			session.changed();
		});

		held.divide();

		fired(held.offer(new Choice(root.translate(Locale.CHANNELS_MUTE_REST))), function():Void {
			final which = session.part.index();
			for (index in 0...Part.COUNT) session.song.muted[index] = index != which;
			session.changed();
		});

		held.divide();
		fired(held.offer(new Choice(root.translate(Locale.CHANNELS_CLEAR))), function():Void
			cleared());

		return held;
	}

	function instrumentMenu():Menu {
		final held = new Menu();

		final copy = held.offer(new Choice(root.translate(Locale.RACK_COPY_PATCH)));
		final paste = held.offer(new Choice(root.translate(Locale.RACK_PASTE_PATCH)));
		final reset = held.offer(new Choice(root.translate(Locale.RACK_RESET_PATCH)));

		fired(copy, function():Void copiedPatch());
		fired(paste, function():Void pastedPatch());
		fired(reset, function():Void resetPatch());

		paste.enabled = session.copiedPatch != null;
		if (!paste.enabled) paste.reason = root.translate(Locale.RACK_NONE_COPIED);

		held.divide();
		fired(held.offer(new Choice(root.translate(Locale.PANEL_BANK))), function():Void
			inspector.show(Inspector.BANK));

		return held;
	}

	function importMenu():Menu {
		final held = new Menu();

		fired(held.offer(new Choice(root.translate(Locale.FILE_READ_VGM))), function():Void
			files.ask(window, Files.READ_VGM));
		fired(held.offer(new Choice(root.translate(Locale.FILE_READ_MIDI))), function():Void
			files.ask(window, Files.READ_MIDI));
		fired(held.offer(new Choice(root.translate(Locale.FILE_READ_WAV))), function():Void
			files.ask(window, Files.READ_WAV));

		return held;
	}

	function exportMenu():Menu {
		final held = new Menu();

		fired(held.offer(new Choice(root.translate(Locale.FILE_VGM), "Ctrl+E")), function():Void
			files.ask(window, Files.VGM));
		fired(held.offer(new Choice(root.translate(Locale.FILE_WAV))), function():Void
			files.ask(window, Files.WAV));
		fired(held.offer(new Choice(root.translate(Locale.FILE_MIDI))), function():Void
			files.ask(window, Files.MIDI));

		return held;
	}

	function viewMenu():Menu {
		final held = new Menu();

		fired(held.offer(new Choice(root.translate(Locale.VIEW_ROLL))), function():Void
			centre.show(Centre.ROLL));
		fired(held.offer(new Choice(root.translate(Locale.VIEW_SCOPE))), function():Void
			centre.show(Centre.SCOPE));
		fired(held.offer(new Choice(root.translate(Locale.VIEW_SAMPLES))), function():Void
			centre.show(Centre.SAMPLES));
		fired(held.offer(new Choice(root.translate(Locale.VIEW_TRACKER))), function():Void
			centre.show(Centre.TRACKER));
		fired(held.offer(new Choice(root.translate(Locale.VIEW_PLAYLIST))), function():Void
			centre.show(Centre.PLAYLIST));
		fired(held.offer(new Choice(root.translate(Locale.VIEW_REGISTERS))), function():Void
			centre.show(Centre.REGISTERS));
		held.divide();
		fired(held.offer(new Choice(root.translate(Locale.VIEW_PATTERNS))), function():Void
			dock.show(Dock.PATTERNS));
		fired(held.offer(new Choice(root.translate(Locale.VIEW_MIXER))), function():Void
			dock.show(Dock.MIXER));
		fired(held.offer(new Choice(root.translate(Locale.VIEW_WARNINGS))), function():Void
			dock.show(Dock.WARNINGS));

		return held;
	}

	function helpMenu():Menu {
		final held = new Menu();

		fired(held.offer(new Choice(root.translate(Locale.HELP_ABOUT))), function():Void
			session.say(Config.TITLE + " " + Config.VERSION + ", "
				+ session.song.patterns.length + " patterns"));

		final source = held.offer(new Choice(root.translate(Locale.HELP_SOURCE)));

		if (update.possible()) {
			fired(source, function():Void session.say("https://github.com/" + Config.GITHUB));
		} else {
			source.enabled = false;
			source.reason = root.translate(Locale.FILE_NO_UPDATE);
		}

		return held;
	}

	function emptied():Void {
		final held = session.current();
		if (held == null) return;

		for (index in 0...Part.COUNT) {
			final part:Part = index;
			final lane = held.lane(part);

			while (lane.notes.length > 0) {
				session.does(new mdd.song.edit.RemoveNote(session.pattern, part, lane.notes[0]));
			}
		}
	}

	function cleared():Void {
		final held = session.current();
		if (held == null) return;

		final lane = held.lane(session.part);

		while (lane.notes.length > 0) {
			session.does(new mdd.song.edit.RemoveNote(session.pattern, session.part,
				lane.notes[0]));
		}
	}

	function copiedPatch():Void {
		final held = session.song.instrumentAt(session.song.rack[session.part.index()]);
		if (held == null || held.patch == null) return;

		session.copiedPatch = held.patch.copy();
		session.say(root.translate(Locale.RACK_COPY_PATCH));
		session.changed();
	}

	function pastedPatch():Void {
		final held = session.song.instrumentAt(session.song.rack[session.part.index()]);
		if (held == null || session.copiedPatch == null) return;

		held.patch = session.copiedPatch.copy();
		session.changed();
	}

	function resetPatch():Void {
		final held = session.song.instrumentAt(session.song.rack[session.part.index()]);
		if (held == null) return;

		held.patch = new mdd.song.Patch();
		session.changed();
	}

	function looks():Void {
		if (!update.look()) {
			session.say(update.state() == Update.LOOKING ? "already looking"
				: "no update address is configured");
			session.changed();
			return;
		}

		session.say(root.translate(Locale.UPDATE_LOOKING));
		session.changed();
	}

	function fetching():Void {
		final into = Paths.within("updates") + "/" + Config.SHORT + "-" + update.offered
			+ Paths.suffix();

		if (update.take(into)) session.say("downloading to " + into);
		else session.say("that update cannot be downloaded");

		session.changed();
	}

	function watched():Bool {
		if (update == null) return false;

		switch (update.state()) {
			case Update.WAITING:
				if (root.sheet == notice) return false;

				notice.arrive();
				root.raise(notice);
				return true;

			case Update.CURRENT:
				if (session.said == root.translate(Locale.UPDATE_LOOKING)) {
					session.say(root.translate(Locale.UPDATE_CURRENT));
					session.changed();
					return true;
				}
				return false;

			case Update.UNREACHABLE:
				update.forget();
				session.say(root.translate(Locale.UPDATE_UNREACHABLE));
				session.changed();
				return true;

			case Update.FETCHED:
				update.forget();
				session.say(root.translate(Locale.UPDATE_FETCHED) + " " + update.into);
				session.changed();
				return true;

			case _:
				return false;
		}
	}

	function spoken():Void {
		final held = settings.of("language", "");
		final code = held != "" && Languages.known(held) ? held : Languages.guessed();

		Languages.speak(root.translation, code);
		preferences.speaks(Languages.shipped(), code);
	}

	function greeting():Void {
		if (!firstRun) return;

		welcome = new Welcome(session);

		welcome.onChoose = function(code:String):Void {
			Languages.speak(root.translation, code);
			preferences.speaks(Languages.shipped(), code);

			relabel();
			root.reshape();
		};

		welcome.onStart = function(code:String):Void {
			settings.put("language", code);
			settings.save();

			root.lower();
			session.changed();
		};

		welcome.arrive(root.translation.language);
		root.raise(welcome);
	}

	function relabel():Void {
		final zone = shell.zone(Shell.MENU);
		while (zone.children.length > 0) zone.remove(zone.children[0]);

		menus = new MenuBar();
		zone.add(menus);

		commands();
	}

	function remembered():Void {
		final which = settings.asWhole("theme", 0);
		final typeface = settings.asWhole("typeface", 0);
		final motion = settings.asWhole("motion", root.flow);
		final density = settings.asWhole("density", 1);
		final keeping = settings.asWhole("keeping", 2);
		if (settings.asFlag("update", true) && update.possible()) update.look();

		session.theme = which;
		session.motion = motion;
		session.typeface = typeface;

		root.theme.wear(which);
		root.flow = motion;

		if (typeface != 0) redressed();

		preferences.chose(Preferences.DENSITY, density);
		preferences.chose(Preferences.KEEPING, keeping);
		root.reshape();
	}

	function keeps():Void {
		if (settings == null) return;

		settings.whole("theme", session.theme);
		settings.whole("typeface", session.typeface);
		settings.whole("motion", session.motion);
		settings.whole("density", preferences.density);
		settings.whole("keeping", preferences.keeping);
		settings.whole("width", Sdl.windowWidth(window));
		settings.whole("height", Sdl.windowHeight(window));
		settings.put("song", files == null ? "" : files.path);
		settings.put("language", root.translation.language);

		settings.save();
	}

	function opened():Void {
		preferences.arrive();
		root.raise(preferences);
	}

	function redressed():Void {
		if (!faces(root.metrics)) return;

		measured();
		root.reshape();
	}

	function densified(much:Float):Void {
		root.rescale(scale * much);
		faces(root.metrics);
		measured();
	}

	function chorded(code:Key, mods:Mod):Bool {
		final ctrl = (mods & Mod.Ctrl) != 0;
		final shift = (mods & Mod.Shift) != 0;

		if (code == Key.Space) {
			bar.press(ctrl ? TransportBar.STOP : TransportBar.PLAY);
			return true;
		}

		if (!ctrl) return false;

		switch (code) {
			case Key.Z:
				if (shift) redone();
				else undone();
				return true;

			case Key.Y:
				redone();
				return true;

			case Key.L:
				bar.press(TransportBar.LOOP);
				return true;

			case Key.S:
				keeping();
				return true;

			case Key.O:
				files.ask(window, Files.OPEN);
				return true;

			case Key.E:
				files.ask(window, Files.VGM);
				return true;

			case Key.Comma:
				opened();
				return true;

			case _:
		}

		return false;
	}

	function keeping():Void {
		if (files.path == "") {
			files.ask(window, Files.SAVE);
			return;
		}

		try {
			files.save(files.path);
		} catch (e:Dynamic) {
			session.say(root.translate(Locale.SAID_FAILED) + ": " + e);
		}

		session.changed();
	}

	function fired(choice:Choice, what:Void -> Void):Void {
		choice.onFire = function(chosen:Choice):Void what();
	}

	function undone():Void {
		if (session.undo()) session.say(root.translate(Locale.SAID_UNDONE));
		else session.say(root.translate(Locale.SAID_NOTHING_UNDO));

		session.changed();
	}

	function redone():Void {
		if (session.redo()) session.say(root.translate(Locale.SAID_REDONE));
		else session.say(root.translate(Locale.SAID_NOTHING_REDO));

		session.changed();
	}

	function loaded(song:Song):Void {
		if (render != null) render.transport.stop();

		final carried = files == null ? null : files.imported;

		session = new Session(song);
		session.onChange = function(held:Session):Void changed();
		session.onReveal = function(found:mdd.check.Diagnostic):Void revealed(found);

		files = new Files(session);
		files.onLoad = function(held:Song):Void loaded(held);

		bar = new TransportBar(session);
		rail = new Rail(session);
		rack = rail.rack;
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
		shell.zone(Shell.RAIL).add(rail);
		shell.zone(Shell.CENTRE).add(centre);
		shell.zone(Shell.INSPECTOR).add(inspector);
		shell.zone(Shell.DOCK).add(dock);

		centre.roll.budget = budget;
		rail.hardware.budget = budget;
		centre.samples.budget = budget;
		centre.samples.onImport = function():Void files.ask(window, Files.READ_WAV);
		inspector.samples.onImport = function():Void files.ask(window, Files.READ_WAV);
		inspector.samples.budget = budget;
		dock.warnings.budget = budget;

		commands();

		session.transport.source = carried;

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

	static final PAIRINGS:Array<Array<String>> = [
		["Go-Regular.ttf", "Go-Mono.ttf"],
		["IBMPlexSans.ttf", "IBMPlexMono.ttf"],
		["Inter.ttf", "JetBrainsMono.ttf"],
		["BarlowSemiCondensed.ttf", "IBMPlexMono.ttf"]
	];

	function paired(where:String):Array<String> {
		final which = session == null ? 0 : session.typeface;
		final held = which < 0 || which >= PAIRINGS.length ? PAIRINGS[0] : PAIRINGS[which];

		for (name in held) {
			if (!sys.FileSystem.exists(where + "/" + name)) return PAIRINGS[0];
		}

		return held;
	}

	function faces(metrics:Metrics):Bool {
		final where = fonts();

		if (where == "") {
			Sys.println("mdd: no fonts found. Run: mdd setup");
			return false;
		}

		shed();

		final pairing = paired(where);
		final sans = where + "/" + pairing[0];
		final fixed = where + "/" + pairing[1];

		body = Font.bake(renderer, sans, 13 * scale);
		small = Font.bake(renderer, sans, 11 * scale);
		mono = Font.bake(renderer, fixed, 12 * scale);
		large = Font.bake(renderer, fixed, 19 * scale);

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
		Sys.println("  userdata      " + Paths.userdata()
			+ (settings.portable ? ", portable" : ""));
		Sys.println("  audio         " + (speaker == null ? "no device"
			: Audio.name(speaker) + ", " + Audio.rate(speaker) + " Hz"));
		Sys.println("  profile       " + budget.profile.name + ", "
			+ budget.profile.counted() + " parts");
		Sys.println("  remembered    " + settings.read + " settings from "
			+ (settings.portable ? "beside the program" : "the settings directory"));
		Sys.println("  saving        " + (files.every <= 0 ? "only when asked"
			: "on its own every " + Std.int(files.every / 60) + " minutes"));
		Sys.println("  updates       " + (update.possible()
			? "github " + update.repository : "no repository configured, never looks"));
		Sys.println("  language      " + root.translation.language + ", " + root.translation.count()
			+ " strings of " + Languages.shipped().length + " shipped languages");
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
			if (files != null && files.tick(since)) root.soil();
			if (watched()) root.soil();
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

		heard = sounding.take(session.transport.stream, heard);

		if (centre.roll.visible) centre.roll.lights(sounding);

		if (centre.registers.visible) {
			seen = centre.registers.take(session.transport.stream, seen);
		}

		if (!centre.scope.visible) return;

		for (index in 0...6) centre.scope.feed(index, traced(index));

		for (index in 0...mdd.song.Part.COUNT) {
			centre.scope.sang(index, sounding.keyed[index] ? sounding.notes[index] : -1);
		}

		centre.scope.invalidate();
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
		keeps();

		if (render != null) render.stop();
		if (speaker != null) Audio.close(speaker);

		shed();
		Sdl.destroyRenderer(renderer);
		Sdl.destroyWindow(window);
	}
}
