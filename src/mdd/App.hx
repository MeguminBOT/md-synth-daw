package mdd;

import mdd.app.Bindings;
import mdd.app.Files;
import mdd.app.Keyboard;
import mdd.app.Mapping;
import mdd.app.Languages;
import mdd.app.Locale;
import mdd.app.Menus;
import mdd.app.Panels;
import mdd.app.Presence;
import mdd.app.Session;
import mdd.app.Task;
import mdd.app.Sound;
import mdd.app.Stage;
import mdd.app.Update;
import mdd.host.Audio;
import mdd.host.Collector;
import mdd.host.Crash;
import mdd.host.Event;
import mdd.host.Instance;
import mdd.host.Native;
import mdd.host.Paths;
import mdd.host.Sdl;
import mdd.host.Usage;
import mdd.host.Settings;
import mdd.ui.Flow;
import mdd.ui.Key;
import mdd.ui.Mod;
import mdd.ui.Translation;
import mdd.song.Part;
import mdd.song.Song;
import mdd.view.TransportBar;
import mdd.view.overlay.Export;
import mdd.view.overlay.Naming;
import mdd.view.overlay.Notice;
import mdd.view.overlay.Preferences;
import mdd.view.overlay.Welcome;
import mdd.view.overlay.Working;

@:unreflective

/**
	The application: the frame loop, and the wiring between every part of it.

	It owns the window, the session, the sound, the panels, the menus, the file
	operations and the updater, and it is where they are told about each other. It has
	no logic of its own beyond that: what a thing does lives in the thing.
**/
class App {
	static inline final LOCK = "-running";

	final stage:Stage = new Stage();
	final library:mdd.song.Library = mdd.song.Library.embedded();
	final keyboard:Keyboard = new Keyboard();
	final sound:Sound = new Sound();

	var panels:Null<Panels> = null;
	var menus:Null<Menus> = null;

	var session:Null<Session> = null;
	var files:Null<Files> = null;
	var settings:Null<Settings> = null;
	var update:Null<Update> = null;

	var firstRun:Bool = false;
	var asking:cpp.Star<mdd.host.Chooser> = null;
	var asked:Int = -1;

	final task:Task = new Task();
	final bounce:Task = new Task();
	final progress:Working = new Working();
	final presence:Presence = new Presence();

	var rendering:Null<mdd.play.Mixdown> = null;
	var running:Bool = true;
	var last:Float = 0;

	/**
		Private: the application is started by `main`.
	**/
	function new() {}

	public static function main():Void {
		Native.ready();
		Usage.start();

		if (Sdl.init() == 0) {
			Sys.println("mdd: SDL would not start: " + Sdl.error());
			Sys.exit(1);
		}

		Crash.watch(Paths.within("logs") + "/fault.txt",
			Config.TITLE + " " + Config.VERSION, true);

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
		app.forced();

		try {
			app.loop();
			app.shut();
		} catch (e:haxe.Exception) {
			recorded(e);
			Instance.release();
			Sdl.quit();
			Sys.exit(2);
		}

		mdd.host.Midi.close();

		Usage.stop();
		Instance.release();
		Sdl.quit();
	}

	static function recorded(e:haxe.Exception):Void {
		final said = new StringBuf();

		said.add(Config.TITLE + " " + Config.VERSION + " stopped at " + Date.now() + "\n");
		said.add(e.message + "\n\n");
		said.add(haxe.CallStack.toString(e.stack) + "\n");

		Sys.println("mdd: " + e.message);
		Sys.println(haxe.CallStack.toString(e.stack));

		try {
			final where = Paths.within("logs") + "/crash.txt";
			sys.io.File.saveContent(where, said.toString());
			Sys.println("mdd: written to " + where);
		} catch (held:haxe.Exception) {}
	}

	/**
		Which renderer backend Windows is pinned to. All six SDL backends open a window and
		paint a still interface correctly; the fault in two of them appears only once the
		transport is running and the playhead, the scope and the meters are redrawing every
		frame. The choice sits behind a platform gate rather than being deleted, because
		the plumbing is right and only the backends are not.
	**/
	public static inline final PINNED = #if windows "direct3d11" #else "" #end;

	static final DRIVERS:Array<String> = ["--dx11", "direct3d11", "--d3d11", "direct3d11",
		"--dx12", "direct3d12", "--d3d12", "direct3d12", "--vulkan", "vulkan",
		"--opengl", "opengl", "--opengles", "opengles2", "--software", "software"];

	public static function flagged(args:Array<String>):String {
		for (index in 0...DRIVERS.length >> 1) {
			if (args.indexOf(DRIVERS[index * 2]) >= 0) return DRIVERS[index * 2 + 1];
		}

		for (arg in args) {
			if (StringTools.startsWith(arg, "--renderer=")) return arg.substr(11);
		}

		return "";
	}

	public static function offered():Array<String> {
		final out:Array<String> = [];

		for (index in 0...Sdl.renderDrivers()) {
			final name = (Sdl.renderDriver(index) : String);
			if (name != "") out.push(name);
		}

		return out;
	}

