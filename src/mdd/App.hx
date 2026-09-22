package mdd;

import mdd.app.Bindings;
import mdd.app.Files;
import mdd.app.Favourites;
import mdd.app.Faces;
import mdd.app.Filming;
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
	final favourites:Favourites = new Favourites();

	/**
		When each installed preset was added, kept in the cache folder and filled in as the presets
		folder is read.
	**/
	final added:mdd.app.Added = new mdd.app.Added();

	/**
		The presets folder as the browser changes it, pointed at the folder once the settings are
		read and again whenever another is chosen.
	**/
	final presetFolder:mdd.app.PresetFolder = new mdd.app.PresetFolder("", "");
	final sound:Sound = new Sound();

	var panels:Null<Panels> = null;
	var menus:Null<Menus> = null;

	var session:Null<Session> = null;
	var files:Null<Files> = null;
	var settings:Null<Settings> = null;
	var update:Null<Update> = null;

	var firstRun:Bool = false;

	/**
		Whether the playhead was being followed when the menus were last built, so they are built
		again with the other label when it changes from the tools or a key.
	**/
	var followingShown:Bool = true;

	/**
		The faces a language needs that may not be installed, and the download of one.
	**/
	var faces:Null<Faces> = null;
	var asking:cpp.Star<mdd.host.Chooser> = null;
	var asked:Int = -1;

	final task:Task = new Task();
	final bounce:Task = new Task();
	final progress:Working = new Working();
	final presence:Presence = new Presence();

	/**
		The host monitor is off: the status bar says nothing about what this is costing.
	**/
	public static inline final MONITOR_OFF = 0;

	/**
		The host monitor shows what it always showed: processor, memory, graphics load and
		how much sound is waiting to be played.
	**/
	public static inline final MONITOR_PLAIN = 1;

	/**
		The host monitor shows all of that, and the high water mark of memory, the graphics
		memory held, and which renderer backend is drawing.
	**/
	public static inline final MONITOR_EVERYTHING = 2;

	var monitoring:Int = MONITOR_PLAIN;

	/**
		How many pieces the file menu offers to open again.
	**/
	public static inline final RECENT = 10;

	/**
		The pieces opened most recently, newest first. It is what the file menu offers and
		nothing else: none of them is opened on its own at startup, which is deliberate.
		A piece takes a while to load and the one wanted next is rarely the one left open
		last, so the choice stays with the reader.
	**/
	public final recent:Array<String> = [];

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
			if (!handsOver(mdd.host.Arguments.all())) {
				Sdl.message(Config.TITLE, Config.TITLE + " is already running.");
			}

			Sdl.quit();
			Sys.exit(0);
		}

		final app = new App();

		if (!app.open()) {
			final said = app.stage.failure;
			if (said != "") Sdl.fault(Config.TITLE, said);

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

	/**
		How long a second copy keeps trying to reach the first, in milliseconds, which covers a
		first copy that has taken the lock and is still opening its window.
	**/
	static inline final HANDING = 10000;

	/**
		Hands what this copy was opened with to the copy already running, which opens it and comes
		to the front. A copy opened with no file brings that one to the front and nothing else.

		@param args What this copy was started with.
		@return False where the copy running could not be reached, or this one was asked to export,
			which the copy running would not do.
	**/
	static function handsOver(args:Array<String>):Bool {
		for (arg in args) if (StringTools.startsWith(arg, "--export")) return false;

		var path = "";

		for (arg in args) {
			if (StringTools.startsWith(arg, "-") || !sys.FileSystem.exists(arg)) continue;

			path = haxe.io.Path.normalize(sys.FileSystem.absolutePath(arg));
			break;
		}

		return Instance.hand(Config.SHORT + LOCK, path, HANDING) != 0;
	}

	static function recorded(e:haxe.Exception):Void {
		final said = new StringBuf();

		said.add(Config.TITLE + " " + Config.VERSION + " stopped at " + Date.now() + "\n");
		said.add(e.message + "\n\n");
		said.add(haxe.CallStack.toString(e.stack) + "\n");

		Sys.println("mdd: " + e.message);
		Sys.println(haxe.CallStack.toString(e.stack));

		var where = "";

		try {
			where = Paths.within("logs") + "/crash.txt";
			sys.io.File.saveContent(where, said.toString());
			Sys.println("mdd: written to " + where);
		} catch (held:haxe.Exception) {
			where = "";
		}

		told(e.message, where);
	}

	/**
		Puts an exception that reached the top in front of whoever was using the window.

		Nothing else does: the console a release build was started from is not attached to
		anything, so without this the window disappears and the only sign of why is a file
		nobody was told about.

		@param message What the exception said.
		@param where The report, or empty where it could not be written.
	**/
	static function told(message:String, where:String):Void {
		final cut = message.length > 400 ? message.substr(0, 397) + "..." : message;

		final said = Config.TITLE + " stopped.\n\n" + cut
			+ (where == "" ? "" : "\n\nThe whole report is in\n" + where);

		try {
			Sdl.fault(Config.TITLE + " " + Config.VERSION, said);
		} catch (held:haxe.Exception) {}
	}

	/**
		Which renderer backend Windows falls back to, and starts at. All six SDL backends
		open a window and paint a still interface correctly; the fault in two of them
		appears only once the transport is running and the playhead, the scope and the
		meters are redrawing every frame. A flag or the `renderer` setting names another
		on any platform, because the plumbing is right and only the backends are not.
	**/
	public static inline final PINNED = #if windows "direct3d11" #else "" #end;

	static final DRIVERS:Array<String> = ["--dx11", "direct3d11", "--d3d11", "direct3d11",
		"--dx12", "direct3d12", "--d3d12", "direct3d12", "--vulkan", "vulkan",
		"--opengl", "opengl", "--opengles", "opengles2"];

	public static function flagged(args:Array<String>):String {
		for (index in 0...DRIVERS.length >> 1) {
			if (args.indexOf(DRIVERS[index * 2]) >= 0) return DRIVERS[index * 2 + 1];
		}

		for (arg in args) {
			if (StringTools.startsWith(arg, "--renderer=")) return arg.substr(11);
		}

		return "";
	}

	/**
		@return The renderer backends SDL was built with, by SDL's own names, leaving out
			`software`, which draws on the processor, and `gpu`, which the preferences do not offer.
	**/
	public static function offered():Array<String> {
		final out:Array<String> = [];

		for (index in 0...Sdl.renderDrivers()) {
			final name = (Sdl.renderDriver(index) : String);
			if (name != "" && name != "software" && name != "gpu") out.push(name);
		}

		return out;
	}

	/**
		Opens the window, the sound and the session, and reads the settings back.

		@return False where any of that would not work.
	**/
	function open():Bool {
		final args = mdd.host.Arguments.all();

		settings = new Settings();

		if (args.indexOf("--reset") >= 0) {
			settings.forget();
			Sys.println("  settings      reset to defaults");
		} else {
			settings.load();
		}

		final asked = flagged(args);
		final held = asked != "" ? asked : settings.of("renderer", "");

		stage.driver = held != "" && offered().indexOf(held) >= 0 ? held : PINNED;
		stage.always = args.indexOf("--redraw") >= 0;

		if (!stage.open()) return false;

		stage.onDrop = function(where:String):Void opens(where);
		stage.onFocus = function():Void rereads();

		dress();
		stage.measured();

		looked();

		outputSaid = settings.of("output", "");
		sound.open(session.transport, outputSaid);
		scoped();

		stage.show(settings == null || settings.asFlag("maximised", true));
		collector.minds();

		Instance.listen(Config.SHORT + LOCK);
		return true;
	}

	/**
		Opens what a second copy handed over, and comes to the front for it. A handover naming no
		file only brings the window forward.

		@return Whether anything arrived.
	**/
	function received():Bool {
		if (Instance.take() < 0) return false;

		final path = (Instance.taken() : String);

		stage.raise();
		if (path != "" && sys.FileSystem.exists(path)) opens(path);

		return true;
	}

	/**
		Asks the releases page once, if the settings allow it at all.

		Once a run, and only here. This used to sit with the settings being applied, which
		happens again every time the output device or the language is changed, so choosing
		either of those asked again: a copy told at startup that there was nothing new
		would put a notice up later in the same sitting, having never been asked to look.
	**/
	function looked():Void {
		if (settings == null || update == null) return;
		if (!settings.asFlag("update", true) || !update.possible()) return;

		update.look();
	}

	/**
		Builds the panels and the menus and wires every callback between them.
	**/
	function dress():Void {
		session = Session.started(library);
		presence.follows(session);

		panels = new Panels(stage);
		panels.favourites = favourites;
		panels.added = added;
		panels.presetFolder = presetFolder;
		panels.onPresetsChanged = function():Void rescanned();
		panels.dress(session);

		files = new Files(session);
		files.library = library;
		files.onLoad = function(song:Song):Void loaded(song);

		panels.onPreset = function(made:mdd.song.Instrument, sample:Null<mdd.song.Sample>):Void {
			if (files.keepsPreset(made, sample) == "") {
				session.says(Locale.SAID_PRESET_UNWRITTEN, files.within("presets"));
			}

			presetsStamp = files.presetsStamp();
		};

		panels.onPresetFolder = function():Void {
			final where = files.within("presets");
			if (!mdd.host.Paths.reveal(where)) session.say(where);
		};
		panels.onImportSample = function():Void files.ask(stage.window, Files.READ_WAV);

		panels.onWritePatch = function(preset:mdd.song.Instrument, sample:Null<mdd.song.Sample>):Void {
			files.chooses("", [preset], [sample]);
			files.ask(stage.window, Files.PRESET_TFI);
		};

		panels.onWriteSample = function(preset:mdd.song.Instrument, sample:Null<mdd.song.Sample>):Void {
			files.chooses("", [preset], [sample]);
			files.ask(stage.window, Files.PRESET_WAV);
		};

		panels.onWriteBank = function(name:String, presets:Array<mdd.song.Instrument>,
				samples:Array<Null<mdd.song.Sample>>):Void {
			files.chooses(name, presets, samples);
			files.ask(stage.window, Files.PRESET_BANK);
		};

		panels.naming = new Naming();
		panels.naming.onShut = function():Void stage.root.lower();

		panels.describing = new mdd.view.overlay.Describing(session);
		panels.describing.onShut = function():Void stage.root.lower();

		panels.working = new Working();

		panels.about = new mdd.view.overlay.About();
		panels.about.onShut = function():Void stage.root.lower();

		panels.limits = new mdd.view.overlay.Limits();
		panels.limits.onShut = function():Void stage.root.lower();

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

		panels.exportingVideo = new Export(session, true);
		panels.exportingVideo.onShut = function():Void stage.root.lower();

		panels.exportingVideo.onExport = function(mixing:mdd.play.Mixing):Void {
			files.mixing = mixing;
			files.ask(stage.window, Files.AUDIO);
		};

		panels.importing = new mdd.view.overlay.Importing();
		panels.importing.onShut = function():Void stage.root.lower();

		panels.importing.onImport = function(strands:Array<mdd.format.Strand>):Void {
			final instead = panels.importing.lands == mdd.view.overlay.Importing.INSTEAD;

			if (!instead) {
				imported(strands, false);
				return;
			}

			guards(function():Void imported(strands, true));
		};

		panels.asking = new mdd.view.overlay.Asking();
		panels.asking.onShut = function():Void stage.root.lower();

		files.onSurvey = function(called:String,
				strands:Array<mdd.format.Strand>):Void panels.surveyed(called, strands);

		panels.kitting = new mdd.view.overlay.Kitting();
		panels.kitting.onShut = function():Void stage.root.lower();

		panels.kitting.onSave = function(kit:mdd.format.Kit):Void {
			files.writeKit(kit);
			changed();
		};

		panels.kitting.onAdd = function():Void files.ask(stage.window, Files.READ_HIT);
		panels.kitting.onFolder = function():Void files.ask(stage.window, Files.READ_KIT);

		files.onHit = function(where:String):Void {
			if (panels.kitting == null) return;
			if (!panels.kitting.takes(where)) session.says(Locale.KIT_NONE);
		};

		files.onKitFolder = function(where:String):Void {
			if (panels.kitting == null) return;
			if (panels.kitting.takesFolder(where) == 0) session.says(Locale.KIT_NONE);
		};

		panels.preferences = new Preferences(session);
		panels.preferences.onScale = function(much:Float):Void stage.densified(much);

		panels.preferences.onTextSize = function(much:Float):Void {
			if (stage.textScale == much) return;

			stage.textScale = much;
			redressed();
			keeps();
		};
		panels.preferences.onTypeface = function(which:Int):Void redressed();
		panels.preferences.onKeep = function():Void keeps();
		panels.preferences.onKeeping = function(every:Float):Void files.every = every;
		panels.preferences.onBackups = function():Void backing();
		panels.preferences.onAutomating = function(which:Int):Void keeps();
		panels.preferences.onRightClick = function():Void keeps();
		panels.preferences.onUpdates = function(on:Bool):Void {
			settings.flag("update", on);
			settings.save();
		};

		panels.preferences.onFolder = function(row:Int):Void folder(row);

		panels.preferences.onHostMonitor = function(which:Int):Void {
			monitoring = which;

			usageAt = 0;
			usageSaid = "";

			costed();
			keeps();
		};

		panels.preferences.onPresence = function(which:Int):Void {
			presence.level = which;
			presence.tick(Presence.DIAL_EVERY);
		};

		panels.preferences.onTempo = function(which:Int):Void {
			panels.bar.regrids = which != 0;
			keeps();
		};

		panels.preferences.onNotation = function(which:Int):Void {
			panels.kitting.notation = which;
			session.changed();
			keeps();
		};

		panels.preferences.onPartColours = function(which:Int):Void keeps();

		panels.preferences.onConsole = function(which:Int):Void {
			consoled(which);
			keeps();
		};

		panels.preferences.onDeclick = function(declick:Bool):Void {
			declicked(declick);
			keeps();
		};

		panels.preferences.onKeyboard = function(which:Int):Void {
			final names = panels.preferences.keyboards;
			listens(which <= 0 || which >= names.length ? "" : names[which]);

			session.say(midiAt < 0 ? stage.root.translate(Locale.MIDI_NONE) : midiSaid);
			keeps();
		};

		panels.preferences.onOutput = function(which:Int):Void {
			final names = panels.preferences.outputs;
			outputSaid = which <= 0 || which >= names.length ? "" : names[which];

			sound.reopens(session.transport, outputSaid);
			sound.monitors(Session.gainOf(session.master));
			scoped();

			session.say(outputSaid == "" ? stage.root.translate(Locale.AUDIO_DEFAULT) : outputSaid);
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
			if (downloads(code)) return;

			Languages.speak(stage.root.translation, code);
			settings.put("language", code);

			listed(code);
			relabel();
			stage.root.reshape();
		};

		panels.preferences.onRenderer = function(name:String):Void {
			settings.put("renderer", name);
			settings.save();

			session.say(stage.root.translate(Locale.RENDERER_RESTART));
		};

		panels.preferences.draws(offered(), stage.driver);

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
		menus.onAsk = function(which:Int):Void asks(which);
		menus.onSave = function():Void keeping();
		menus.onRecent = function():Array<String> return recent;
		menus.onOpen = function(where:String):Void opens(where);
		menus.onQuit = function():Void quits();
		menus.onRelabel = function():Void relabel();
		menus.onUndo = function():Void undone();
		menus.onRedo = function():Void redone();
		menus.onLift = function():Int return files.liftsPatches();
		menus.onKit = function():Void panels.kitted(new mdd.format.Kit());
		menus.bindings = bindings;
		bound();

		menus.onNew = function():Void guards(function():Void fresh());
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
		files.forget();

		greeting();
		handed();

		session.onChange = function(held:Session):Void changed();
		changed();
	}

	public function forced():Void {
		for (arg in mdd.host.Arguments.all()) {
			if (!StringTools.startsWith(arg, "--export=")) continue;

			final where = arg.substr(9);
			if (where == "") continue;

			Sys.println("  forcing an export to " + where);
			renders(where);

			return;
		}

		if (mdd.host.Arguments.all().indexOf("--exporting") >= 0) panels.sounded();
	}

	/**
		Opens whatever file the application was started with.
	**/
	function handed():Void {
		for (arg in mdd.host.Arguments.all()) {
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

		if (!replaces(suffix)) {
			opened(where, suffix);
			return;
		}

		guards(function():Void opened(where, suffix));
	}

	/**
		@param suffix A file suffix, in lower case.
		@return Whether reading it puts a different piece in the window. A recording and a
			patch are added to the piece that is open, and a MIDI file is only surveyed
			until the import sheet is answered, so none of those loses anything.
	**/
	static function replaces(suffix:String):Bool {
		return switch (suffix) {
			case "mid", "midi", "wav", "tfi": false;
			case mdd.Config.PRESET, mdd.Config.BANK: false;
			case _: true;
		}
	}

	/**
		Reads a file, whatever has already been decided about the piece it replaces.

		@param where The file.
		@param suffix Its suffix, in lower case.
	**/
	function opened(where:String, suffix:String):Void {
		try {
			switch (suffix) {
				case "vgm", "vgz": files.readVgm(where);
				case "xgm": files.readXgm(where);
				case "mid", "midi": files.readMidi(where);
				case "wav": files.readWav(where);
				case "tfi": files.readTfi(where);
				case mdd.Config.PRESET, mdd.Config.BANK: files.readPresets(where);
				case _: files.load(where);
			}
		} catch (e:Dynamic) {
			session.says(Locale.SAID_OPEN_FAILED, "" + e);
		}

		changed();
	}

	/**
		What to do once the question about unsaved work has been answered.
	**/
	var pending:Null<Void -> Void> = null;

	/**
		Whether that answer sent the reader to the save dialog, so what happens next
		waits on which file was chosen rather than on the sheet.
	**/
	var saving:Bool = false;

	/**
		Asks about work in no file yet before doing something that would throw it away.

		Nothing is asked where the piece matches what was last read or written, so the
		ordinary case costs one pass over the piece and no sheet at all.

		@param what What to do once that is settled. It is not called at all where the
			answer was to stop.
	**/
	function guards(what:Void -> Void):Void {
		if (panels.asking == null || files == null || !files.unsaved()) {
			what();
			return;
		}

		pending = what;
		saving = false;

		final sheet = panels.asking;
		stage.root.raise(sheet);

		sheet.ask(sheet.translate(Locale.UNSAVED),
			sheet.filled(Locale.UNSAVED_SAID, [piece()]),
			[sheet.translate(Locale.FILE_SAVE), sheet.translate(Locale.UNSAVED_DISCARD),
			sheet.translate(Locale.EXPORT_CANCEL)]);

		sheet.onAnswer = function(which:Int):Void answered(which);
	}

	/**
		@return What to call the piece in the question: the file it came from, or the
			name it carries where it has never been in one.
	**/
	function piece():String {
		if (files.path != "") return Files.name(files.path);

		final called = session.song.name;
		return called == "" ? stage.root.translate(Locale.FILE_NEW) : called;
	}

	/**
		Acts on the answer.

		@param which 0 to save first, 1 to go on without saving, anything else to stop.
	**/
	function answered(which:Int):Void {
		final what = pending;

		if (which != 0 && which != 1) {
			pending = null;
			return;
		}

		if (which == 1) {
			pending = null;
			if (what != null) what();
			return;
		}

		if (files.path != "") {
			pending = null;

			keeping();
			if (what != null) what();
			return;
		}

		saving = true;
		files.ask(stage.window, Files.SAVE);
	}

	/**
		Goes on with whatever was waiting on a save, once the dialog has been answered.

		A dialog that was closed with nothing chosen is the same answer as stopping: the
		reader asked to save, did not, and the piece is still the one in the window.
	**/
	function written():Void {
		if (!saving) return;

		saving = false;

		final what = pending;
		pending = null;

		if (what != null && files.path != "") what();
	}

	/**
		Asks about unsaved work first where the dialog leads to a different piece in the
		window.

		@param which Which dialog.
	**/
	function asks(which:Int):Void {
		if (which != Files.OPEN && which != Files.READ_VGM && which != Files.READ_XGM) {
			files.ask(stage.window, which);
			return;
		}

		guards(function():Void files.ask(stage.window, which));
	}

	/**
		Stops the application, asking about unsaved work first.
	**/
	function quits():Void {
		guards(function():Void running = false);
	}

	/**
		Takes what the import sheet chose, and asks about the chords it landed.

		@param strands What to take, and where each strand goes.
		@param instead Whether it becomes a piece of its own rather than one more track.
	**/
	function imported(strands:Array<mdd.format.Strand>, instead:Bool):Void {
		files.takesMidi(strands, instead);
		changed();
		chorded();
	}

	/**
		Asks what to do about the notes an import left where no channel will sound them.

		A file written for anything polyphonic puts chords on one part, and this console
		gives that part to whichever note keyed on last. Nothing is asked where the piece
		has none, and a part with no key to be in is not counted, so a drum kit or an
		atonal run never raises this.
	**/
	function chorded():Void {
		if (panels.asking == null) return;

		final many = mdd.song.edit.ThinChords.counted(session.song);
		if (many == 0) return;

		final sheet = panels.asking;
		stage.root.raise(sheet);

		sheet.ask(sheet.translate(Locale.CHORDS),
			sheet.filled(Locale.CHORDS_SAID, ["" + many]),
			[sheet.translate(Locale.CHORDS_MOVE), sheet.translate(Locale.CHORDS_REMOVE),
			sheet.translate(Locale.CHORDS_KEEP)]);

		sheet.onAnswer = function(which:Int):Void thins(which, many);
	}

	/**
		Does what was answered, on the undo stack, so it is one step back to the import
		as the file wrote it.

		@param which Which answer: move them, remove them, or leave them.
		@param many How many notes that was about.
	**/
	function thins(which:Int, many:Int):Void {
		if (which != 0 && which != 1) return;

		final moves = which == 0;

		session.does(new mdd.song.edit.ThinChords(moves));
		session.says(moves ? Locale.SAID_CHORDS_MOVED : Locale.SAID_CHORDS_REMOVED,
			"" + many);

		changed();
	}

	/**
		Puts a piece at the top of the list the file menu offers, and drops the oldest
		where that makes it too long.

		@param where The file it was read from, which is empty for a piece never saved.
	**/
	function remembers(where:String):Void {
		if (where == "") return;

		recent.remove(where);
		recent.unshift(where);

		while (recent.length > RECENT) recent.pop();
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
		final notes = session == null ? 0 : session.notation;
		final palette = session == null ? 0 : session.partColours;
		final rightly = session == null ? Session.DELETES : session.rightClick;
		final following = session == null ? true : session.following;

		sound.stop();

		mdd.app.Formerly.origins(song, library);

		session = new Session(song);
		session.library = library;
		presence.follows(session);
		session.onChange = function(held:Session):Void changed();
		session.onReveal = function(found:mdd.check.Diagnostic):Void revealed(found);

		files.follows(session);
		remembers(files.path);

		session.master = held;
		session.automating = automates;
		session.snapping = snaps;
		session.notation = notes;
		session.partColours = palette;
		session.rightClick = rightly;
		session.following = following;

		panels.dress(session);
		menus.dress(session);
		bound();
		scoped();

		if (panels.preferences != null) session.transport.declick = panels.preferences.declick;

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

		if (menus != null && followingShown != session.following) {
			followingShown = session.following;
			relabel();
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

				stage.root.raise(panels.notice);
				panels.notice.arrive();
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

		A language whose face is not here is not spoken, whether the settings named it or
		the account's own language did: every word would draw as nothing. The first run
		sheet and the preferences still list it, with what picking it downloads.
	**/
	function spoken():Void {
		faces = new Faces(stage.fonts(), Faces.keptFolder());

		final held = settings.of("language", "");
		var code = held != "" && Languages.known(held) ? held : Languages.guessed();

		if (!faces.present(code)) code = Languages.first();

		Languages.speak(stage.root.translation, code);
		listed(code);
	}

	/**
		Gives both language lists what to call every language, in the language now in force.

		@param code Which language is spoken now.
	**/
	function listed(code:String):Void {
		final codes = Languages.shipped();
		final names = [for (held in codes) nameOf(held)];

		panels.preferences.speaks(codes, code, names);

		final welcome = panels.welcome;
		if (welcome != null) welcome.names = names;
	}

	/**
		@param code A language code.
		@return What a language list calls it: its own name, or, where its face is not here,
			its name in the language in force and how much picking it downloads.
	**/
	function nameOf(code:String):String {
		if (faces == null || faces.present(code)) return Languages.named(code);

		final key = Languages.called(code);
		final named = key < 0 ? code : stage.root.translate(key);
		final megabytes = Math.round(Faces.bytesOf(code) / 1048576);

		return Translation.filled(stage.root.translate(Locale.LANGUAGE_DOWNLOAD),
			[named, "" + megabytes]);
	}

	/**
		Starts fetching the face a picked language needs, where it is not here, and puts the
		lists back on the language being read until it lands.

		@param code The language that was picked.
		@return Whether a download stands in for the picking.
	**/
	function downloads(code:String):Bool {
		if (faces == null || faces.present(code)) return false;

		final now = stage.root.translation.language;

		listed(now);
		if (panels.welcome != null) panels.welcome.marks(now);

		if (!faces.fetches(code)) return true;

		final key = Languages.called(code);
		shows(Locale.WORKING_FONT, key < 0 ? code : stage.root.translate(key));
		session.changed();

		return true;
	}

	/**
		Moves the progress bar on while a face downloads.

		@param since How long since the last frame.
		@return Whether one is downloading.
	**/
	function facing(since:Float):Bool {
		if (faces == null || faces.state() != Faces.FETCHING) return false;

		task.holds(faces.pulling());
		progress.advance(since);

		return true;
	}

	/**
		Acts on a face download that has finished: speaks the language it was for, or says
		why it cannot.

		@return Whether anything happened.
	**/
	function faced():Bool {
		if (faces == null) return false;

		final now = faces.state();
		if (now == Faces.IDLE || now == Faces.FETCHING) return false;

		final code = faces.language;
		final key = Languages.called(code);
		final named = key < 0 ? code : stage.root.translate(key);

		faces.forget();
		settled();

		if (now != Faces.FETCHED) {
			session.says(now == Faces.BROKEN ? Locale.SAID_FONT_BROKEN : Locale.SAID_FONT_UNREACHABLE,
				named);
			session.changed();
			return true;
		}

		stage.refaced();
		Languages.speak(stage.root.translation, code);

		final welcome = panels.welcome;

		if (welcome != null && stage.root.sheet == welcome) {
			welcome.marks(code);
		} else {
			settings.put("language", code);
			keeps();
		}

		listed(code);
		relabel();
		stage.root.reshape();

		session.says(Locale.SAID_FONT_FETCHED, Languages.named(code));
		session.changed();
		return true;
	}

	/**
		Raises the first run sheet, which asks for a language.
	**/
	function greeting():Void {
		if (!firstRun) return;

		final welcome = new Welcome(session);
		panels.welcome = welcome;
		listed(stage.root.translation.language);

		welcome.onChoose = function(code:String):Void {
			if (downloads(code)) return;

			Languages.speak(stage.root.translation, code);
			listed(code);

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

	var renderingTo:String = "";
	var filming:Null<Filming> = null;

	/**
		Starts a bounce on a worker thread and puts the progress bar up in the band.

		@param where The file to write.
	**/
	function renders(where:String):Void {
		renderingTo = where;
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
		if (filming != null) return filmed(since);
		if (rendering == null) return false;

		final held = rendering;
		final moving = files.mixing.moving();

		bounce.holds(moving ? held.reach() * 0.5 : held.reach());

		progress.advance(since);

		if (!files.wroteYet()) return true;

		rendering = null;

		final wrong = files.wroteWrong;
		final beaten = wrong == "" && held.stopped();

		if (moving && wrong == "" && !beaten) {
			films(held);
			return true;
		}

		if (wrong != "") session.says(Locale.SAID_FAILED, wrong);
		else if (beaten) session.says(Locale.SAID_STOPPED);
		else session.saying(files.wroteKey, files.wroteWith);

		bounce.ends(wrong == "" && !beaten);
		stage.root.bands(null);

		session.changed();
		return true;
	}

	/**
		How much of a frame drawing the video may take before the window is drawn, in seconds.
		The progress bar is the only thing moving while it runs, so it can take most of one.
	**/
	static inline final FILMING = 0.030;

	/**
		Starts drawing the scope over a mix that has finished rendering, into the video file.

		@param made The finished mix.
	**/
	function films(made:mdd.play.Mixdown):Void {
		final where = Files.suffixed(renderingTo, files.mixing.suffix());
		final baked = stage.bakes(files.mixing.tall() / Filming.DESIGNED);
		final sizes = baked == null ? stage.root.metrics : baked;

		final held = new Filming(stage.root, stage.paint, sizes, session, session.song,
			files.mixing, made, where);

		filming = held;
		progress.onCancel = function():Void held.stops();
	}

	/**
		Draws as many video frames as fit in part of a frame, and finishes the file once the last
		one is drawn or the export is cancelled.

		@param since How long since the last frame.
		@return Always true, since a video is still being written whenever this is asked.
	**/
	function filmed(since:Float):Bool {
		final held = filming;
		if (held == null) return false;

		progress.advance(since);

		if (held.step(FILMING)) {
			bounce.holds(0.5 + held.reach() * 0.5);
			return true;
		}

		filming = null;

		final wrong = held.finish();
		final beaten = wrong == "" && held.stopped;

		stage.shuts(held.sizes);

		if (wrong != "") session.says(Locale.SAID_FAILED, wrong);
		else if (beaten) session.says(Locale.SAID_STOPPED);
		else {
			session.says(Locale.SAID_WROTE_AUDIO, "" + (Math.round(held.seconds() * 10) / 10),
				Files.name(held.path), "" + Math.round(held.size() / 1024));
		}

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

		if (monitoring == MONITOR_OFF) {
			usageSaid = "";
			return usageSaid;
		}

		final cpu = Usage.cpu();
		final ram = Usage.ram();

		if (cpu < 0 && ram < 0) {
			usageSaid = "";
			return usageSaid;
		}

		var held = "cpu " + Math.round(cpu) + "%   ram " + Math.round(ram) + " MB";

		if (monitoring == MONITOR_EVERYTHING) {
			final peak = Usage.peak();
			if (peak >= 0) held += "   peak " + Math.round(peak) + " MB";
		}

		final gpu = Usage.gpu();
		if (gpu >= 0) held += "   gpu " + Math.round(gpu) + "%";

		if (monitoring == MONITOR_EVERYTHING) {
			final vram = Usage.vram();
			if (vram >= 0) held += "   vram " + Math.round(vram) + " MB";
		}

		final render = sound.render;

		if (render != null && render.rate > 0 && render.leastHeld > 0) {
			held += "   ring " + Math.round(render.leastHeld * 1000.0 / render.rate) + " ms";
		}

		if (monitoring == MONITOR_EVERYTHING && stage.renderer != null) {
			held += "   " + (Sdl.rendererName(stage.renderer) : String);
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
		What the presets folder held when it was last read, so coming back to the window
		reads it again only where something in it changed.
	**/
	var presetsStamp:String = "";

	/**
		Reads the presets folder again where anything in it has changed since it was
		last read, which is what lets a subfolder made in the file manager show up as a
		bank without a restart.
	**/
	function rereads():Void {
		if (files == null || session == null) return;
		if (files.presetsStamp() == presetsStamp) return;

		rescanned();
	}

	/**
		Reads the presets folder from nothing, from the cache where the folder has not changed
		since it was written, and has the browser offer what it holds. Nothing is copied into the
		piece: a preset reaches it when it is loaded.
	**/
	function rescanned():Void {
		final folder = new mdd.song.Library();
		final where = files.within("presets");
		final stamp = files.presetsStamp();
		final cache = files.cache("presets");

		if (folder.cached(cache, stamp) < 0) {
			folder.within(where, files.savedInto);
			folder.caches(cache, stamp);
		}

		library.forgets();
		library.takes(folder);
		presetsStamp = stamp;

		added.sees(library, Date.now().getTime() / 1000);
		session.changed();
	}

	/**
		Points the browser's presets folder at the one chosen, with what is deleted going into the
		backups.
	**/
	function shelves():Void {
		final keeper = files.presetFolder();

		presetFolder.root = keeper.root;
		presetFolder.bin = keeper.bin;
	}

	/**
		Asks what to do about a file being imported that holds presets the library already holds,
		and imports it the way the answer says.

		@param where The file.
		@param held What it holds.
		@param twins How many of those the library already holds.
	**/
	function duplicated(where:String, held:mdd.format.Banked, twins:Int):Void {
		final sheet = panels.asking;

		if (sheet == null) {
			files.imports(where, held, Files.IMPORT_ALL);
			return;
		}

		stage.root.raise(sheet);

		sheet.ask(sheet.translate(Locale.PRESET_DUPLICATES),
			sheet.filled(Locale.PRESET_DUPLICATES_SAID, ["" + twins, "" + held.presets.length,
				held.name == "" ? Files.name(where) : held.name]),
			[sheet.translate(Locale.PRESET_IMPORT_ANYWAY), sheet.translate(Locale.PRESET_SKIP_DUPLICATES),
				sheet.translate(Locale.PRESET_COMBINE_TAGS), sheet.translate(Locale.EXPORT_CANCEL)]);

		sheet.onAnswer = function(which:Int):Void {
			final how = switch (which) {
				case 0: Files.IMPORT_ALL;
				case 1: Files.SKIP_DUPLICATES;
				case 2: Files.COMBINE_TAGS;
				case _: -1;
			}

			if (how < 0) return;

			files.imports(where, held, how);
			changed();
		};
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
				shelves();
				rescanned();
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
		final watching = settings.asWhole("hostMonitor", MONITOR_PLAIN);

		recent.resize(0);

		for (held in settings.of("recent", "").split("|")) {
			if (held != "" && sys.FileSystem.exists(held)) recent.push(held);
			if (recent.length >= RECENT) break;
		}

		monitoring = watching < MONITOR_OFF || watching > MONITOR_EVERYTHING
			? MONITOR_PLAIN : watching;

		usageAt = 0;
		usageSaid = "";
		final automating = settings.asWhole("automating", Session.LANES);
		final snapping = settings.asWhole("snapping", Session.SIXTEENTH);

		files.projectsAt = settings.of("projects", "");
		files.presetsAt = settings.of("presets", "");
		files.savedInto = stage.root.translate(Locale.PRESET_SAVED);
		files.importedInto = stage.root.translate(Locale.PRESET_IMPORTED);
		shelves();

		files.onDuplicates = function(where:String, held:mdd.format.Banked, twins:Int):Void
			duplicated(where, held, twins);
		files.onShelved = function():Void rereads();

		favourites.reads(settings.of("favourites", ""));

		favourites.onChange = function():Void {
			settings.put("favourites", favourites.spelt());
			settings.save();
		};

		final dated = files.cache("added");

		try {
			if (sys.FileSystem.exists(dated)) added.reads(sys.io.File.getContent(dated));
		} catch (e:Dynamic) {}

		added.onChange = function():Void {
			try {
				sys.io.File.saveContent(dated, added.spelt());
			} catch (e:Dynamic) {}
		};

		panels.presetView = settings.of("presetView", "");

		if (panels.inspector != null) {
			panels.inspector.presets.reads(panels.presetView);
			panels.inspector.presets.fit();
		}

		panels.onPresetView = function(said:String):Void {
			settings.put("presetView", said);
			settings.save();
		};

		if (!settings.asFlag("presetsSorted", false)) {
			final moved = files.sortsPresets();

			settings.flag("presetsSorted", true);
			if (moved > 0) session.says(Locale.SAID_PRESETS_SORTED, "" + moved);
		}

		rescanned();

		if (!settings.asFlag("starsBySound", false)) {
			mdd.app.Formerly.stars(favourites, library);
			settings.flag("starsBySound", true);
		}

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
		session.notation = settings.asWhole("notation", 0) & 3;
		panels.kitting.notation = session.notation;
		session.master = Session.UNITY;

		sound.monitors(Session.gainOf(session.master));
		session.automating = automating == Session.CLIPS ? Session.CLIPS : Session.LANES;
		session.rightClick = settings.asWhole("rightClick", Session.DELETES) == Session.OPENS
			? Session.OPENS : Session.DELETES;
		session.snapping = snapping < 0 ? Session.SIXTEENTH : snapping;
		session.following = settings.asFlag("following", true);

		stage.root.theme.wear(which);
		session.partColours = settings.asWhole("partColours", 0) == mdd.ui.Theme.SAFE
			? mdd.ui.Theme.SAFE : mdd.ui.Theme.STANDARD;
		stage.root.theme.chooses(session.partColours);
		stage.root.flow = motion;

		if (typeface != 0) redressed();

		panels.preferences.chose(Preferences.DENSITY, density);
		panels.preferences.chose(Preferences.TEXT_SIZE, settings.asWhole("textSize", 1));
		panels.preferences.chose(Preferences.TAIL, tail);
		panels.preferences.chose(Preferences.KEEPING, keeping);
		panels.preferences.chose(Preferences.BACKUPS, backups);
		panels.preferences.chose(Preferences.BACKUP_AGE, backupAge);
		panels.preferences.chose(Preferences.UPDATES, looks ? 1 : 0);
		panels.preferences.chose(Preferences.HOST_MONITOR, monitoring);
		panels.preferences.chose(Preferences.RIGHT_CLICK, session.rightClick);

		keyboards();
		outputs();

		panels.preferences.chose(Preferences.CONSOLE,
			settings.asWhole("console", mdd.play.Render.MODEL_ONE));

		panels.preferences.chose(Preferences.DECLICK, settings.asFlag("declick", true) ? 1 : 0);

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
		Puts the kept speed and accuracy on the scope, tells it the rate the device plays at,
		and has it keep the settings when either is changed.

		Loading a song builds the panels again, and the scope with them, so this runs after
		every build of the panels rather than once at start. Run only once, the scope a song
		opened into was back at its defaults and kept nothing that was changed on it.
	**/
	function scoped():Void {
		final scope = panels.centre.scope;

		if (sound.render != null) scope.rated(sound.render.rate);
		if (settings == null) return;

		scope.paces(settings.asWhole("scopeSpeed", mdd.view.monitor.Scope.SPEED));
		scope.refines(settings.asWhole("scopeAccuracy", mdd.view.monitor.Scope.ACCURACY));
		scope.onChange = function():Void keeps();
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
		settings.whole("notation", session.notation);
		settings.whole("partColours", session.partColours);
		settings.whole("motion", session.motion);
		settings.whole("automating", session.automating);
		settings.whole("rightClick", session.rightClick);
		settings.whole("snapping", session.snapping);
		settings.flag("following", session.following);
		settings.whole("density", panels.preferences.density);
		settings.whole("textSize", panels.preferences.textSize);
		settings.whole("tail", panels.preferences.tail);
		settings.whole("keeping", panels.preferences.keeping);
		settings.whole("backups", panels.preferences.backups);
		settings.whole("backupAge", panels.preferences.backupAge);
		settings.whole("scopeSpeed", panels.centre.scope.speed);
		settings.whole("scopeAccuracy", panels.centre.scope.accuracy);
		if (stage.shown) settings.flag("maximised", stage.maximised());
		settings.whole("width", Sdl.windowWidth(stage.window));
		settings.whole("height", Sdl.windowHeight(stage.window));
		settings.put("recent", recent.join("|"));
		settings.whole("hostMonitor", monitoring);
		settings.put("language", stage.root.translation.language);
		settings.put("midi", midiSaid);
		settings.put("output", outputSaid);
		settings.whole("midiChannel", panels.preferences.keyboardChannel);
		settings.whole("midiVelocity", panels.preferences.keyboardVelocity);
		settings.whole("console", panels.preferences.console);
		settings.flag("declick", panels.preferences.declick);
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
			case Bindings.NEW: guards(function():Void fresh());
			case Bindings.OPEN: asks(Files.OPEN);
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
			case Bindings.DOUBLE: return edited(mdd.ui.Edit.DOUBLE);
			case Bindings.FOLLOW: panels.centre.tools.press(mdd.view.Tools.FOLLOW);
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
	/**
		Sends an editing command to whatever should take it.

		The keyboard is where it goes first. Where nothing has the keyboard, which is
		what pressing anywhere that does not take it leaves, it goes to the editor in
		front instead: a reader who presses select all is asking the thing they are
		looking at to select all, and nothing at all is the wrong answer.

		@param what One of the `Edit` values.
		@return Whether anything took it.
	**/
	function edited(what:Int):Bool {
		if (stage.root.edits(what)) return true;

		if (stage.root.focus != null || panels.centre == null) return false;

		final editor = panels.centre.editing();
		return editor != null && editor.enabled && editor.edited(what);
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
				if (!stage.took(event)) quits();
			}

			if (!running) break;

			final now = Sdl.ticks();
			var since = now - last;
			last = now;
			if (since > 0.100) since = 0.100;

			if (keyed()) stage.root.soil();

			stage.root.advance(since);
			if (files != null && files.poll()) {
				written();
				stage.root.soil();
			}
			folded();
			if (rendered(since) || pulling(since) || facing(since)) stage.root.soil();
			if (files != null && files.tick(since)) stage.root.soil();
			if (watched() || faced()) stage.root.soil();
			watch();

			final showing = bounce.running() ? bounce : task;
			presence.busy = showing.running() ? stage.root.translate(showing.label) : "";
			presence.tick(since);

			if (shared()) stage.root.soil();
			if (costed()) stage.root.soil();
			if (received()) stage.root.soil();

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
		if (panels != null && panels.exportingVideo != null) panels.exportingVideo.follows(which);
	}

	/**
		Switches whether playback smooths the edges the parts would otherwise click on, and tells
		the export panels so they keep their own rather than following this.

		@param declick Whether to smooth them.
	**/
	function declicked(declick:Bool):Void {
		if (session != null) session.transport.declick = declick;
		if (panels != null && panels.exporting != null) panels.exporting.declicks(declick);
		if (panels != null && panels.exportingVideo != null) panels.exportingVideo.declicks(declick);
	}

	/**
		Fills the audio device choices with what the system has now, and marks the one in use.
	**/
	function outputs():Void {
		final held = panels.preferences.outputs;

		held.resize(0);
		held.push(stage.root.translate(Locale.AUDIO_DEFAULT));

		for (name in mdd.app.Sound.devices()) held.push(name);

		final at = held.indexOf(outputSaid);
		panels.preferences.sounds(outputSaid == "" || at < 0 ? 0 : at);
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
		The playback device the sound goes to, by name, or an empty string for the system default.
	**/
	var outputSaid:String = "";

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
		Keeps the line the preferences sheet shows for Discord presence in step with what the
		presence is doing, while that sheet is up.

		@return Whether the line changed, so the frame needs drawing again.
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
