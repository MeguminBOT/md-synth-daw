package mdd.app;

import mdd.format.Banked;
import mdd.format.Preset;
import mdd.host.Paths;
import mdd.song.Instrument;
import mdd.song.Library;
import mdd.song.Sample;
import sys.FileSystem;

@:unreflective

/**
	The reader's presets folder, changed from the application: a preset renamed, retagged, given
	an icon, copied or moved into another category or deleted, and a category made, renamed,
	tagged or deleted.

	Every change is a change to the files, so the folder and the browser never disagree and what a
	reader does in the file manager and what they do here are the same thing. A preset that lives in
	a patch file or a document, which cannot carry what it is being given, is written out as a
	preset file in its place. Nothing is erased: what is deleted is moved into the backups, where a
	reader can take it back by hand.

	It changes files and nothing else. The library is read again afterwards by whoever asked, which
	is what makes the change show.
**/
final class PresetFolder {
	/**
		The presets folder.
	**/
	public var root:String;

	/**
		Where what is deleted goes.
	**/
	public var bin:String;

	/**
		Builds one.

		@param root The presets folder.
		@param bin Where what is deleted goes.
	**/
	public function new(root:String, bin:String) {
		this.root = root;
		this.bin = bin;
	}

	/**
		Renames a preset in the file it lives in, and renames a file that holds it alone to match.

		@param library The library, as last read.
		@param at The preset's bank, by position.
		@param which The preset, by position in the bank.
		@param name What to call it.
		@return Whether the file was written.
	**/
	public function renames(library:Library, at:Int, which:Int, name:String):Bool {
		final said = StringTools.trim(name);
		if (said == "") return false;

		return changes(library, at, which, function(held:Instrument):Void held.name = said, said);
	}

	/**
		Gives a preset new tags in the file it lives in.

		@param library The library, as last read.
		@param at The preset's bank, by position.
		@param which The preset, by position in the bank.
		@param tags Its tags now.
		@return Whether the file was written.
	**/
	public function retags(library:Library, at:Int, which:Int, tags:Array<String>):Bool {
		return changes(library, at, which, function(held:Instrument):Void {
			held.tags.resize(0);
			for (tag in tags) if (StringTools.trim(tag) != "") held.tags.push(StringTools.trim(tag));
		}, "");
	}

	/**
		Gives a preset another icon in the file it lives in.

		@param library The library, as last read.
		@param at The preset's bank, by position.
		@param which The preset, by position in the bank.
		@param icon The icon, or -1 for none.
		@return Whether the file was written.
	**/
	public function reicons(library:Library, at:Int, which:Int, icon:Int):Bool {
		return changes(library, at, which, function(held:Instrument):Void held.icon = icon, "");
	}

	/**
		Takes a preset out of the file it lives in, and moves a file left holding nothing into the
		backups.

		@param library The library, as last read.
		@param at The preset's bank, by position.
		@param which The preset, by position in the bank.
		@return Whether it was taken out.
	**/
	public function deletes(library:Library, at:Int, which:Int):Bool {
		final path = pathOf(library, at, which);
		final held = loaded(path);
		if (held == null) return false;

		final found = findIn(held, library.instruments[at][which]);
		if (found < 0) return false;

		if (held.presets.length == 1) return binned(path);

		held.presets.splice(found, 1);
		held.samples.splice(found, 1);

		return saves(path, held, "") != "";
	}

	/**
		Writes a copy of a preset into a folder as a preset file of its own.

		@param preset The preset.
		@param sample What it plays, or null.
		@param folder The folder.
		@return Where it was written, or an empty string where it could not be.
	**/
	public function copies(preset:Instrument, sample:Null<Sample>, folder:String):String {
		final made = preset.copy();

		made.sample = -1;
		made.from = "";

		final named = free(folder, Files.safely(made.name), Preset.SUFFIX);

		try {
			Paths.make(folder);
			sys.io.File.saveBytes(named, Preset.write("", [made], [sample]));
		} catch (e:Dynamic) {
			return "";
		}

		return named;
	}

	/**
		Moves a preset into another folder: a copy there, and taken out of where it was.

		@param library The library, as last read.
		@param at The preset's bank, by position.
		@param which The preset, by position in the bank.
		@param folder The folder it goes to.
		@return Whether it moved.
	**/
	public function moves(library:Library, at:Int, which:Int, folder:String):Bool {
		final path = pathOf(library, at, which);
		if (path == "" || haxe.io.Path.directory(path) == folder) return false;

		final held = loaded(path);
		if (held == null) return false;

		final found = findIn(held, library.instruments[at][which]);
		if (found < 0) return false;

		if (held.presets.length == 1 && held.name == "") {
			final named = free(folder, Files.bare(path), suffix(path));

			try {
				Paths.make(folder);
				FileSystem.rename(path, named);
				return true;
			} catch (e:Dynamic) {}
		}

		if (copies(held.presets[found], held.samples[found], folder) == "") return false;

		return deletes(library, at, which);
	}