	/**
		Opens the window, the sound and the session, and reads the settings back.

		@return False where any of that would not work.
	**/
	function open():Bool {
		final args = Sys.args();

		settings = new Settings();

		if (args.indexOf("--reset") >= 0) {
			settings.forget();
			Sys.println("  settings      reset to defaults");
		} else {
			settings.load();
		}

		#if windows
		stage.driver = PINNED;
		#else
		final asked = flagged(args);
		final held = asked != "" ? asked : settings.of("renderer", "");

		stage.driver = held != "" && offered().indexOf(held) >= 0 ? held : "";
		#end

		if (!stage.open()) return false;

		stage.onDrop = function(where:String):Void opens(where);

		dress();
		stage.measured();
		sound.open(session.transport);

		stage.show(settings == null || settings.asFlag("maximised", true));
		collector.minds();
		return true;
	}

	/**
		Builds the panels and the menus and wires every callback between them.
	**/
	function dress():Void {
		library.within(mdd.host.Paths.within("presets"),
			stage.root.translate(Locale.PRESET_SAVED));

		session = Session.started(library);
		presence.follows(session);

		panels = new Panels(stage);
		panels.dress(session);

		files = new Files(session);
		files.onLoad = function(song:Song):Void loaded(song);
		panels.onImportSample = function():Void files.ask(stage.window, Files.READ_WAV);

		panels.naming = new Naming();
		panels.naming.onShut = function():Void stage.root.lower();

		panels.working = new Working();

		panels.about = new mdd.view.overlay.About();
		panels.about.onShut = function():Void stage.root.lower();

		panels.onMaster = function(much:Int):Void {
			sound.monitors(Session.gainOf(much));
			keeps();
		};

		files.onBusy = function(label:Locale, detail:String):Void busy(label, detail);
		files.onIdle = function():Void idle();
		files.onRender = function(where:String):Void renders(where);

		panels.exporting = new Export(session);
		panels.exporting.onShut = function():Void stage.root.lower();

		panels.exporting.onExport = function(mixing:mdd.play.Mixing):Void {
			files.mixing = mixing;
			files.ask(stage.window, Files.AUDIO);
		};

		panels.importing = new mdd.view.overlay.Importing();
		panels.importing.onShut = function():Void stage.root.lower();

		panels.importing.onImport = function(strands:Array<mdd.format.Strand>):Void {
			final instead = panels.importing.lands == mdd.view.overlay.Importing.INSTEAD;

			files.takesMidi(strands, instead);
			changed();
		};

		files.onSurvey = function(called:String,
				strands:Array<mdd.format.Strand>):Void panels.surveyed(called, strands);

		panels.preferences = new Preferences(session);
		panels.preferences.onScale = function(much:Float):Void stage.densified(much);
		panels.preferences.onTypeface = function(which:Int):Void redressed();
		panels.preferences.onKeep = function():Void keeps();
		panels.preferences.onKeeping = function(every:Float):Void files.every = every;
		panels.preferences.onBackups = function():Void backing();
		panels.preferences.onAutomating = function(which:Int):Void keeps();
		panels.preferences.onUpdates = function(on:Bool):Void {
			settings.flag("update", on);
			settings.save();
		};

		panels.preferences.onFolder = function(row:Int):Void folder(row);

		panels.preferences.onPresence = function(which:Int):Void {
			presence.level = which;
			presence.tick(Presence.DIAL_EVERY);
		};

		panels.preferences.onTempo = function(which:Int):Void {
			panels.bar.regrids = which != 0;
			keeps();
		};

		panels.preferences.onConsole = function(which:Int):Void {
			consoled(which);
			keeps();
		};

		panels.preferences.onKeyboard = function(which:Int):Void {
			final names = panels.preferences.keyboards;
			listens(which <= 0 || which >= names.length ? "" : names[which]);

			session.say(midiAt < 0 ? stage.root.translate(Locale.MIDI_NONE) : midiSaid);
			keeps();
		};

		panels.preferences.onKeyboardChannel = function(which:Int):Void {
			keyboard.channel = which <= 0 ? Keyboard.ANY : which - 1;
			keeps();
		};

		panels.preferences.onKeyboardVelocity = function(which:Int):Void {
			keyboard.forces = which != 0;
			keeps();
		};
		panels.preferences.onShut = function():Void stage.root.lower();
		panels.preferences.bindings = bindings;
		panels.preferences.mapping = mapping;

		panels.preferences.onRemap = function():Void keeps();

		panels.preferences.onRebind = function():Void {
			relabel();
			bound();
			keeps();
		};

		panels.preferences.onSpeak = function(code:String):Void {
			Languages.speak(stage.root.translation, code);
			settings.put("language", code);

			relabel();
			stage.root.reshape();
		};

		panels.preferences.onRenderer = function(name:String):Void {
			settings.put("renderer", name);
			settings.save();

			session.say(stage.root.translate(Locale.RENDERER_RESTART));
		};

		#if !windows
		panels.preferences.draws(offered(), stage.driver);
		#end

		update = new Update(Config.GITHUB, Config.VERSION);

		panels.notice = new Notice(session);
		panels.notice.update = update;
		panels.notice.onTake = function():Void fetching();
		panels.notice.onNever = function():Void {
			settings.flag("update", false);
			settings.save();
		};

		firstRun = settings.of("language", "") == "";
		spoken();
		remembered();

		menus = new Menus(stage, panels);
		menus.update = update;
		menus.onAsk = function(which:Int):Void files.ask(stage.window, which);
		menus.onSave = function():Void keeping();
		menus.onQuit = function():Void running = false;
		menus.onRelabel = function():Void relabel();
		menus.onUndo = function():Void undone();
		menus.onRedo = function():Void redone();
		menus.onLift = function():Int return files.liftsPatches();
		menus.bindings = bindings;
		bound();

		menus.onNew = function():Void fresh();
		menus.onEdit = function(what:Int):Void edited(what);

		menus.onPart = function(part:Int):Void {
			session.does(new mdd.song.edit.MovePattern(session.pattern, part));

			final held:mdd.song.Part = part;
			session.say(stage.root.translate(Locale.PATTERN_PART) + " " + held.name());
		};

		menus.onNudge = function(way:Int):Void {
			session.does(new mdd.song.edit.ShiftSong(way));
			session.say(stage.root.translate(way < 0 ? Locale.EDIT_EARLIER : Locale.EDIT_LATER));
		};
		menus.dress(session);

		stage.root.onShortcut = function(code:Key, mods:Mod):Bool return commanded(code, mods);

		stage.root.onTyping = function(on:Bool):Void {
			if (on) Sdl.startTextInput(stage.window);
			else Sdl.stopTextInput(stage.window);
		};

		session.onReveal = function(found:mdd.check.Diagnostic):Void revealed(found);
		session.say(stage.root.translate(Locale.READY));

		keeps();
		greeting();
		handed();

		session.onChange = function(held:Session):Void changed();
		changed();
	}

