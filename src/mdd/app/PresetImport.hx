package mdd.app;

import mdd.host.Sdl;
import mdd.ui.Translation;

@:unreflective

/**
	A preset file or a bank file opened from the desktop while the application is not running,
	imported without opening a window.

	It asks the questions an import in the window asks, in the desktop's own boxes: what to do with
	presets the library already holds, and then what came of it, with a choice to open the
	application or leave it closed. The import is the one `Files.imports` makes, so a file opened
	this way lands exactly where one dropped on the window would.

	While the application is running, the file is handed to the copy that is running instead, which
	imports it and says what came of it in a sheet of its own.
**/
final class PresetImport {
	/**
		@param args What the application was started with.
		@return The first preset or bank file among them, or an empty string where there is none,
			or where it was also asked to export, which a window has to do.
	**/
	public static function argument(args:Array<String>):String {
		for (arg in args) if (StringTools.startsWith(arg, "--export")) return "";

		for (arg in args) {
			if (StringTools.startsWith(arg, "-") || !sys.FileSystem.exists(arg)) continue;

			final suffix = haxe.io.Path.extension(arg).toLowerCase();
			if (suffix == mdd.Config.PRESET || suffix == mdd.Config.BANK) return arg;
		}

		return "";
	}

	/**
		Imports a file with no window, asking in the desktop's own boxes.

		@param path The file.
		@return Whether the reader asked for the application to be opened afterwards.
	**/
	public static function runs(path:String):Bool {
		final settings = new mdd.host.Settings();
		settings.load();

		final said = new Translation();
		final held = settings.of("language", "");
		final code = held != "" && Languages.known(held) ? held : Languages.guessed();

		if (Languages.speak(said, code) == 0) Languages.speak(said, Languages.first());

		final library = mdd.song.Library.embedded();
		final files = new Files(Session.started(library));

		files.presetsAt = settings.of("presets", "");
		files.savedInto = said.of(Locale.PRESET_SAVED);
		files.importedInto = said.of(Locale.PRESET_IMPORTED);

		final folder = new mdd.song.Library();
		folder.within(files.within("presets"), files.savedInto);

		library.takes(folder);
		files.library = library;

		final name = Files.name(path);
		final opening = Translation.filled(said.of(Locale.PRESET_OPEN_NOW), [mdd.Config.TITLE]);

		var bank:Null<mdd.format.Banked> = null;

		try {
			bank = mdd.format.Preset.read(sys.io.File.getBytes(path));
		} catch (e:Dynamic) {}

		if (bank == null || bank.presets.length == 0) {
			return asks(said, Translation.filled(said.of(Locale.PRESET_IMPORT_FAILED),
				[name, said.of(Locale.SAID_NOT_PRESETS)]) + "\n\n" + opening, true);
		}

		var how = Files.IMPORT_ALL;
		final twins = files.duplicates(bank);

		if (twins > 0) {
			final answer = Sdl.ask(said.of(Locale.PRESET_DUPLICATES),
				Translation.filled(said.of(Locale.PRESET_DUPLICATES_SAID), ["" + twins,
					"" + bank.presets.length, bank.name == "" ? name : bank.name]),
				said.of(Locale.PRESET_IMPORT_ANYWAY), said.of(Locale.PRESET_SKIP_DUPLICATES),
				said.of(Locale.PRESET_COMBINE_TAGS), said.of(Locale.EXPORT_CANCEL), 0);

			if (answer < 0 || answer > 2) return asks(said, opening, false);

			how = answer == 1 ? Files.SKIP_DUPLICATES : (answer == 2 ? Files.COMBINE_TAGS : Files.IMPORT_ALL);
		}

		var outcome = "";
		var failed = false;

		files.onImported = function(named:String, many:Int, single:Bool):Void {
			failed = many < 0;
			outcome = told(said, named, many, single, files.within("presets"));
		};

		files.imports(path, bank, how);

		return asks(said, outcome + "\n\n" + opening, failed);
	}

	/**
		@param said The words, in the reader's language.
		@param named What was imported.
		@param many How many presets were written, nought for nothing new and -1 where nothing
			could be written.
		@param single Whether it was one preset rather than a bank.
		@param folder The presets folder, which a failure names.
		@return What to tell the reader.
	**/
	public static function told(said:Translation, named:String, many:Int, single:Bool,
			folder:String):String {
		if (many < 0) {
			return Translation.filled(said.of(Locale.PRESET_IMPORT_FAILED),
				[named, Translation.filled(said.of(Locale.SAID_PRESET_UNWRITTEN), [folder])]);
		}

		if (many == 0) return Translation.filled(said.of(Locale.PRESET_IMPORTED_NOTHING), [named]);
		if (single) return Translation.filled(said.of(Locale.PRESET_IMPORTED_PRESET), [named]);

		return Translation.filled(said.of(Locale.PRESET_IMPORTED_BANK), [named, "" + many]);
	}

	/**
		Asks whether to open the application.

		@param said The words, in the reader's language.
		@param question What the box says.
		@param fault Whether it is saying something went wrong.
		@return Whether the answer was to open it.
	**/
	static function asks(said:Translation, question:String, fault:Bool):Bool {
		return Sdl.ask(mdd.Config.TITLE, question, said.of(Locale.FILE_OPEN), said.of(Locale.PRESET_CLOSE),
			"", "", fault ? 1 : 0) == 0;
	}
}