	/**
		Makes a category: a folder of its own under the family's folder.

		@param family The family's folder name, as `Part.family` names it.
		@param name What to call it.
		@return The folder, or an empty string where it could not be made or the name is taken.
	**/
	public function makes(family:String, name:String):String {
		final said = Files.safely(StringTools.trim(name));
		final folder = root + "/" + family + "/" + said;

		if (StringTools.trim(name) == "" || FileSystem.exists(folder)) return "";

		Paths.make(folder);
		return FileSystem.exists(folder) ? folder : "";
	}

	/**
		Renames a category's folder.

		@param folder The folder.
		@param name What to call it.
		@return The folder it is now, or an empty string where the name is taken or it would not go.
	**/
	public function renamesFolder(folder:String, name:String):String {
		final said = Files.safely(StringTools.trim(name));
		final to = haxe.io.Path.directory(folder) + "/" + said;

		if (StringTools.trim(name) == "" || FileSystem.exists(to)) return "";

		try {
			FileSystem.rename(folder, to);
		} catch (e:Dynamic) {
			return "";
		}

		return to;
	}

	/**
		Renames a bank that is one file, in the file.

		@param path The bank file.
		@param name What to call it.
		@return Whether it was written.
	**/
	public function renamesBank(path:String, name:String):Bool {
		final held = loaded(path);
		final said = StringTools.trim(name);

		if (held == null || said == "") return false;

		held.name = said;
		return saves(path, held, said) != "";
	}

	/**
		Gives a category its own tags: in a `.tags` file inside a folder, or in a bank file's own
		first bytes.

		@param where The folder, or the bank file.
		@param tags Its tags now.
		@return Whether they were written.
	**/
	public function tagsCategory(where:String, tags:Array<String>):Bool {
		final kept:Array<String> = [];
		for (tag in tags) if (StringTools.trim(tag) != "") kept.push(StringTools.trim(tag));

		if (FileSystem.exists(where) && FileSystem.isDirectory(where)) {
			final file = where + "/" + Library.TAGS;

			try {
				if (kept.length == 0) {
					if (FileSystem.exists(file)) FileSystem.deleteFile(file);
				} else {
					sys.io.File.saveContent(file, kept.join("\n") + "\n");
				}
			} catch (e:Dynamic) {
				return false;
			}

			return true;
		}

		final held = loaded(where);
		if (held == null) return false;

		held.tags.resize(0);
		for (tag in kept) held.tags.push(tag);

		return saves(where, held, "") != "";
	}

	/**
		Deletes a category: moves its folder, or its bank file, into the backups.

		@param where The folder, or the bank file.
		@return Whether it went.
	**/
	public function deletesCategory(where:String):Bool {
		return binned(where);
	}

	/**
		Changes one preset in the file it lives in, writing the file again as a preset file where
		it was a patch file or a document.

		@param library The library, as last read.
		@param at The preset's bank, by position.
		@param which The preset, by position in the bank.
		@param change What to do to it.
		@param named What a file holding it alone is called afterwards, or an empty string to keep
			the name it has.
		@return Whether the file was written.
	**/
	function changes(library:Library, at:Int, which:Int, change:Instrument -> Void,
			named:String):Bool {
		final path = pathOf(library, at, which);
		final held = loaded(path);
		if (held == null) return false;

		final found = findIn(held, library.instruments[at][which]);
		if (found < 0) return false;

		change(held.presets[found]);

		final alone = held.presets.length == 1 && held.name == "";
		return saves(path, held, alone ? named : "") != "";
	}

	/**
		@param library The library.
		@param at A bank, by position.
		@param which A preset in it, by position.
		@return The file it lives in, or an empty string where it lives in none.
	**/
	static function pathOf(library:Library, at:Int, which:Int):String {
		if (at < 0 || at >= library.paths.length) return "";

		final held = library.paths[at];
		return which < 0 || which >= held.length ? "" : held[which];
	}

	/**
		@param held What a file holds.
		@param preset A preset read out of it.
		@return Where the file holds that preset: by sound and name, or by sound alone, or -1.
	**/
	static function findIn(held:Banked, preset:Instrument):Int {
		var sounding = -1;

		for (index in 0...held.presets.length) {
			final one = held.presets[index];
			if (one.identifies(held.samples[index]) != preset.id) continue;

			if (one.name == preset.name) return index;
			if (sounding < 0) sounding = index;
		}

		return sounding;
	}