	public function forced():Void {
		for (arg in Sys.args()) {
			if (!StringTools.startsWith(arg, "--export=")) continue;

			final where = arg.substr(9);
			if (where == "") continue;

			Sys.println("  forcing an export to " + where);
			renders(where);

			return;
		}

		if (Sys.args().indexOf("--exporting") >= 0) panels.sounded();
	}

	/**
		Opens whatever file the application was started with.
	**/
	function handed():Void {
		for (arg in Sys.args()) {
			if (StringTools.startsWith(arg, "-")) continue;
			if (!sys.FileSystem.exists(arg)) continue;

			opens(arg);
			return;
		}
	}

	/**
		Opens a file of any kind this reads, picked by its suffix. Anything else is
		read as a piece.

		@param where The file.
	**/
	public function opens(where:String):Void {
		final suffix = haxe.io.Path.extension(where).toLowerCase();

		try {
			switch (suffix) {
				case "vgm", "vgz": files.readVgm(where);
				case "xgm": files.readXgm(where);
				case "mid", "midi": files.readMidi(where);
				case "wav": files.readWav(where);
				case "tfi": files.readTfi(where);
				case _: files.load(where);
			}
		} catch (e:Dynamic) {
			session.says(Locale.SAID_OPEN_FAILED, "" + e);
		}

		changed();
	}

	/**
		Takes a piece that has just been read: points the session, the sound, the
		panels and the file operations at it rather than building new ones, because a
		rebuilt object silently drops every callback nobody re-attached.

		@param song The piece.
	**/
	function loaded(song:Song):Void {
		final held = session == null ? Session.UNITY : session.master;
		final automates = session == null ? Session.LANES : session.automating;
		final snaps = session == null ? Session.SIXTEENTH : session.snapping;

		sound.stop();

		library.into(song);

		session = new Session(song);
		presence.follows(session);
		session.onChange = function(held:Session):Void changed();
		session.onReveal = function(found:mdd.check.Diagnostic):Void revealed(found);

		files.follows(session);

		session.master = held;
		session.automating = automates;
		session.snapping = snaps;

		panels.dress(session);
		menus.dress(session);
		bound();

		session.transport.silence();
		sound.follows(session.transport);

		stage.measured();
		changed();

		collector.sweeps(true);
	}

	/**
		Redraws and rechecks whatever the session says has moved.
	**/
	function changed():Void {
		if (panels == null || panels.budget == null || session == null) return;

		panels.budget.overSong(session.song);

		if (panels.centre != null) panels.centre.roll.invalidate();
		if (panels.inspector != null) panels.inspector.follow();

		if (panels.status != null) {
			panels.centre.warnings.fit();
			panels.status.said = saying();
			panels.status.invalidate();
		}
	}

	/**
		Shows the note a warning is about, which is what clicking one does.

		@param found The warning.
	**/
	function revealed(found:mdd.check.Diagnostic):Void {
		if (panels.centre == null || found.note == null) return;

		panels.centre.show(mdd.view.Centre.ROLL);
		panels.centre.roll.reveal(found.note.at, found.note.pitch);
		panels.centre.roll.choose(found.note);
	}

	/**
		Starts downloading an update and raises the progress bar over it.
	**/
	function fetching():Void {
		final into = Paths.within("updates") + "/" + update.named();

		if (!update.take(into)) {
			session.says(Locale.SAID_UPDATE_NO_DOWNLOAD);
			session.changed();
			return;
		}

		shows(Locale.WORKING_DOWNLOADING, Files.name(into));
		session.changed();
	}

	/**
		Puts the progress bar up in the band, which is the one slot nothing else can
		claim.

		@param label What the task is called.
		@param detail A second line.
	**/
	function shows(label:Locale, detail:String):Void {
		task.begins(label, detail);

		stage.root.bands(progress);
		progress.arrive(task);
		progress.rise.hold(1);
		progress.fade.hold(1);
		progress.onCancel = null;

		stage.root.soil();
	}

