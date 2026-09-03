package mdd;

import mdd.app.Files;
import mdd.app.Languages;
import mdd.app.Locale;
import mdd.app.Menus;
import mdd.app.Panels;
import mdd.app.Session;
import mdd.app.Task;
import mdd.app.Sound;
import mdd.app.Stage;
import mdd.app.Update;
import mdd.host.Audio;
import mdd.host.Crash;
import mdd.host.Event;
import mdd.host.Instance;
import mdd.host.Native;
import mdd.host.Paths;
import mdd.host.Sdl;
import mdd.host.Settings;
import mdd.ui.Flow;
import mdd.ui.Key;
import mdd.ui.Mod;
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
class App {
	static inline final LOCK = "-running";

	final stage:Stage = new Stage();
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
	var rendering:Null<mdd.play.Mixdown> = null;
	var rendersInto:String = "";
	var running:Bool = true;
	var last:Float = 0;

	function new() {}

	public static function main():Void {
		Native.ready();

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

	function open():Bool {
		if (!stage.open()) return false;

		dress();
		stage.measured();
		sound.open(session.transport);

		stage.show(settings == null || settings.asFlag("maximised", true));
		return true;
	}

	function dress():Void {
		session = Session.started();

		panels = new Panels(stage);
		panels.dress(session);

		files = new Files(session);
		files.onLoad = function(song:Song):Void loaded(song);
		panels.onImportSample = function():Void files.ask(stage.window, Files.READ_WAV);

		panels.naming = new Naming();
		panels.naming.onShut = function():Void stage.root.lower();

		panels.working = new Working();

		panels.onMaster = function(much:Int):Void {
			sound.monitors(much / mdd.song.Song.LOUDEST);
			keeps();
		};

		files.onBusy = function(label:String, detail:String):Void busy(label, detail);
		files.onIdle = function():Void idle();
		files.onRender = function(where:String):Void renders(where);

		panels.exporting = new Export(session);
		panels.exporting.onShut = function():Void stage.root.lower();

		panels.exporting.onExport = function(mixing:mdd.play.Mixing):Void {
			files.mixing = mixing;
			files.ask(stage.window, Files.AUDIO);
		};

		panels.preferences = new Preferences(session);
		panels.preferences.onScale = function(much:Float):Void stage.densified(much);
		panels.preferences.onTypeface = function(which:Int):Void redressed();
		panels.preferences.onKeep = function():Void keeps();
		panels.preferences.onKeeping = function(every:Float):Void files.every = every;
		panels.preferences.onBackups = function():Void backing();
		panels.preferences.onUpdates = function(on:Bool):Void {
			settings.flag("update", on);
			settings.save();
		};

		panels.preferences.onFolder = function(row:Int):Void folder(row);

		panels.preferences.onSpeak = function(code:String):Void {
			Languages.speak(stage.root.translation, code);
			settings.put("language", code);

			relabel();
			stage.root.reshape();
		};

		update = new Update(Config.GITHUB, Config.VERSION);

		panels.notice = new Notice(session);
		panels.notice.update = update;
		panels.notice.onTake = function():Void fetching();
		panels.notice.onNever = function():Void {
			settings.flag("update", false);
			settings.save();
		};

		settings = new Settings();
		settings.load();

		firstRun = settings.of("language", "") == "";
		spoken();
		remembered();

		menus = new Menus(stage, panels);
		menus.update = update;
		menus.onAsk = function(which:Int):Void files.ask(stage.window, which);
		menus.onSave = function():Void keeping();
		menus.onQuit = function():Void running = false;
		menus.onUndo = function():Void undone();
		menus.onRedo = function():Void redone();
		menus.dress(session);

		stage.root.onChord = function(code:Key, mods:Mod):Bool return chorded(code, mods);

		session.onReveal = function(found:mdd.check.Diagnostic):Void revealed(found);
		session.say(stage.root.translate(Locale.READY));

		keeps();
		greeting();
		handed();

		session.onChange = function(held:Session):Void changed();
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

	function loaded(song:Song):Void {
		final held = session == null ? mdd.song.Song.LOUDEST : session.master;

		sound.stop();

		session = new Session(song);
		session.onChange = function(held:Session):Void changed();
		session.onReveal = function(found:mdd.check.Diagnostic):Void revealed(found);

		files = new Files(session);
		files.onLoad = function(held:Song):Void loaded(held);

		session.master = held;

		panels.dress(session);
		menus.dress(session);

		session.transport.silence();
		sound.follows(session.transport);

		stage.measured();
		changed();
	}

	function changed():Void {
		if (panels == null || panels.budget == null || session == null) return;

		panels.budget.overSong(session.song);

		if (panels.centre != null) panels.centre.roll.invalidate();
		if (panels.inspector != null) panels.inspector.follow();

		if (panels.dock != null) {
			panels.dock.warnings.fit();
			panels.dock.said = session.said;
			panels.dock.invalidate();
		}
	}

	function revealed(found:mdd.check.Diagnostic):Void {
		if (panels.centre == null || found.note == null) return;

		panels.centre.show(mdd.view.Centre.ROLL);
		panels.centre.roll.reveal(found.note.at, found.note.pitch);
		panels.centre.roll.choose(found.note);
	}

	function fetching():Void {
		final into = Paths.within("updates") + "/" + Config.SHORT + "-" + update.offered
			+ Paths.suffix();

		if (!update.take(into)) {
			session.say("that update cannot be downloaded");
			session.changed();
			return;
		}

		if (panels.working == null) {
			session.say("downloading to " + into);
			session.changed();
			return;
		}

		task.begins(Locale.WORKING_DOWNLOADING, Files.name(into));
		stage.root.raise(panels.working);
		panels.working.arrive(task);

		panels.working.onCancel = null;
		session.changed();
	}

	function settled():Void {
		if (panels.working == null || stage.root.sheet != panels.working) return;

		task.ends(true);
		stage.root.lower();
	}

	function pulling(since:Float):Bool {
		if (update == null || update.state() != Update.FETCHING) return false;

		task.holds(update.pulling());
		if (panels.working != null) panels.working.advance(since);

		return true;
	}

	function watched():Bool {
		if (update == null) return false;

		switch (update.state()) {
			case Update.WAITING:
				if (stage.root.sheet == panels.notice) return false;

				panels.notice.arrive();
				stage.root.raise(panels.notice);
				return true;

			case Update.CURRENT:
				if (session.said == stage.root.translate(Locale.UPDATE_LOOKING)) {
					session.say(stage.root.translate(Locale.UPDATE_CURRENT));
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
				update.forget();
				settled();
				session.say(stage.root.translate(Locale.UPDATE_FETCHED) + " " + update.into);
				session.changed();
				return true;

			case _:
				return false;
		}
	}

	function spoken():Void {
		final held = settings.of("language", "");
		final code = held != "" && Languages.known(held) ? held : Languages.guessed();

		Languages.speak(stage.root.translation, code);
		panels.preferences.speaks(Languages.shipped(), code);
	}

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
			settings.save();

			stage.root.lower();
			session.changed();
		};

		stage.root.raise(welcome);
		welcome.arrive(stage.root.translation.language);
	}

	function relabel():Void {
		menus.dress(session);
	}

	function busy(label:String, detail:String):Void {
		if (panels.working == null) return;

		task.begins(label, detail);
		stage.root.raise(panels.working);
		panels.working.arrive(task);

		stage.root.soil();
		stage.draw();
	}

	function idle():Void {
		task.ends(true);

		if (stage.root.sheet == panels.working) stage.root.lower();
		stage.root.soil();
	}

	function renders(where:String):Void {
		if (panels.working == null) {
			files.exportAudio(where);
			return;
		}

		rendersInto = where;
		rendering = files.renders();

		task.begins(Locale.WORKING_RENDERING, Files.name(where), true);
		stage.root.raise(panels.working);
		panels.working.arrive(task);

		panels.working.onCancel = function():Void {
			if (rendering != null) rendering.stops();
		};

		stage.root.soil();
	}

	function rendered(since:Float):Bool {
		if (rendering == null) return false;

		final held = rendering;
		task.holds(held.reach());

		if (panels.working != null) panels.working.advance(since);

		if (held.stopped()) {
			rendering = null;
			task.ends(false);

			if (stage.root.sheet == panels.working) stage.root.lower();
			session.say("stopped rendering");
			session.changed();

			return true;
		}

		if (held.reach() < 1) return true;

		rendering = null;

		try {
			files.wrote(rendersInto, held);
		} catch (e:Dynamic) {
			session.say("that would not work: " + e);
		}

		task.ends(true);
		if (stage.root.sheet == panels.working) stage.root.lower();

		session.changed();
		return true;
	}

	function backing():Void {
		final held = panels.preferences;

		files.backupRoom = Preferences.ROOMS[held.backups] * 1024 * 1024;
		files.backupDays = Preferences.DAYS[held.backupAge];

		final gone = files.pruned();
		if (gone > 0) session.say("removed " + gone + " older backups");

		session.changed();
	}

	function folder(row:Int):Void {
		if (asking != null) return;

		asked = row;
		asking = mdd.host.Dialog.folder(stage.window,
			row == Preferences.PROJECTS ? files.within("projects") : files.within("presets"));
	}

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

	function remembered():Void {
		final which = settings.asWhole("theme", 0);
		final typeface = settings.asWhole("typeface", 0);
		final motion = settings.asWhole("motion", stage.root.flow);
		final density = settings.asWhole("density", 1);
		final keeping = settings.asWhole("keeping", 2);
		final backups = settings.asWhole("backups", 3);
		final backupAge = settings.asWhole("backupAge", 2);
		final looks = settings.asFlag("update", true);
		final master = settings.asWhole("master", mdd.song.Song.LOUDEST);

		if (looks && update.possible()) update.look();

		files.projectsAt = settings.of("projects", "");
		files.presetsAt = settings.of("presets", "");

		panels.preferences.projectsAt = files.projectsAt;
		panels.preferences.presetsAt = files.presetsAt;

		session.theme = which;
		session.motion = motion;
		session.typeface = typeface;
		session.master = master < 0 ? 0 : (master > mdd.song.Song.LOUDEST
			? mdd.song.Song.LOUDEST : master);

		sound.monitors(session.master / mdd.song.Song.LOUDEST);

		stage.root.theme.wear(which);
		stage.root.flow = motion;

		if (typeface != 0) redressed();

		panels.preferences.chose(Preferences.DENSITY, density);
		panels.preferences.chose(Preferences.KEEPING, keeping);
		panels.preferences.chose(Preferences.BACKUPS, backups);
		panels.preferences.chose(Preferences.BACKUP_AGE, backupAge);
		panels.preferences.chose(Preferences.UPDATES, looks ? 1 : 0);
		stage.root.reshape();
	}

	function redressed():Void {
		stage.typeface = session == null ? 0 : session.typeface;
		stage.redressed();
	}

	function keeps():Void {
		if (settings == null) return;

		settings.whole("theme", session.theme);
		settings.whole("typeface", session.typeface);
		settings.whole("motion", session.motion);
		settings.whole("master", session.master);
		settings.whole("density", panels.preferences.density);
		settings.whole("keeping", panels.preferences.keeping);
		settings.whole("backups", panels.preferences.backups);
		settings.whole("backupAge", panels.preferences.backupAge);
		if (stage.shown) settings.flag("maximised", stage.maximised());
		settings.whole("width", Sdl.windowWidth(stage.window));
		settings.whole("height", Sdl.windowHeight(stage.window));
		settings.put("song", files == null ? "" : files.path);
		settings.put("language", stage.root.translation.language);

		settings.save();
	}

	function keeping():Void {
		if (files.path == "") {
			files.ask(stage.window, Files.SAVE);
			return;
		}

		try {
			files.save(files.path);
		} catch (e:Dynamic) {
			session.say(stage.root.translate(Locale.SAID_FAILED) + ": " + e);
		}

		session.changed();
	}

	function undone():Void {
		if (session.undo()) session.say(stage.root.translate(Locale.SAID_UNDONE));
		else session.say(stage.root.translate(Locale.SAID_NOTHING_UNDO));

		session.changed();
	}

	function redone():Void {
		if (session.redo()) session.say(stage.root.translate(Locale.SAID_REDONE));
		else session.say(stage.root.translate(Locale.SAID_NOTHING_REDO));

		session.changed();
	}

	function chorded(code:Key, mods:Mod):Bool {
		final ctrl = (mods & Mod.Ctrl) != 0;
		final shift = (mods & Mod.Shift) != 0;

		if (code == Key.Space) {
			panels.bar.press(ctrl ? TransportBar.STOP : TransportBar.PLAY);
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
				panels.bar.press(TransportBar.LOOP);
				return true;

			case Key.S:
				keeping();
				return true;

			case Key.O:
				files.ask(stage.window, Files.OPEN);
				return true;

			case Key.E:
				if (shift) panels.sounded();
				else files.ask(stage.window, Files.VGM);

				return true;

			case Key.Comma:
				panels.opened();
				return true;

			case _:
		}

		return false;
	}

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
	}

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

			stage.root.advance(since);
			if (files != null && files.poll()) stage.root.soil();
			folded();
			if (rendered(since) || pulling(since)) stage.root.soil();
			if (files != null && files.tick(since)) stage.root.soil();
			if (watched()) stage.root.soil();
			watch();
			stage.draw();
		}
	}

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

		final dock = panels.dock;

		if (dock != null && dock.mixer.visible) {
			for (index in 0...Part.COUNT) dock.mixer.levels[index] = rack.levels[index];
			if (moved) dock.mixer.invalidate();

			dock.mixer.metered(sound.render.peak);
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

	function shut():Void {
		keeps();

		sound.shut();
		stage.shut();
	}
}