	/**
		Reads any file a presets folder holds into what it carries.

		@param path The file.
		@return Its presets and what each plays, or null where it will not read.
	**/
	static function loaded(path:String):Null<Banked> {
		if (path == "" || !FileSystem.exists(path)) return null;

		final lower = path.toLowerCase();

		try {
			if (StringTools.endsWith(lower, Library.RECORDS) || StringTools.endsWith(lower, Library.BANK)) {
				return Preset.read(sys.io.File.getBytes(path));
			}

			if (StringTools.endsWith(lower, Library.PATCH)) {
				final patch = mdd.format.Tfi.read(sys.io.File.getBytes(path));
				if (patch == null) return null;

				final one = new Instrument(Files.bare(path), mdd.song.Part.Fm1);

				one.patch = patch;
				one.icon = mdd.Icon.NAMES.indexOf("synthesizer");

				final out = new Banked();
				out.add(one, null);

				return out;
			}

			if (StringTools.endsWith(lower, Library.SUFFIX)) {
				final said = sys.io.File.getContent(path);
				final node = mdd.format.Json.parse(said);
				final named = node == null ? "" : node.get("name").saying("");

				final library = new Library();
				library.reads(said, true, "-");

				final at = library.names.indexOf(named == "" ? "-" : named);
				if (at < 0) return null;

				final out = new Banked();
				out.name = named;

				for (index in 0...library.instruments[at].length) {
					out.add(library.instruments[at][index], library.samples[at][index]);
				}

				return out;
			}
		} catch (e:Dynamic) {}

		return null;
	}

	/**
		Writes what a file holds back as records: over the file itself where it is a preset or bank
		file, and beside it where it was a patch file or a document, which then goes into the
		backups.

		@param path The file it came from.
		@param held What it holds now.
		@param named What a file holding one preset alone is called afterwards, or an empty string
			to keep the name it has.
		@return Where it was written, or an empty string where it could not be.
	**/
	function saves(path:String, held:Banked, named:String):String {
		final lower = path.toLowerCase();
		final records = StringTools.endsWith(lower, Library.RECORDS)
			|| StringTools.endsWith(lower, Library.BANK);
		final folder = haxe.io.Path.directory(path);
		final bank = held.name != "" || held.presets.length > 1;
		final end = bank ? Library.BANK : Library.RECORDS;
		final stem = named == "" ? Files.bare(path) : Files.safely(named);

		var to = records && named == "" ? path : folder + "/" + stem + (records ? suffix(path) : end);

		if (to != path && FileSystem.exists(to)) to = free(folder, stem, records ? suffix(path) : end);

		final bytes = Preset.write(held.name, held.presets, held.samples, held.tags);
		final aside = to + ".part";

		try {
			sys.io.File.saveBytes(aside, bytes);

			if (FileSystem.exists(to)) FileSystem.deleteFile(to);
			FileSystem.rename(aside, to);
		} catch (e:Dynamic) {
			try {
				if (FileSystem.exists(aside)) FileSystem.deleteFile(aside);
			} catch (e:Dynamic) {}

			return "";
		}

		if (to != path) {
			if (records) {
				try {
					FileSystem.deleteFile(path);
				} catch (e:Dynamic) {}
			} else {
				binned(path);
			}
		}

		return to;
	}

	/**
		Moves a file or a folder into the backups, under its own name and when it went.

		@param path What to move.
		@return Whether it went.
	**/
	function binned(path:String):Bool {
		if (path == "" || !FileSystem.exists(path)) return false;

		final stamp = DateTools.format(Date.now(), "%Y%m%d-%H%M%S");
		final named = haxe.io.Path.withoutDirectory(path);
		final dot = named.lastIndexOf(".");
		final to = bin + "/" + (dot > 0 ? named.substr(0, dot) + "-" + stamp + named.substr(dot)
			: named + "-" + stamp);

		Paths.make(bin);

		try {
			FileSystem.rename(path, to);
			return true;
		} catch (e:Dynamic) {}

		try {
			copied(path, to);
			Paths.clear(path);
		} catch (e:Dynamic) {
			return false;
		}

		return !FileSystem.exists(path);
	}

	/**
		Copies a file, or a folder and everything in it.

		@param from What to copy.
		@param to Where it goes.
	**/
	static function copied(from:String, to:String):Void {
		if (!FileSystem.isDirectory(from)) {
			sys.io.File.copy(from, to);
			return;
		}

		Paths.make(to);

		for (name in FileSystem.readDirectory(from)) copied(from + "/" + name, to + "/" + name);
	}

	/**
		@param folder A folder.
		@param stem What a file in it should be called, without its suffix.
		@param end Its suffix, with the dot.
		@return A path in the folder no file takes: the name itself, or it with a number after.
	**/
	static function free(folder:String, stem:String, end:String):String {
		var named = folder + "/" + stem + end;
		var at = 2;

		while (FileSystem.exists(named)) {
			named = folder + "/" + stem + " " + at + end;
			at++;
		}

		return named;
	}

	/**
		@param path A file.
		@return Its suffix with the dot, in lower case.
	**/
	static function suffix(path:String):String {
		final held = haxe.io.Path.extension(path);
		return held == "" ? "" : "." + held.toLowerCase();
	}
}