	/**
		Takes the progress bar down.
	**/
	function settled():Void {
		if (stage.root.band != progress) return;

		task.ends(true);
		stage.root.bands(null);
		stage.root.soil();
	}

	/**
		Unpacks the downloaded update and writes the handover script.
	**/
	function applying():Void {
		shows(Locale.WORKING_INSTALLING, update.offered);

		if (!update.applies(Paths.beside())) {
			update.forget();
			settled();
			session.say(stage.root.translate(Locale.UPDATE_BROKEN));
		}

		session.changed();
	}

	/**
		Launches the handover script and closes the application, which is the only way a
		running program can have its own files replaced.
	**/
	function handing():Void {
		session.say(stage.root.translate(Locale.UPDATE_APPLIED));
		session.changed();

		stage.root.soil();
		stage.draw();

		if (!update.hands()) {
			update.forget();
			settled();
			session.say(stage.root.translate(Locale.UPDATE_BROKEN));
			session.changed();
			return;
		}

		running = false;
	}

	/**
		Moves the progress bar on while a download or an install is running.

		@param since How long since the last frame.
		@return Whether anything is running.
	**/
	function pulling(since:Float):Bool {
		if (update == null) return false;

		final now = update.state();
		if (now != Update.FETCHING && now != Update.APPLYING) return false;

		task.holds(now == Update.FETCHING ? update.pulling() : -1);
		progress.advance(since);

		return true;
	}

	/**
		Acts on whatever the updater has got to since the last frame.

		@return Whether anything happened.
	**/
	function watched():Bool {
		if (update == null || rendering != null) return false;

		switch (update.state()) {
			case Update.WAITING:
				if (stage.root.sheet == panels.notice) return false;

				panels.notice.arrive();
				stage.root.raise(panels.notice);
				return true;

			case Update.CURRENT:
				if (session.saidKey == Locale.UPDATE_LOOKING) {
					session.says(Locale.UPDATE_CURRENT);
					session.changed();
					return true;
				}
				return false;

			case Update.UNREACHABLE:
				update.forget();
				settled();
				session.say(stage.root.translate(Locale.UPDATE_UNREACHABLE));
				session.changed();
				return true;

			case Update.FETCHED:
				applying();
				return true;

			case Update.APPLIED:
				handing();
				return true;

			case Update.BROKEN:
				update.forget();
				settled();
				session.say(stage.root.translate(Locale.UPDATE_BROKEN)
					+ (update.wrong == "" ? "" : ": " + update.wrong));
				session.changed();
				return true;

			case _:
				return false;
		}
	}

	/**
		Loads the language the settings ask for.
	**/
	function spoken():Void {
		final held = settings.of("language", "");
		final code = held != "" && Languages.known(held) ? held : Languages.guessed();

		Languages.speak(stage.root.translation, code);
		panels.preferences.speaks(Languages.shipped(), code);
	}

	/**
		Raises the first run sheet, which asks for a language.
	**/
	function greeting():Void {
		if (!firstRun) return;

		final welcome = new Welcome(session);
		panels.welcome = welcome;

		welcome.onChoose = function(code:String):Void {
			Languages.speak(stage.root.translation, code);
			panels.preferences.speaks(Languages.shipped(), code);

			relabel();
			stage.root.reshape();
		};

		welcome.onStart = function(code:String):Void {
			settings.put("language", code);

			session.automating = welcome.automating;
			settings.whole("automating", session.automating);

			panels.preferences.chose(Preferences.AUTOMATING, session.automating);
			settings.save();

			stage.root.lower();
			session.changed();
		};

		stage.root.raise(welcome);
		welcome.arrive(stage.root.translation.language);
	}

	/**
		Builds the menus again, which changing the language needs.
	**/
	function relabel():Void {
		menus.dress(session);
	}

	/**
		Puts the progress bar up for something long that runs on this thread, and draws
		one frame so it is actually seen before the work starts.

		@param label What the task is called.
		@param detail A second line.
	**/
	function busy(label:Locale, detail:String):Void {
		if (panels.working == null) return;

		task.begins(label, detail);
		stage.root.raise(panels.working);
		panels.working.arrive(task);

		stage.root.soil();
		stage.draw();
	}

	/**
		Takes that progress bar down.
	**/
	function idle():Void {
		task.ends(true);

		if (stage.root.sheet == panels.working) stage.root.lower();
		stage.root.soil();
	}

	/**
		Starts a bounce on a worker thread and puts the progress bar up in the band.

		@param where The file to write.
	**/
	function renders(where:String):Void {
		rendering = files.renders(where);

		bounce.begins(Locale.WORKING_RENDERING, Files.name(where), true);

		stage.root.bands(progress);
		progress.arrive(bounce);
		progress.rise.hold(1);
		progress.fade.hold(1);

		progress.onCancel = function():Void {
			if (rendering != null) rendering.stops();
		};

		stage.root.soil();
		stage.draw();
	}

	/**
		Follows a running bounce, and writes the file when it finishes.

		@param since How long since the last frame.
		@return Whether one is running.
	**/
	function rendered(since:Float):Bool {
		if (rendering == null) return false;

		final held = rendering;
		bounce.holds(held.reach());

		progress.advance(since);

		if (!files.wroteYet()) return true;

		rendering = null;

		final wrong = files.wroteWrong;
		final beaten = wrong == "" && held.stopped();

		if (wrong != "") session.says(Locale.SAID_FAILED, wrong);
		else if (beaten) session.says(Locale.SAID_STOPPED);
		else session.saying(files.wroteKey, files.wroteWith);

		bounce.ends(wrong == "" && !beaten);
		stage.root.bands(null);

		session.changed();
		return true;
	}

	static inline final USAGE_EVERY = 0.5;

	var usageAt:Float = 0;
	var usageSaid:String = "";

	/**
		@return What this process is costing the machine, for the status bar, worked out no more
			often than twice a second.
	**/
	function measured():String {
		final now = Sdl.ticks();
		if (now - usageAt < USAGE_EVERY) return usageSaid;

		usageAt = now;

		final cpu = Usage.cpu();
		final ram = Usage.ram();
		final gpu = Usage.gpu();

		if (cpu < 0 && ram < 0) {
			usageSaid = "";
			return usageSaid;
		}

		var held = "cpu " + Math.round(cpu) + "%   ram " + Math.round(ram) + " MB";
		if (gpu >= 0) held += "   gpu " + Math.round(gpu) + "%";

		final render = sound.render;

		if (render != null && render.rate > 0 && render.leastHeld > 0) {
			held += "   ring " + Math.round(render.leastHeld * 1000.0 / render.rate) + " ms";
		}

		usageSaid = held;
		return usageSaid;
	}

	/**
		Removes the backups that are too old or too many.
	**/
	function backing():Void {
		final held = panels.preferences;

		files.backupRoom = Preferences.ROOMS[held.backups] * 1024 * 1024;
		files.backupDays = Preferences.DAYS[held.backupAge];

		final gone = files.pruned();
		if (gone > 0) session.says(Locale.SAID_SWEPT_BACKUPS, "" + gone);

		session.changed();
	}

	/**
		Asks for a folder and remembers it as where projects or presets live.

		@param row Which of the two.
	**/
	function folder(row:Int):Void {
		if (asking != null) return;

		asked = row;
		asking = mdd.host.Dialog.folder(stage.window,
			row == Preferences.PROJECTS ? files.within("projects") : files.within("presets"));
	}

	/**
		Takes the folder a dialog answered with.
	**/
	function folded():Void {
		if (asking == null) return;

		final state = mdd.host.Dialog.state(asking);
		if (state == mdd.host.Dialog.WAITING) return;

		if (state == mdd.host.Dialog.CHOSEN) {
			final where = haxe.io.Path.normalize((mdd.host.Dialog.path(asking) : String));

			if (asked == Preferences.PROJECTS) {
				files.projectsAt = where;
				panels.preferences.projectsAt = where;
				settings.put("projects", where);
			} else {
				files.presetsAt = where;
				panels.preferences.presetsAt = where;
				settings.put("presets", where);
			}

			settings.save();
			session.say(where);
			session.changed();
		}

		mdd.host.Dialog.close(asking);
		asking = null;
	}

	/**
		Reads every setting back and applies it: the theme, the faces, the density, the
		language, the bindings, the mapping, the folders and the rest.
	**/
	function remembered():Void {
		final which = settings.asWhole("theme", 0);
		final typeface = settings.asWhole("typeface", 0);
		final motion = settings.asWhole("motion", stage.root.flow);
		final density = settings.asWhole("density", 1);
		final tail = settings.asWhole("tail", 1);
		final keeping = settings.asWhole("keeping", 2);
		final backups = settings.asWhole("backups", 3);
		final backupAge = settings.asWhole("backupAge", 2);
		final looks = settings.asFlag("update", true);
		final master = settings.asWhole("monitor", Session.UNITY);
		final automating = settings.asWhole("automating", Session.LANES);
		final snapping = settings.asWhole("snapping", Session.SIXTEENTH);

		if (looks && update.possible()) update.look();

		files.projectsAt = settings.of("projects", "");
		files.presetsAt = settings.of("presets", "");
		files.savedInto = stage.root.translate(Locale.PRESET_SAVED);

		keyboard.onNote = function(pitch:Int, velocity:Int):Void {
			if (session != null) session.transport.auditions(session.part, pitch, velocity, true);
		};

		keyboard.onRelease = function(pitch:Int):Void {
			if (session != null) session.transport.releases(session.part);
		};

		keyboard.onControl = function(control:Int, value:Int):Void turned(control, value);

		listens(settings.of("midi", ""));

		panels.preferences.projectsAt = files.projectsAt;
		panels.preferences.presetsAt = files.presetsAt;

		session.theme = which;
		session.motion = motion;
		session.typeface = typeface;
		session.master = master < 0 ? 0 : (master > mdd.song.Song.LOUDEST
			? mdd.song.Song.LOUDEST : master);

		sound.monitors(Session.gainOf(session.master));
		session.automating = automating == Session.CLIPS ? Session.CLIPS : Session.LANES;
		session.snapping = snapping < 0 ? Session.SIXTEENTH : snapping;

		stage.root.theme.wear(which);
		stage.root.flow = motion;

		if (typeface != 0) redressed();

		panels.preferences.chose(Preferences.DENSITY, density);
		panels.preferences.chose(Preferences.TAIL, tail);
		panels.preferences.chose(Preferences.KEEPING, keeping);
		panels.preferences.chose(Preferences.BACKUPS, backups);
		panels.preferences.chose(Preferences.BACKUP_AGE, backupAge);
		panels.preferences.chose(Preferences.UPDATES, looks ? 1 : 0);

		keyboards();

		panels.preferences.chose(Preferences.CONSOLE,
			settings.asWhole("console", mdd.play.Render.MODEL_ONE));

		panels.preferences.chose(Preferences.TEMPO, settings.asWhole("tempo", 0));

		panels.preferences.chose(Preferences.PRESENCE,
			settings.asWhole("presence", Presence.FULL));

		bindings.reads(settings.of("keys", ""));

		final controls = settings.of("controls", "");

		if (controls == "") mapping.plain();
		else mapping.reads(controls);

		stage.root.reshape();
	}

	/**
		Bakes the faces again and lays the interface out, which changing the pairing needs.
	**/
	function redressed():Void {
		stage.typeface = session == null ? 0 : session.typeface;
		stage.redressed();
	}

	/**
		Writes every setting out.
	**/
	function keeps():Void {
		if (settings == null) return;

		settings.whole("theme", session.theme);
		settings.whole("typeface", session.typeface);
		settings.whole("motion", session.motion);
		settings.whole("monitor", session.master);
		settings.whole("automating", session.automating);
		settings.whole("snapping", session.snapping);
		settings.whole("density", panels.preferences.density);
		settings.whole("tail", panels.preferences.tail);
		settings.whole("keeping", panels.preferences.keeping);
		settings.whole("backups", panels.preferences.backups);
		settings.whole("backupAge", panels.preferences.backupAge);
		if (stage.shown) settings.flag("maximised", stage.maximised());
		settings.whole("width", Sdl.windowWidth(stage.window));
		settings.whole("height", Sdl.windowHeight(stage.window));
		settings.put("song", files == null ? "" : files.path);
		settings.put("language", stage.root.translation.language);
		settings.put("midi", midiSaid);
		settings.whole("midiChannel", panels.preferences.keyboardChannel);
		settings.whole("midiVelocity", panels.preferences.keyboardVelocity);
		settings.whole("console", panels.preferences.console);
		settings.whole("tempo", panels.preferences.tempo);
		settings.whole("presence", panels.preferences.presence);
		settings.put("keys", bindings.said());
		settings.put("controls", mapping.said());

		settings.save();
	}

	/**
		Writes out only the settings that change often.
	**/
	function keeping():Void {
		if (files.path == "") {
			files.ask(stage.window, Files.SAVE);
			return;
		}

		try {
			files.save(files.path);
		} catch (e:Dynamic) {
			session.says(Locale.SAID_FAILED, "" + e);
		}

		session.changed();
	}

	/**
		Takes the last edit back and redraws.
	**/
	function undone():Void {
		if (session.undo()) session.says(Locale.SAID_UNDONE);
		else session.says(Locale.SAID_NOTHING_UNDO);

		session.changed();
	}

	/**
		Puts it back.
	**/
	function redone():Void {
		if (session.redo()) session.says(Locale.SAID_REDONE);
		else session.says(Locale.SAID_NOTHING_REDO);

		session.changed();
	}

	/**
		Starts a new piece.
	**/
	function fresh():Void {
		loaded(Session.empty(library));
		files.forget();

		session.say(stage.root.translate(Locale.FILE_NEW));
	}

	final bindings:Bindings = new Bindings();
	final mapping:Mapping = new Mapping();
	final collector:Collector = new Collector();

	/**
		Acts on a chord the focus chain declined, which is what lets a field keep its
		plain keys while a chord still reaches past it.

		@param code Which key.
		@param mods Which modifiers were held.
		@return Whether anything took it.
	**/
	function commanded(code:Key, mods:Mod):Bool {
		if (code == Key.Z && (mods & Mod.Ctrl) != 0 && (mods & Mod.Shift) != 0) {
			redone();
			return true;
		}

		final action = bindings.actionFor(code, mods);
		if (action == Bindings.NONE) return false;

		if (action >= Bindings.SELECT && action <= Bindings.PAN) {
			return tooled(action - Bindings.SELECT);
		}

		switch (action) {
			case Bindings.UNDO: undone();
			case Bindings.REDO: redone();
			case Bindings.NEW: fresh();
			case Bindings.OPEN: files.ask(stage.window, Files.OPEN);
			case Bindings.SAVE: keeping();
			case Bindings.PREFERENCES: panels.opened();
			case Bindings.PLAY: panels.bar.press(TransportBar.PLAY);
			case Bindings.STOP: panels.bar.press(TransportBar.STOP);
			case Bindings.LOOP: panels.bar.press(TransportBar.LOOP);
			case Bindings.WRITE_VGM: files.ask(stage.window, Files.VGM);
			case Bindings.WRITE_AUDIO: panels.sounded();
			case Bindings.EARLIER: nudged(-1);
			case Bindings.LATER: nudged(1);
			case Bindings.ALL: return edited(mdd.ui.Edit.ALL);
			case Bindings.COPY: return edited(mdd.ui.Edit.COPY);
			case Bindings.CUT: return edited(mdd.ui.Edit.CUT);
			case Bindings.PASTE: return edited(mdd.ui.Edit.PASTE);
			case _: return false;
		}

		return true;
	}

	/**
		Puts the bindings into the menus, so they show the chords.
	**/
	function bound():Void {
		if (panels == null || panels.centre == null) return;

		if (panels.centre.tools != null) panels.centre.tools.bindings = bindings;

		panels.centre.roll.bindings = bindings;
		panels.centre.playlist.bindings = bindings;
	}

	/**
		Sends an editing command to whatever has the keyboard.

		@param what One of the `Edit` values.
		@return Whether anything took it.
	**/
	function edited(what:Int):Bool {
		return stage.root.edits(what);
	}

	/**
		Moves the whole piece in time.

		@param way How far, in ticks.
	**/
	function nudged(way:Int):Void {
		session.does(new mdd.song.edit.ShiftSong(way));
		session.say(stage.root.translate(way < 0 ? Locale.EDIT_EARLIER : Locale.EDIT_LATER));
	}

	/**
		Puts a tool in hand.

		@param which Which tool.
		@return Whether it changed.
	**/
	function tooled(which:Int):Bool {
		final tools = panels.centre == null ? null : panels.centre.tools;

		if (tools == null || !tools.visible) return false;
		if (which < 0 || (tools.allowed & (1 << which)) == 0) return false;

		tools.press(which);
		tools.invalidate();

		return true;
	}

	/**
		Prints what opened and what did not: the window, the renderer, the faces, the
		device, the settings, the updater and the presence. It is the first thing to read
		when something is wrong on a machine that is not to hand.
	**/
	function report():Void {
		Sys.println("  " + Config.TITLE + " " + Config.VERSION);
		Sys.println("  renderer      " + Sdl.rendererName(stage.renderer));
		Sys.println("  vsync         " + Sdl.rendererVsync(stage.renderer));
		Sys.println("  refresh       " + Sdl.displayRefresh(stage.window) + " Hz");
		Sys.println("  window        " + Sdl.windowWidth(stage.window) + "x"
			+ Sdl.windowHeight(stage.window) + " logical"
			+ (stage.maximised() ? ", maximised" : ""));
		Sys.println("  drawing at    " + Sdl.outputWidth(stage.renderer) + "x"
			+ Sdl.outputHeight(stage.renderer) + " native pixels");
		Sys.println("  pixel density " + Sdl.pixelDensity(stage.window));
		Sys.println("  display scale " + stage.scale);
		Sys.println("  motion        " + (stage.root.flow == Flow.Reduced
			? "reduced, as the desktop asks" : "full"));
		Sys.println("  userdata      " + Paths.userdata()
			+ (settings.portable ? ", portable" : ""));
		Sys.println("  audio         " + (sound.speaker == null ? "no device"
			: Audio.name(sound.speaker) + ", " + Audio.rate(sound.speaker) + " Hz"));
		Sys.println("  icons         " + (stage.iconsAt == "" ? "none" : stage.iconsAt));
		Sys.println("  profile       " + panels.budget.profile.name + ", "
			+ panels.budget.profile.counted() + " parts");
		Sys.println("  remembered    " + settings.read + " settings from "
			+ (settings.portable ? "beside the program" : "the settings directory"));
		Sys.println("  saving        " + (files.every <= 0 ? "only when asked"
			: "on its own every " + Std.int(files.every / 60) + " minutes"));
		Sys.println("  updates       " + (update.possible()
			? "github " + update.repository : "no repository configured, never looks"));
		Sys.println("  language      " + stage.root.translation.language + ", "
			+ stage.root.translation.count() + " strings of " + Languages.shipped().length
			+ " shipped languages");
		Sys.println("  presence      " + presence.said());
	}

	/**
		The frame loop: take events, advance motion, poll the files, follow a bounce or a
		download, draw a frame if anything changed, and sleep if nothing did.
	**/
	function loop():Void {
		final event = new Event();
		last = Sdl.ticks();

		while (running) {
			while (Sdl.pollEvent(cpp.Pointer.addressOf(event).raw) != 0) {
				if (!stage.took(event)) running = false;
			}

			if (!running) break;

			final now = Sdl.ticks();
			var since = now - last;
			last = now;
			if (since > 0.100) since = 0.100;

			if (keyed()) stage.root.soil();

			stage.root.advance(since);
			if (files != null && files.poll()) stage.root.soil();
			folded();
			if (rendered(since) || pulling(since)) stage.root.soil();
			if (files != null && files.tick(since)) stage.root.soil();
			if (watched()) stage.root.soil();
			watch();

			final showing = bounce.running() ? bounce : task;
			presence.busy = showing.running() ? stage.root.translate(showing.label) : "";
			presence.tick(since);

			if (shared()) stage.root.soil();
			if (costed()) stage.root.soil();

			collector.rests(since, stage.draw());
		}
	}

	/**
		@return The last status line, read in the language being worn. A line put up by
			name is looked up now rather than when it was said.
	**/
	function saying():String {
		if (session.saidKey < 0) return session.said;

		return Translation.filled(stage.root.translate(session.saidKey),
			session.saidWith);
	}

	/**
		Changes which output stage is monitored, and tells the export panel so it keeps
		its own rather than following this.

		@param which Which output stage.
	**/
	function consoled(which:Int):Void {
		if (sound.render != null) sound.render.console = which;
		if (panels != null && panels.exporting != null) panels.exporting.follows(which);
	}

	/**
		Opens the MIDI port the settings name.
	**/
	function keyboards():Void {
		final held = panels.preferences.keyboards;

		held.resize(0);
		held.push(stage.root.translate(Locale.MIDI_NONE));

		for (name in devices()) held.push(name);

		var at = held.indexOf(midiSaid);
		if (midiSaid == "" || at < 0) at = 0;

		final channel = settings == null ? 0 : settings.asWhole("midiChannel", 0);
		final velocity = settings == null ? 0 : settings.asWhole("midiVelocity", 0);

		panels.preferences.keyed(at, channel, velocity);

		keyboard.channel = channel <= 0 ? Keyboard.ANY : channel - 1;
		keyboard.forces = velocity != 0;
	}

	/**
		Turns whatever a MIDI controller is mapped to.

		@param control Which controller.
		@param value Its value, 0 to 127.
	**/
	function turned(control:Int, value:Int):Void {
		if (panels != null && panels.preferences != null
			&& panels.preferences.hears(control)) return;

		if (session == null || !session.part.fm()) return;

		final slot = mapping.slotFor(control);
		if (slot == Mapping.NONE) return;

		final patch = session.song.patchOf(session.part);
		if (patch == null) return;

		final want = mapping.turns(patch, slot, value);

		final key = mapping.named(slot);
		final held = mapping.operated(slot);

		if (key < 0) return;

		session.say(stage.root.translate(key)
			+ (held < 0 ? "" : " " + (held + 1)) + "  " + want);
		session.changed();
	}

	/**
		Takes whatever the MIDI keyboard has played.

		@return Whether anything arrived.
	**/
	function keyed():Bool {
		if (!mdd.host.Midi.holding()) return false;
		return keyboard.drains() > 0;
	}

	/**
		Opens a MIDI port by name.

		@param want What the port is called, or an empty string for none.
		@return Whether one opened.
	**/
	function listens(want:String):Bool {
		mdd.host.Midi.close();

		midiAt = -1;
		midiSaid = want;

		if (want == "") return false;

		for (index in 0...mdd.host.Midi.count()) {
			if (Std.string(mdd.host.Midi.named(index)) != want) continue;

			if (mdd.host.Midi.open(index)) {
				midiAt = index;
				return true;
			}

			break;
		}

		return false;
	}

	public static function devices():Array<String> {
		final out:Array<String> = [];
		for (index in 0...mdd.host.Midi.count()) out.push(Std.string(mdd.host.Midi.named(index)));

		return out;
	}

	var midiAt:Int = -1;
	var midiSaid:String = "";

	/**
		Keeps the status bar, the meters, the scope and the presence up to date.
	**/
	function watch():Void {
		if (session == null || panels == null) return;

		final centre = panels.centre;
		final rack = panels.rack;
		if (centre == null || rack == null) return;

		centre.playhead(session.transport.tick());

		if (sound.render == null) return;

		var moved = false;
		sound.metered();

		for (index in 0...Part.COUNT) {
			final was = rack.levels[index];
			final now = sound.peaks[index];
			final held = now > was ? now : was * 0.86;

			if (Math.abs(held - was) > 0.01) moved = true;
			rack.levels[index] = held;
		}

		if (moved) {
			rack.invalidate();
			if (panels.rail != null) panels.rail.hardware.invalidate();
		}

		if (panels.bar != null) {
			panels.bar.metered(sound.render.peak);
			sound.render.forgetPeak();
		}

		sound.lit(session.transport.stream);

		if (centre.roll.visible) centre.roll.lights(sound.sounding);

		if (centre.registers.visible) {
			sound.seen = centre.registers.take(session.transport.stream, sound.seen);
		}

		if (!centre.scope.visible) return;

		sound.poured(centre.scope);

		for (index in 0...Part.COUNT) {
			centre.scope.sang(index, sound.sounding.keyed[index] ? sound.sounding.notes[index] : -1);
		}

		centre.scope.invalidate();
	}

	/**
		Puts what the machine is costing on the status bar.

		This runs every frame rather than on an edit, because the numbers move on
		their own: reading them only when the song changed left them standing at
		whatever they were at the last edit, and never moving at all while a piece
		played. `measured` works them out twice a second and hands back the same
		line in between, so this costs a comparison on the frames between.

		@return Whether the line changed and the bar has to be drawn again.
	**/
	function costed():Bool {
		if (panels == null || panels.status == null) return false;

		final held = measured();
		if (held == panels.status.usage) return false;

		panels.status.usage = held;
		panels.status.invalidate();
		return true;
	}

	/**
		Claims the one instance lock, and hands the file to the copy already running
		where one has it.

		@return False where another copy is already running.
	**/
	function shared():Bool {
		if (panels == null || panels.preferences == null) return false;
		if (stage.root.sheet != panels.preferences) return false;

		final held = !presence.possible() ? stage.root.translate(Locale.PRESENCE_NONE)
			: (presence.live() ? presence.said()
				: stage.root.translate(Locale.PRESENCE_WAITING));

		if (held == panels.preferences.presenceSaid) return false;

		panels.preferences.presenceSaid = held;
		panels.preferences.invalidate();

		return true;
	}

	/**
		Writes the settings, stops the sound, gives the window back and releases the lock.
	**/
	function shut():Void {
		keeps();

		presence.shut();

		sound.shut();
		stage.shut();
	}
}
