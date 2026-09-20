package mdd.app;

import haxe.ds.Vector;
import mdd.format.Midi;
import mdd.format.Project;
import mdd.format.Strand;
import mdd.format.Transcription;
import mdd.format.Vgm;
import mdd.format.Wav;
import mdd.format.Coded;
import mdd.format.Flac;
import mdd.format.Xgm;
import mdd.host.Chooser;
import mdd.host.Dialog;
import mdd.host.Paths;
import mdd.host.Window;
import mdd.play.Render;
import mdd.play.Mixdown;
import mdd.play.Mixing;
import mdd.play.Sequencer;
import mdd.play.Stream;
import mdd.song.Song;
import sys.FileSystem;
import mdd.song.Tempo;

@:unreflective

/**
	Everything that reads or writes a file: opening, saving, importing, exporting,
	saving on its own, and the backups.

	A dialog is asked for rather than blocked on, so the interface keeps drawing and
	the audio keeps playing while one is open. There is one of these for the life of
	the application and loading a song calls `follows` rather than building another:
	rebuilding it once dropped every callback nobody re-attached, and a null render
	callback is not an error but a bounce that runs on the main thread.
**/
final class Files {
	/**
		No dialog is open.
	**/
	public static inline final NOTHING = 0;

	/**
		Dialog: open a project.
	**/
	public static inline final OPEN = 1;

	/**
		Dialog: save a project.
	**/
	public static inline final SAVE = 2;

	/**
		Dialog: export a register log.
	**/
	public static inline final VGM = 3;

	/**
		Dialog: export a wave file.
	**/
	public static inline final WAV = 4;

	/**
		Dialog: export a midi file.
	**/
	public static inline final MIDI = 5;

	/**
		Dialog: import a register log.
	**/
	public static inline final READ_VGM = 6;

	/**
		Dialog: import a midi file.
	**/
	public static inline final READ_MIDI = 7;

	/**
		Dialog: import a sample.
	**/
	public static inline final READ_WAV = 8;

	/**
		Dialog: export a driver file.
	**/
	public static inline final XGM = 9;

	/**
		Dialog: import one.
	**/
	public static inline final READ_XGM = 10;

	/**
		Dialog: export audio.
	**/
	public static inline final AUDIO = 11;

	/**
		Dialog: export a patch.
	**/
	public static inline final TFI = 12;

	/**
		Dialog: import one.
	**/
	public static inline final READ_TFI = 13;

	/**
		Dialog: a folder of recordings to make a kit out of.
	**/
	public static inline final READ_KIT = 14;

	/**
		Dialog: one recording to add to the kit being made.
	**/
	public static inline final READ_HIT = 15;

	/**
		Dialog: writing a preset out as a patch file.
	**/
	public static inline final PRESET_TFI = 16;

	/**
		Dialog: writing what a converter preset plays out as a wave file.
	**/
	public static inline final PRESET_WAV = 17;

	/**
		Dialog: writing a whole bank out as one file.
	**/
	public static inline final PRESET_BANK = 18;

	/**
		Dialog: reading a preset file or a bank file into the piece.
	**/
	public static inline final READ_PRESETS = 19;

	/**
		Which preset the next preset dialog is about, by index into the song, or which bank for a
		bank dialog. It is set before the dialog is asked for and read when it answers.
	**/
	public var chosen:Int = -1;

	/**
		The rate an import is measured at.
	**/
	public static inline final RATE = 44100;
	static inline final DAC_RATE = 8000;

	/**
		Where the piece was last saved, or an empty string where it never was.
	**/
	public var path(default, null):String = "";

	/**
		Which dialog is open.
	**/
	public var asking(default, null):Int = NOTHING;

	/**
		How often to save on its own, in seconds, or nought for never.
	**/
	public var every:Float = 0;

	/**
		How long since the last one.
	**/
	public var since(default, null):Float = 0;

	/**
		How many times it has saved on its own.
	**/
	public var kept(default, null):Int = 0;

	/**
		Where a piece that was never saved by hand went, so it is not lost.
	**/
	public var recovered(default, null):String = "";

	/**
		How much room the backups may take before the oldest are removed.
	**/
	public var backupRoom:Float = 250 * 1024 * 1024;

	/**
		How long a backup is kept.
	**/
	public var backupDays:Int = 30;

	/**
		Where a dialog starts looking for projects.
	**/
	public var projectsAt:String = "";

	/**
		Where it starts looking for presets.
	**/
	public var presetsAt:String = "";

	var stamp:Int = -1;

	/**
		Called when a piece has been read.
	**/
	public var onLoad:Null<Song -> Void> = null;

	/**
		Called with what a surveyed MIDI file holds, so a reader can say which of it to
		take and where each strand goes. Nothing has happened to the piece by the time
		this is called, and `takes` is what acts on the answer.
	**/
	public var onSurvey:Null<(String, Array<Strand>) -> Void> = null;

	/**
		Called with a kit read out of a folder, so a reader can say what it becomes.
		Nothing is written by the time this is called.
	**/
	public var onKit:Null<mdd.format.Kit -> Void> = null;

	/**
		Called with a folder to add to the kit that is open.
	**/
	public var onKitFolder:Null<String -> Void> = null;

	/**
		Called with one recording to add to the kit that is open.
	**/
	public var onHit:Null<String -> Void> = null;

	var midiBytes:Null<haxe.io.Bytes> = null;
	var midiName:String = "";

	/**
		The bank a preset saved from the browser or read out of a patch file goes into,
		named in the reader's language.
	**/
	public var savedInto:String = "";

	/**
		The preset library, where a preset written into the presets folder is put as
		well, so every piece opened afterwards offers it. Null in a check that has none.
	**/
	public var library:Null<mdd.song.Library> = null;

	/**
		Called when something long starts, so a progress bar can be raised.
	**/
	public var onBusy:Null<(Locale, String) -> Void> = null;

	/**
		Called when it finishes.
	**/
	public var onIdle:Null<Void -> Void> = null;

	/**
		Called to start a bounce on a worker thread. A null here is not an error and is
		worse than one: the bounce runs on the main thread instead and the window freezes
		for its whole length.
	**/
	public var onRender:Null<String -> Void> = null;

	/**
		The session being read and written.
	**/
	public var session(default, null):Session;
	var chooser:cpp.Star<Chooser> = null;

	/**
		Binds the file operations to a session.

		@param session The session.
	**/
	public function new(session:Session) {
		this.session = session;
	}

	/**
		Points this at another session, which loading a piece needs. It is this rather
		than a new instance so no callback is dropped.

		@param session The session to follow.
	**/
	public function follows(session:Session):Void {
		this.session = session;
	}

	/**
		Counts down to the next save on its own and takes one when it is due and
		anything has changed. Call once a frame.

		@param seconds How long since the last call.
		@return Whether anything happened.
	**/
	public function tick(seconds:Float):Bool {
		if (every <= 0) return false;

		since += seconds;
		if (since < every) return false;

		since = 0;
		return keep();
	}

	/**
		@return A stamp over the piece and its samples. Two calls agreeing means nothing has
			changed since, which is what decides whether a save on its own has anything to do.
	**/
	public function marked():Int {
		final said = haxe.io.Bytes.ofString(Project.text(session.song, library));
		final bulk = Project.bulk(session.song, library);

		return haxe.crypto.Crc32.make(said) ^ haxe.crypto.Crc32.make(bulk);
	}

	/**
		Saves on its own, to the piece's own file or to a recovery file where it has
		never been saved by hand.

		@return Whether it saved.
	**/
	public function keep():Bool {
		final now = marked();
		if (now == stamp) return false;

		final where = path != "" ? path : recovery();

		try {
			Project.save(session.song, where, library);
		} catch (e:Dynamic) {
			session.says(Locale.SAID_SAVE_FAILED, "" + e);
			return true;
		}

		stamp = now;
		kept++;
		recovered = path != "" ? "" : where;

		backed(where);

		session.says(path != "" ? Locale.SAID_KEPT : Locale.SAID_RECOVERED);
		return true;
	}

	/**
		@return Where a piece that was never saved by hand goes.
	**/
	public function recovery():String {
		return within("projects") + "/recovered." + mdd.Config.SUFFIX;
	}

	/**
		Finds a folder under the userdata folder, making it if it is not there.

		@param what The folder name.
		@return Its full path.
	**/
	public function within(what:String):String {
		final held = what == "projects" ? projectsAt : (what == "presets" ? presetsAt : "");

		if (held == "") return Paths.within(what);

		Paths.make(held);
		return held;
	}

	/**
		@return Where the backups are kept.
	**/
	public function backups():String {
		return Paths.within("backups");
	}

	/**
		Copies a file into the backups before it is overwritten.

		@param from The file about to be written.
	**/
	function backed(from:String):Void {
		if (backupRoom <= 0 || !FileSystem.exists(from)) return;

		final stamp = DateTools.format(Date.now(), "%Y%m%d-%H%M%S");
		final named = haxe.io.Path.withoutDirectory(from);
		final at = named.lastIndexOf(".");
		final stem = at <= 0 ? named : named.substr(0, at);

		try {
			Paths.make(backups());
			sys.io.File.copy(from, backups() + "/" + stem + "-" + stamp + "."
				+ mdd.Config.SUFFIX);
		} catch (e:Dynamic) {
			return;
		}

		pruned();
	}

	/**
		Removes the backups that are too old or that push the folder past its room.

		@return How many were removed.
	**/
	public function pruned():Int {
		final where = backups();
		if (!FileSystem.exists(where)) return 0;

		final names:Array<String> = [];
		final stamps:Array<Float> = [];
		final sizes:Array<Float> = [];

		for (name in FileSystem.readDirectory(where)) {
			if (!StringTools.endsWith(name.toLowerCase(), "." + mdd.Config.SUFFIX)) continue;

			final held = FileSystem.stat(where + "/" + name);

			names.push(name);
			stamps.push(held.mtime.getTime());
			sizes.push(held.size);
		}

		for (index in 1...names.length) {
			final name = names[index];
			final stamp = stamps[index];
			final size = sizes[index];
			var at = index - 1;

			while (at >= 0 && stamps[at] < stamp) {
				names[at + 1] = names[at];
				stamps[at + 1] = stamps[at];
				sizes[at + 1] = sizes[at];
				at--;
			}

			names[at + 1] = name;
			stamps[at + 1] = stamp;
			sizes[at + 1] = size;
		}

		final oldest = backupDays <= 0 ? 0.0
			: Date.now().getTime() - backupDays * 24.0 * 3600.0 * 1000.0;

		var held = 0.0;
		var gone = 0;

		for (index in 0...names.length) {
			held += sizes[index];

			final stale = oldest > 0 && stamps[index] < oldest;
			final full = backupRoom > 0 && held > backupRoom;

			if (!stale && !full) continue;

			try {
				FileSystem.deleteFile(where + "/" + names[index]);
				gone++;
			} catch (e:Dynamic) {}
		}

		return gone;
	}

	/**
		@return How much room the backups take, in bytes.
	**/
	function backedUp():Float {
		final where = backups();
		if (!FileSystem.exists(where)) return 0;

		var held = 0.0;

		for (name in FileSystem.readDirectory(where)) {
			if (!StringTools.endsWith(name.toLowerCase(), "." + mdd.Config.SUFFIX)) continue;
			held += FileSystem.stat(where + "/" + name).size;
		}

		return held;
	}

	/**
		Forgets where the piece was saved, which starting a new one needs.
	**/
	public function forget():Void {
		stamp = marked();
		since = 0;
	}

	/**
		Whether the piece holds work that is in no file yet, which is what has to be
		asked about before anything replaces it.

		This reads the whole piece rather than watching the undo stack, because a sample
		read in and a name typed are changes the stack never saw. It costs one pass over
		the piece and it is asked once, when the reader does something that would throw
		the work away.

		@return Whether the piece differs from what was last read or written.
	**/
	public function unsaved():Bool {
		return marked() != stamp;
	}

	/**
		Opens a dialog. It does not block: `poll` finds out what happened.

		@param window The window it belongs to.
		@param what Which dialog, one of the constants above.
	**/
	public function ask(window:cpp.Star<Window>, what:Int):Void {
		if (asking != NOTHING) return;

		final where = path != "" ? haxe.io.Path.directory(path) : Paths.within("projects");

		asking = what;

		chooser = switch (what) {
			case OPEN: Dialog.open(window, mdd.Config.FORMAT, mdd.Config.SUFFIX, where);
			case SAVE: Dialog.save(window, mdd.Config.FORMAT, mdd.Config.SUFFIX, where);
			case VGM: Dialog.save(window, "vgm", "vgm", where);
			case WAV: Dialog.save(window, "wav", "wav", where);
			case MIDI: Dialog.save(window, "midi", "mid", where);
			case XGM: Dialog.save(window, "xgm", "xgm", where);
			case AUDIO: Dialog.save(window, mixing.named(), mixing.suffix(), where);
			case READ_VGM: Dialog.open(window, "vgm", "vgm;vgz", where);
			case READ_MIDI: Dialog.open(window, "midi", "mid", where);
			case READ_WAV: Dialog.open(window, "wav", "wav", where);
			case READ_XGM: Dialog.open(window, "xgm", "xgm", where);
			case TFI: Dialog.save(window, "tfi", "tfi", where);
			case PRESET_TFI: Dialog.save(window, "tfi", "tfi", within("presets"));
			case PRESET_WAV: Dialog.save(window, "wav", "wav", within("presets"));

			case PRESET_BANK:
				Dialog.save(window, mdd.Config.BANK_FORMAT, mdd.Config.BANK, within("presets"));
			case READ_TFI: Dialog.open(window, "tfi", "tfi", where);

			case READ_PRESETS:
				Dialog.open(window, mdd.Config.PRESET_FORMAT,
					mdd.Config.PRESET + ";" + mdd.Config.BANK, within("presets"));
			case READ_KIT: Dialog.folder(window, where);
			case READ_HIT: Dialog.open(window, "wav", "wav", where);
			case _: null;
		}

		if (chooser == null) asking = NOTHING;
	}

	/**
		Finds out whether an open dialog has been answered, and acts on it. Call once a
		frame.

		Most answers raise the progress bar while they are acted on. A recording or a
		folder going into a kit does not, because `Root.sheet` holds one widget: raising
		anything there would put the sheet that asked for the file away, and with it the
		kit being built. They are read in no time anyway.

		@return Whether anything happened.
	**/
	public function poll():Bool {
		if (asking == NOTHING || chooser == null) return false;

		final state = Dialog.state(chooser);
		if (state == Dialog.WAITING) return false;

		final chose = state == Dialog.CHOSEN;
		final where = chose ? (Dialog.path(chooser) : String) : "";
		final what = asking;

		Dialog.close(chooser);
		chooser = null;
		asking = NOTHING;

		if (!chose) {
			session.says(Locale.SAID_NOTHING_CHOSEN);
			session.changed();
			return true;
		}

		if (what == AUDIO) {
			if (onRender != null) onRender(where);
			else took(what, where);

			return true;
		}

		if (instant(what)) {
			took(what, where);
			return true;
		}

		if (onBusy != null) onBusy(labelled(what), name(where));

		took(what, where);

		if (onIdle != null) onIdle();
		return true;
	}

	/**
		Whether acting on an answer is done in no time, so no progress bar is raised
		for it.

		This is not only about speed. `Root.sheet` holds one widget, so raising the
		progress bar puts away whatever sheet was there. A dialog opened by a sheet
		that has to still be there afterwards, which is what adding a recording to a
		kit is, must be on this list or the sheet it is feeding disappears along with
		everything gathered into it.

		@param what Which dialog.
		@return Whether it is acted on without a progress bar.
	**/
	public static function instant(what:Int):Bool {
		return what == READ_HIT || what == READ_KIT;
	}

	/**
		@param what A dialog.
		@return What to call it.
	**/
	public static function labelled(what:Int):Locale {
		return switch (what) {
			case OPEN: Locale.WORKING_OPENING;
			case SAVE: Locale.WORKING_SAVING;
			case READ_VGM, READ_XGM, READ_MIDI, READ_WAV: Locale.WORKING_IMPORTING;
			case _: Locale.WORKING_EXPORTING;
		}
	}

	/**
		Acts on a path a dialog answered with.

		@param what Which dialog.
		@param where The path.
	**/
	function took(what:Int, where:String):Void {
		try {
			switch (what) {
				case OPEN: load(where);
				case SAVE: save(where);
				case VGM: exportVgm(where);
				case XGM: exportXgm(where);
				case AUDIO: exportAudio(where);
				case WAV: exportWav(where);
				case MIDI: exportMidi(where);
				case READ_VGM: readVgm(where);
				case READ_XGM: readXgm(where);
				case READ_MIDI: readMidi(where);
				case READ_WAV: readWav(where);
				case TFI: writeTfi(where);
				case PRESET_TFI: writesPresetTfi(where);
				case PRESET_WAV: writesPresetWav(where);
				case PRESET_BANK: writesBank(where);
				case READ_PRESETS: readPresets(where);
				case READ_TFI: readTfi(where);
				case READ_KIT: readKit(where);
				case READ_HIT: readHit(where);
				case _:
			}
		} catch (e:Dynamic) {
			session.says(Locale.SAID_FAILED, "" + e);
		}

		session.changed();
	}

	/**
		Reads a project and hands it to `onLoad`.

		@param where The file to read.
	**/
	public function load(where:String):Void {
		final song = Project.open(where);
		final many = song.instruments.length;

		path = where;
		if (onLoad != null) onLoad(song);
		forget();

		session.says(Locale.SAID_OPENED, name(where), "" + song.patterns.length, "" + many);
	}

	/**
		Imports a register log: reads the writes, then works out what they meant.

		@param where The file to read.
	**/
	public function readVgm(where:String):Void {
		final into = new Stream(1 << 22);
		final vgm = Vgm.read(mdd.format.Gzip.opened(sys.io.File.getBytes(where)), into);
		final made = Transcription.of(into, vgm.rate, name(where));

		if (vgm.title != "") made.song.name = vgm.title;
		if (vgm.author != "") made.song.author = vgm.author;

		made.song.album = vgm.game;
		made.song.year = vgm.released;
		made.song.comment = vgm.notes;

		path = "";
		if (onLoad != null) onLoad(made.song);
		forget();

		session.says(Locale.SAID_READ_NOTES, name(where), "" + made.notes,
			"" + made.song.patterns.length, "" + Math.round(made.beats));
	}

	/**
		Imports a driver file the same way.

		@param where The file to read.
	**/
	public function readXgm(where:String):Void {
		final into = new Stream(1 << 22);
		final xgm = Xgm.read(sys.io.File.getBytes(where), into);
		final made = Transcription.of(into, xgm.rate, name(where));

		if (xgm.title != "") made.song.name = xgm.title;
		if (xgm.author != "") made.song.author = xgm.author;

		made.song.album = xgm.game;
		made.song.year = xgm.released;
		made.song.comment = xgm.notes;

		path = "";
		if (onLoad != null) onLoad(made.song);
		forget();

		session.says(xgm.unknown == 0 ? Locale.SAID_READ_DRIVER
			: Locale.SAID_READ_DRIVER_PARTLY, name(where), "" + made.notes,
			"" + made.song.patterns.length, "" + Math.round(made.beats),
			"" + xgm.samples, "" + xgm.struck);
	}

	/**
		Imports a wave file as a sample, resampled to the rate the export asks for.

		@param where The file to read.
		@return The sample.
	**/
	public function readWav(where:String):mdd.song.Sample {
		final wav = Wav.read(sys.io.File.getBytes(where));
		final made = new mdd.song.Sample(name(where), DAC_RATE);

		made.hold(wav.bytes(DAC_RATE));
		session.holds();
		session.song.samples.push(made);
		session.frees();

		session.says(Locale.SAID_READ_SAMPLE, name(where), "" + made.length(),
			"" + DAC_RATE);
		session.changed();

		return made;
	}

	/**
		Hands a folder of recordings to the kit that is open.

		Nothing is read or written here. The sheet is what holds the kit and what decides
		whether any of it is kept, so a folder can be looked at and left alone.

		@param where The folder to read.
	**/
	public function readKit(where:String):Void {
		final what = onKitFolder;
		if (what != null) what(where);
	}

	/**
		Hands one recording to the kit that is open.

		@param where The file to read.
	**/
	public function readHit(where:String):Void {
		final what = onHit;
		if (what != null) what(where);
	}

	/**
		Writes a kit into the presets folder and reads it straight back into the
		library, so it is there to play without restarting.

		@param kit The kit to write.
		@return Where it was written, or an empty string where nothing was.
	**/
	public function writeKit(kit:mdd.format.Kit):String {
		final made = kit.banked();
		if (made == null) return "";

		final into = familied(mdd.song.Part.Dac);
		Paths.make(into);

		final named = into + "/" + safely(kit.name) + mdd.song.Library.BANK;
		final bytes = mdd.format.Preset.write(made.name, made.presets, made.samples);

		sys.io.File.saveBytes(named, bytes);

		final held = new mdd.song.Library();
		held.holds(bytes, true);

		session.holds();
		held.into(session.song);
		session.frees();

		if (library != null) library.holds(bytes, true, "", true);

		session.says(Locale.SAID_KIT, kit.name, "" + kit.taken(), "" + kit.bytes());
		session.changed();

		return named;
	}

	/**
		Imports a midi file as notes and a tempo map.

		@param where The file to read.
	**/
	public function readMidi(where:String):Void {
		final bytes = sys.io.File.getBytes(where);
		final strands = Midi.survey(bytes);

		if (strands.length == 0) {
			session.says(Locale.SAID_EMPTY_MIDI);
			return;
		}

		midiBytes = bytes;
		midiName = name(where);

		final what = onSurvey;
		if (what != null) what(midiName, strands);
	}

	/**
		Takes what a reader chose out of the file `readMidi` surveyed.

		@param strands What to take, and where each strand goes.
		@param instead Whether the file becomes a piece of its own rather than a track in
			the one that is open.
	**/
	public function takesMidi(strands:Array<Strand>, instead:Bool):Void {
		final bytes = midiBytes;
		if (bytes == null) return;

		var many = 0;
		for (strand in strands) if (strand.taken) many += strand.notes;

		if (many == 0) {
			session.says(Locale.SAID_NOTHING_TAKEN);
			return;
		}

		if (instead) {
			final song = Midi.taken(bytes, midiName, strands);
			final many = song.instruments.length;

			path = "";
			if (onLoad != null) onLoad(song);
			forget();

			session.says(Locale.SAID_READ_SONG, midiName, "" + song.patterns.length, "" + many);
			return;
		}

		tracked(bytes, strands, many);
	}

	/**
		Puts the chosen strands into the piece that is open, as one more track.

		It lands as one pattern on one new row, which is what a track is here, so the
		whole import moves as one thing. It goes on the undo stack whole.

		@param bytes The file.
		@param strands What to take, and where each strand goes.
		@param many How many notes that comes to.
	**/
	function tracked(bytes:haxe.io.Bytes, strands:Array<Strand>, many:Int):Void {
		final song = session.song;
		final pattern = Midi.patterned(bytes, midiName, strands, song.tempo.ppqn);

		final onto = song.tracks.length;
		final which = song.patterns.length;

		final group = new mdd.song.edit.Together("import a midi");

		group.also(new mdd.song.edit.AddPattern(pattern));
		group.also(new mdd.song.edit.AddTrack(onto));
		group.also(new mdd.song.edit.RenameTrack(onto, midiName));
		group.also(new mdd.song.edit.AddClip(onto,
			new mdd.song.Clip(which, 0, pattern.length)));

		if (Midi.kitted(strands)) group.also(new mdd.song.edit.KitDrums(true));

		session.does(group);
		session.says(Locale.SAID_IMPORTED, midiName, "" + (onto + 1), "" + many);
	}

	/**
		Writes the project, backing up whatever was there first.

		@param where The file to write.
		@return What to say about it.
	**/
	public function save(where:String):String {
		final named = suffixed(where, mdd.Config.SUFFIX);

		Project.save(session.song, named, library);
		path = named;
		forget();

		session.says(Locale.SAID_SAVED, name(named));
		return named;
	}

	/**
		Writes the whole piece out as a register log.

		@param where The file to write.
		@return What to say about it.
	**/
	public function exportVgm(where:String):String {
		final named = suffixed(where, "vgm");
		final span = session.song.tempo.samplesAt(session.song.ends());

		final stream = Stream.reserved(span);
		final sequencer = new Sequencer(session.song);

		sequencer.declick = mixing.declick;
		sequencer.stuck = mixing.stuck;
		sequencer.spanned(stream, 0, span);
		sys.io.File.saveBytes(named, Vgm.write(stream, 0, span, session.song.tempo.rate,
			session.song.name, session.song.author, session.song.album, session.song.year,
			session.song.comment));

		final lost = sequencer.lost + stream.dropped;

		if (lost == 0) {
			session.says(Locale.SAID_WROTE_STREAM, "" + stream.count, name(named));
		} else {
			session.says(Locale.SAID_WROTE_STREAM_DROPPED, "" + stream.count,
				name(named), "" + lost);
		}
		return named;
	}

	/**
		What the next audio export is set to.
	**/
	public var mixing:Mixing = new Mixing();

	/**
		The bounce running now, where one is.
	**/
	public var mixdown:Null<Mixdown> = null;

	final writing:mdd.host.Atomic = new mdd.host.Atomic(1);

	/**
		Where the last export went.
	**/
	public var wroteAs(default, null):String = "";

	/**
		What it said about it.
	**/
	public var wroteKey(default, null):Int = -1;

	/**
		What goes in the numbered places of `wroteKey`.
	**/
	public final wroteWith:Array<String> = [];

	/**
		What went wrong, or an empty string where nothing did.
	**/
	public var wroteWrong(default, null):String = "";

	/**
		@return Whether the bounce that was running has finished.
	**/
	public inline function wroteYet():Bool {
		return writing.load() == 1;
	}

	/**
		Starts a bounce on a worker thread and answers with it, so a progress bar can
		follow it.

		@param where The file to write.
		@return The bounce.
	**/
	public function renders(where:String):Mixdown {
		final made = Mixdown.made();
		final song = session.song;
		final parts = mixing.moving() ? [] : stemsOf(song);

		mixdown = made;

		wroteAs = "";
		wroteKey = -1;
		wroteWith.resize(0);
		wroteWrong = "";

		writing.store(0);
		made.spans(1 + parts.length);
		made.steps(0);

		sys.thread.Thread.create(function():Void {
			mdd.host.Crash.thread("the export thread");

			try {
				made.runs(song, mixing);

				if (!made.stopped() && !mixing.moving()) {
					wroteAs = wrote(where, made);
					if (parts.length > 0) stemsInto(where, song, made, parts);
				}
			} catch (e:Dynamic) {
				wroteWrong = Std.string(e);
			}

			writing.store(1);
		});

		return made;
	}

	/**
		@param song The piece.
		@return What gets a stem, as indices: for stems by channel every part the arrangement
			actually sounds, for stems by track every track that is not muted and places a pattern
			with notes in it, and nothing where the export writes no stems.
	**/
	public function stemsOf(song:mdd.song.Song):Array<Int> {
		final out:Array<Int> = [];

		if (mixing.stems == Mixing.CHANNEL_STEMS) {
			for (index in 0...mdd.song.Part.COUNT) {
				if (song.carries(index)) out.push(index);
			}
		}

		if (mixing.stems == Mixing.TRACK_STEMS) {
			for (index in 0...song.tracks.length) {
				if (noted(song, song.tracks[index])) out.push(index);
			}
		}

		return out;
	}

	/**
		@param song The piece.
		@param track One of its tracks.
		@return Whether the track is heard in the mix and places a pattern that holds notes.
	**/
	static function noted(song:mdd.song.Song, track:mdd.song.Track):Bool {
		if (track.muted) return false;

		for (clip in track.clips) {
			if (clip.kind != mdd.song.Clip.PATTERN) continue;

			final pattern = song.patternAt(clip.pattern);
			if (pattern == null) continue;

			for (index in 0...mdd.song.Part.COUNT) {
				if (pattern.lanes[index].notes.length > 0) return true;
			}
		}

		return false;
	}

	/**
		@param song The piece.
		@param stems What gets a stem, as `stemsOf` gave it.
		@return The file name each stem is written under, without a suffix: the part's name for a
			stem by channel, and the track's name for a stem by track, numbered where two tracks
			share a name so neither is written over the other.
	**/
	public function stemNames(song:mdd.song.Song, stems:Array<Int>):Array<String> {
		final out:Array<String> = [];

		for (index in stems) {
			if (mixing.stems != Mixing.TRACK_STEMS) {
				final part:mdd.song.Part = index;
				out.push(part.name());
				continue;
			}

			final given = StringTools.trim(song.tracks[index].name);
			final base = safely(given == "" ? "Track " + (index + 1) : given);

			var named = base;
			var count = 2;

			while (out.indexOf(named) >= 0) named = base + " " + count++;

			out.push(named);
		}

		return out;
	}

	/**
		@param where The file the mix was written to.
		@return The folder the stems go in, which is that file name and the word stems.
	**/
	function stemFolder(where:String):String {
		return haxe.io.Path.withoutExtension(suffixed(where, mixing.suffix()))
			+ " stems";
	}

	/**
		Renders one file per part or per track beside the mix, on the thread the mix was rendered
		on.

		Every stem takes the gain the mix arrived at rather than being normalised on its
		own, so the set of them sums back to the mix.

		The stems are independent of each other, so rendering several at once would be
		the obvious way to spend the other processors. It does not work: several
		mixdowns running at once fault the collector inside its own mark phase.
		`docs/notes/audio-export.md` records what was measured.

		@param where The file the mix was written to.
		@param song The piece.
		@param made The bounce the mix was rendered with, reused for every stem.
		@param stems What to render, as `stemsOf` gave it.
	**/
	function stemsInto(where:String, song:mdd.song.Song, made:Mixdown,
			stems:Array<Int>):Void {
		final into = stemFolder(where);
		final gain = made.gain;
		final names = stemNames(song, stems);
		final tracked = mixing.stems == Mixing.TRACK_STEMS;

		mdd.host.Paths.make(into);

		var written = 0;

		for (at in 0...stems.length) {
			if (made.stopped()) break;

			made.steps(written + 1);
			made.onlyPart = tracked ? -1 : stems[at];
			made.onlyTrack = tracked ? stems[at] : -1;
			made.sharedGain = gain;

			made.runs(song, mixing);
			if (made.stopped()) break;

			wrote(into + "/" + names[at], made);

			written++;
		}

		made.onlyPart = -1;
		made.onlyTrack = -1;
		made.sharedGain = 0;

		wroteKey = wroteKey == Locale.SAID_WROTE_AUDIO_LIFTED
			? Locale.SAID_WROTE_AUDIO_LIFTED_STEMS : Locale.SAID_WROTE_AUDIO_STEMS;

		wroteWith.push("" + written);
		wroteWith.push(name(into));
	}

	/**
		Imports a patch file into the library.

		@param where The file to read.
	**/
	public function readTfi(where:String):Void {
		final held = mdd.format.Tfi.read(sys.io.File.getBytes(where));

		if (held == null) {
			session.says(Locale.SAID_NOT_TFI);
			return;
		}

		final made = new mdd.song.Instrument(bare(where), mdd.song.Part.Fm1);

		made.patch = held;
		made.icon = mdd.Icon.NAMES.indexOf("synthesizer");

		session.holds();
		session.song.instrument(made);

		final index = session.song.instruments.length - 1;
		session.song.rack[session.part.index()] = index;

		if (savedInto != "") {
			session.song.bank(0).remove(index);
			session.song.banked(savedInto).add(index);
		}

		session.frees();

		final into = familied(mdd.song.Part.Fm1);
		final named = into + "/" + safely(bare(where)) + ".tfi";

		if (!FileSystem.exists(named)) {
			Paths.make(into);
			sys.io.File.saveBytes(named, mdd.format.Tfi.write(held));
		}

		if (library != null && savedInto != "" && sameTfi(named, held)) {
			library.adds(savedInto, made.copy(), null, true);
		}

		session.say(bare(where));
	}

	/**
		Reads a preset file or a bank file into the piece that is open, and keeps a copy of it in
		the presets folder so every other piece offers it too. The piece is not replaced: a bank
		is presets, and opening one adds them.

		A file that names its own bank is that bank. One that names none is the file itself, so a
		single preset saved out and read back in sits under its own name rather than joining
		whatever was last saved.

		@param where The file to read.
	**/
	public function readPresets(where:String):Void {
		final held = mdd.format.Preset.read(sys.io.File.getBytes(where));

		if (held == null || held.presets.length == 0) {
			session.says(Locale.SAID_NOT_PRESETS);
			return;
		}

		final song = session.song;
		final named = held.name == "" ? bare(where) : held.name;
		final bank = song.banked(named);

		session.holds();

		var many = 0;

		for (index in 0...held.presets.length) {
			final made = held.presets[index].copy();
			final sample = held.samples[index];

			if (sample != null) {
				song.sample(sample.copy());
				made.sample = song.samples.length - 1;
			}

			song.instrument(made);

			final at = song.instruments.length - 1;

			song.bank(0).remove(at);
			bank.add(at);

			many++;
		}

		bank.kept = true;
		session.frees();

		keepsPresets(where, held, named);

		session.says(Locale.SAID_PRESETS_READ, "" + many, named);
	}

	/**
		Copies a preset file just read into the presets folder, under the family its presets share
		where they share one, and puts what it holds in the library. A file already there is left
		as it is.

		@param where The file that was read.
		@param held What it carried.
		@param named The bank it was read under.
	**/
	function keepsPresets(where:String, held:mdd.format.Banked, named:String):Void {
		final into = within("presets");
		if (into == "") return;

		var family = "";

		for (preset in held.presets) {
			final one = preset.kind.family();

			if (family == "") family = one;
			else if (family != one) family = "-";
		}

		final folder = family == "" || family == "-" ? into : into + "/" + family;
		final at = folder + "/" + safely(bare(where)) + suffixOf(where);

		if (!FileSystem.exists(at)) {
			Paths.make(folder);

			try {
				sys.io.File.copy(where, at);
			} catch (e:Dynamic) {
				return;
			}
		}

		if (library == null) return;

		for (index in 0...held.presets.length) {
			library.adds(named, held.presets[index].copy(), held.samples[index], true);
		}
	}

	/**
		@param where A path.
		@return Its suffix with the dot, in lower case, or an empty string where it has none.
	**/
	static function suffixOf(where:String):String {
		final held = haxe.io.Path.extension(where);
		return held == "" ? "" : "." + held.toLowerCase();
	}

	/**
		@param kind What family of part a preset is for.
		@return The folder in the presets folder that family is kept in, which is the presets
			folder itself where there is none set.
	**/
	public function familied(kind:mdd.song.Part):String {
		final where = within("presets");
		return where == "" ? "" : where + "/" + kind.family();
	}

	/**
		Moves what is already in the presets folder into a folder for each family of part, which
		is how the folder is laid out from now on: `FM`, `PSG`, `NOISE` and `DAC`, each holding
		whatever folders of its own a reader has made under it. A file already inside one of the
		four is left where it is, and so is a bank document, which names its own bank and may
		carry more than one family. A file whose place is taken is left where it is as well.

		@return How many files moved.
	**/
	public function sortsPresets():Int {
		final where = within("presets");
		if (where == "" || !FileSystem.exists(where) || !FileSystem.isDirectory(where)) return 0;

		var many = 0;

		for (name in FileSystem.readDirectory(where)) {
			if (StringTools.startsWith(name, ".")) continue;
			if (FileSystem.isDirectory(where + "/" + name) && mdd.song.Library.familied(name)) continue;

			many += sorted(where, name, "");
		}

		for (family in mdd.song.Library.FAMILIES) Paths.make(where + "/" + family);

		return many;
	}

	/**
		Moves one file, or everything under one folder, into the family folder each belongs in.

		@param where The presets folder.
		@param name What sits in it, a file or a folder.
		@param under The folders it sits in below the presets folder, or an empty string.
		@return How many files moved.
	**/
	function sorted(where:String, name:String, under:String):Int {
		final from = where + (under == "" ? "" : "/" + under) + "/" + name;

		if (FileSystem.isDirectory(from)) {
			var many = 0;
			final inside = under == "" ? name : under + "/" + name;

			for (held in FileSystem.readDirectory(from)) {
				if (StringTools.startsWith(held, ".")) continue;
				many += sorted(where, held, inside);
			}

			return many;
		}

		final family = familyOf(from, name);
		if (family == "") return 0;

		final into = where + "/" + family + (under == "" ? "" : "/" + under);
		final named = into + "/" + name;

		if (FileSystem.exists(named)) return 0;

		try {
			Paths.make(into);
			FileSystem.rename(from, named);
		} catch (e:Dynamic) {
			return 0;
		}

		return 1;
	}

	/**
		@param from A file in the presets folder, of any kind read out of one.
		@param name What it is called.
		@return Which family of part it holds presets for, or an empty string where it will not
			read, holds no preset, or carries more than one family. A file naming a bank of its
			own answers the same way, because it is that bank wherever it sits.
	**/
	function familyOf(from:String, name:String):String {
		final lower = name.toLowerCase();

		if (StringTools.endsWith(lower, mdd.song.Library.PATCH)) {
			return mdd.song.Part.Fm1.family();
		}

		try {
			if (StringTools.endsWith(lower, mdd.song.Library.RECORDS)
					|| StringTools.endsWith(lower, mdd.song.Library.BANK)) {
				return mdd.song.Library.familyOf(sys.io.File.getBytes(from));
			}

			if (StringTools.endsWith(lower, mdd.song.Library.SUFFIX)) {
				return mdd.song.Library.familyIn(sys.io.File.getContent(from));
			}
		} catch (e:Dynamic) {}

		return "";
	}

	/**
		Writes a preset into the presets folder as a file of its own and puts it in the
		library, so every piece opened from now on offers it. A file of that name holding
		anything but a saved preset of the same name and kind is left alone, and the
		preset is written beside it under a number.

		@param made The preset.
		@param sample The sample it plays, or null.
		@return Where it was written, or an empty string where it could not be.
	**/
	public function keepsPreset(made:mdd.song.Instrument, sample:Null<mdd.song.Sample>):String {
		made.identifies(sample);

		final into = familied(made.kind);
		final written = mdd.format.Preset.write("", [made], [sample]);
		final base = into + "/" + safely(made.name);

		var named = base + mdd.song.Library.RECORDS;
		var at = 2;

		while (FileSystem.exists(named) && !overwrites(named, made)) {
			named = base + " " + at + mdd.song.Library.RECORDS;
			at++;
		}

		try {
			Paths.make(into);
			sys.io.File.saveBytes(named, written);
		} catch (e:Dynamic) {
			return "";
		}

		if (library != null && savedInto != "") {
			library.keeps(savedInto, made.copy(), sample == null ? null : sample.copy());
		}

		return named;
	}

	/**
		@param where A file in the presets folder.
		@param made A preset about to be saved.
		@return Whether the file holds a saved preset with that name for the same kind of
			part and nothing else, which saving it again may write over.
	**/
	function overwrites(where:String, made:mdd.song.Instrument):Bool {
		try {
			final held = mdd.format.Preset.read(sys.io.File.getBytes(where));
			if (held == null || held.name != "" || held.presets.length != 1) return false;

			return held.presets[0].name == made.name
				&& mdd.song.Library.kin(held.presets[0].kind, made.kind);
		} catch (e:Dynamic) {
			return false;
		}
	}

	/**
		Lists every file under the presets folder with its size and when it last changed,
		as deep as the library reads, so two calls answer whether anything in it moved.

		@return The listing, which means nothing except compared with another.
	**/
	/**
		@param name What the cache holds.
		@return The file it is kept in, which is beside the settings rather than in the folder it
			caches: what a reader put in the presets folder is theirs, and nothing this writes
			belongs there.
	**/
	public function cache(name:String):String {
		return Paths.within("cache") + "/" + name + ".cache";
	}

	public function presetsStamp():String {
		final out = new StringBuf();
		stamped(within("presets"), 0, out);

		return out.toString();
	}

	/**
		@param where A folder.
		@param depth How far down from the presets folder it is.
		@param out Where the listing goes.
	**/
	static function stamped(where:String, depth:Int, out:StringBuf):Void {
		try {
			final held = FileSystem.readDirectory(where);
			held.sort(function(one:String, two:String):Int return one < two ? -1 : 1);

			for (name in held) {
				final path = where + "/" + name;

				if (FileSystem.isDirectory(path)) {
					out.add(path);
					out.add("\n");

					if (depth < mdd.song.Library.DEPTH) stamped(path, depth + 1, out);
					continue;
				}

				final stat = FileSystem.stat(path);

				out.add(path);
				out.add(" ");
				out.add(stat.size);
				out.add(" ");
				out.add(stat.mtime.getTime());
				out.add("\n");
			}
		} catch (e:Dynamic) {}
	}

	/**
		Writes the chosen patch out as a patch file.

		@param where The file to write.
		@return What to say about it.
	**/
	function writeTfi(where:String):String {
		final at = session.song.rack[session.part.index()];
		final held = session.song.instrumentAt(at);

		if (held == null || held.patch == null) {
			session.says(Locale.SAID_NO_PATCH);
			return "";
		}

		final named = suffixed(where, "tfi");
		sys.io.File.saveBytes(named, mdd.format.Tfi.write(held.patch));

		session.say(name(named));
		return named;
	}

	/**
		Writes one preset out as a patch file, which is what a reader hands to anything else that
		plays this chip.

		@param where The file to write.
		@return What was written, or an empty string where the preset carries no patch.
	**/
	public function writesPresetTfi(where:String):String {
		final held = session.song.instrumentAt(chosen);
		final patch = held == null ? null : held.patch;

		if (patch == null) {
			session.says(Locale.SAID_NO_PATCH);
			return "";
		}

		final named = suffixed(where, "tfi");
		sys.io.File.saveBytes(named, mdd.format.Tfi.write(patch));

		session.say(name(named));
		return named;
	}

	/**
		Writes what a converter preset plays out as a wave file, at the rate it was recorded at,
		so a hit can be taken into anything that edits sound.

		@param where The file to write.
		@return What was written, or an empty string where the preset plays nothing.
	**/
	public function writesPresetWav(where:String):String {
		final held = session.song.instrumentAt(chosen);
		final sample = held == null || held.sample < 0 ? null : session.song.sampleAt(held.sample);

		if (sample == null || sample.length() == 0) {
			session.says(Locale.SAID_NO_SAMPLE);
			return "";
		}

		final frames = sample.length();
		final taken = new Vector<cpp.Float32>(frames);

		for (at in 0...frames) taken[at] = (sample.bytes[at] - 128) / 127.0;

		final named = suffixed(where, "wav");
		sys.io.File.saveBytes(named, mdd.format.Wav.write(taken, frames, 1, sample.rate));

		session.says(Locale.SAID_SAMPLE_WRITTEN, name(named), "" + frames, "" + sample.rate);
		return named;
	}

	/**
		Writes a whole bank out as one file, every preset in it and every recording they play, so
		a folder of presets travels as one thing.

		@param where The file to write.
		@return What was written, or an empty string where the bank holds nothing.
	**/
	public function writesBank(where:String):String {
		final song = session.song;

		if (chosen < 0 || chosen >= song.banks.length) return "";

		final bank = song.banks[chosen];
		final presets:Array<mdd.song.Instrument> = [];
		final samples:Array<Null<mdd.song.Sample>> = [];

		for (index in bank.instruments) {
			final held = song.instrumentAt(index);
			if (held == null) continue;

			presets.push(held);
			samples.push(held.sample < 0 ? null : song.sampleAt(held.sample));
		}

		if (presets.length == 0) {
			session.says(Locale.SAID_NO_PRESETS);
			return "";
		}

		final named = suffixed(where, mdd.Config.BANK);
		sys.io.File.saveBytes(named, mdd.format.Preset.write(bank.name, presets, samples));

		session.says(Locale.SAID_BANK_WRITTEN, name(named), "" + presets.length);
		return named;
	}

	/**
		Writes every patch the piece carries into the presets folder, skipping any already there,
		and puts each one in the library.

		Each one is written the way a preset saved from the browser is, so the name, the icon, the
		tags and the two LFO depths come with it: a patch file carries none of those, and a lift
		that wrote one would be handing back less than it took.

		@return How many were written.
	**/
	public function liftsPatches():Int {
		final where = familied(mdd.song.Part.Fm1);
		final song = session.song;

		var many = 0;

		for (index in 0...song.instruments.length) {
			final held = song.instruments[index];
			final patch = held.patch;

			if (patch == null || held.sample >= 0) continue;
			if (lifts(where, held, patch)) many++;
		}

		return many;
	}

	/**
		Writes one patch out into a file nothing else in the folder is called, and puts it in the
		library. The preset keeps its own name whatever the file is called, because a record
		carries the name and a file name is only where it sits, so lifting the same piece twice
		finds what it wrote the first time and writes nothing.

		@param where The folder to write into.
		@param held The instrument it came from.
		@param patch Its patch.
		@return Whether anything was written.
	**/
	function lifts(where:String, held:mdd.song.Instrument, patch:mdd.song.Patch):Bool {
		final made = new mdd.song.Instrument(held.name, mdd.song.Part.Fm1);

		made.patch = patch.copy();
		made.icon = held.icon;

		for (tag in held.tags) made.tags.push(tag);

		made.identifies(null);

		final base = where + "/" + safely(made.name);

		var named = base + mdd.song.Library.RECORDS;
		var at = 2;

		while (FileSystem.exists(named)) {
			if (samePreset(named, made)) return false;

			named = base + " " + at + mdd.song.Library.RECORDS;
			at++;
		}

		try {
			Paths.make(where);
			sys.io.File.saveBytes(named, mdd.format.Preset.write("", [made], [null]));
		} catch (e:Dynamic) {
			return false;
		}

		if (library != null && savedInto != "") library.adds(savedInto, made, null, true);

		return true;
	}

	/**
		@param where A preset file.
		@param made A preset.
		@return Whether the file already holds exactly that preset, whatever it calls the file.
	**/
	static function samePreset(where:String, made:mdd.song.Instrument):Bool {
		try {
			final held = mdd.format.Preset.read(sys.io.File.getBytes(where));
			if (held == null) return false;

			for (one in held.presets) if (one.identifies(null) == made.id) return true;
		} catch (e:Dynamic) {}

		return false;
	}

	/**
		@param where A patch file.
		@param patch A patch.
		@return Whether the file already holds that patch.
	**/
	function sameTfi(where:String, patch:mdd.song.Patch):Bool {
		try {
			final held = mdd.format.Tfi.read(sys.io.File.getBytes(where));
			return held != null && mdd.format.Tfi.same(held, patch);
		} catch (e:Dynamic) {
			return false;
		}
	}

	/**
		@param said A name.
		@return It with anything a file name cannot carry taken out.
	**/
	static function safely(said:String):String {
		var out = "";

		for (index in 0...said.length) {
			final code = said.charCodeAt(index);
			final one = said.charAt(index);

			if (code == null) continue;

			out += (one == "/" || one == "\\" || one == ":" || one == "*" || one == "?"
				|| one == "\"" || one == "<" || one == ">" || one == "|") ? "-" : one;
		}

		final held = StringTools.trim(out);
		return held == "" ? "patch" : held;
	}

	/**
		Writes the finished bounce out in whichever format the export is set to.

		@param where The file to write.
		@return What to say about it.
	**/
	public function exportAudio(where:String):String {
		final song = session.song;
		final made = Mixdown.of(song, mixing);
		final named = wrote(where, made);

		final stems = stemsOf(song);
		if (stems.length > 0) stemsInto(where, song, made, stems);

		session.saying(wroteKey, wroteWith);
		return named;
	}

	/**
		Encodes a finished bounce and writes it.

		@param where The file to write.
		@param made The bounce.
		@return What to say about it.
	**/
	public function wrote(where:String, made:Mixdown):String {
		final named = suffixed(where, mixing.suffix());

		if (made.frames <= 0) {
			wroteKey = Locale.SAID_NOTHING_TO_RENDER;
			wroteWith.resize(0);
			return "";
		}

		final bytes = encoded(named, made);

		wroteKey = mixing.normalise ? Locale.SAID_WROTE_AUDIO_LIFTED
			: Locale.SAID_WROTE_AUDIO;

		wroteWith.resize(0);
		wroteWith.push("" + (Math.round(made.seconds() * 10) / 10));
		wroteWith.push(name(named));
		wroteWith.push("" + Math.round(bytes / 1024));

		if (mixing.normalise) {
			wroteWith.push("" + (Math.round(2000 * Math.log(made.gain)
				/ Math.log(10)) / 100));
		}

		return named;
	}

	/**
		Encodes a finished bounce and writes it, reading the export settings and
		touching nothing a reader on another thread holds.

		`wrote` is this with the line the status bar reads written afterwards, which is
		what makes that one unsafe to call from two threads at once. The split is here
		because writing the file and saying what was written are separate concerns,
		and because anything spreading the bounce would need the half that is not
		shared state.

		@param named The file to write, with its suffix already on it.
		@param made The bounce.
		@return How many bytes were written.
	**/
	function encoded(named:String, made:Mixdown):Int {
		final bytes = switch (mixing.kind) {
			case Mixing.FLAC:
				Flac.write(made.samples, made.frames, made.channels, made.rate,
					mixing.depth, tagged());

			case Mixing.OGG:
				Coded.vorbis(made.samples, made.frames, made.channels, made.rate,
					Coded.QUALITIES[mixing.quality], tagged());

			case Mixing.OPUS:
				Coded.opus(made.samples, made.frames, made.channels, made.rate,
					Coded.BITRATES[mixing.quality], mixing.opusMode, mixing.opusSpan,
					mixing.opusBitrateMode, tagged());

			case _:
				Wav.write(made.samples, made.frames, made.channels, made.rate, mixing.depth,
					mixing.dither && mixing.depth < 32);
		}

		sys.io.File.saveBytes(named, bytes);
		return bytes.length;
	}

	/**
		@return The metadata to write into the file, one entry a name and a value. A tag the export
			sheet leaves empty is taken from the piece's own description, so an export started from
			the command line is tagged the same as one started from the sheet.
	**/
	public function tagged():Array<String> {
		final held:Array<String> = [];
		final song = session.song;

		final title = mixing.title != "" ? mixing.title : song.name;
		final artist = mixing.artist != "" ? mixing.artist : song.author;
		final album = mixing.album != "" ? mixing.album : song.album;
		final year = mixing.year != "" ? mixing.year : song.year;
		final track = mixing.track != "" ? mixing.track : song.trackNumber;
		final comment = mixing.comment != "" ? mixing.comment : song.comment;

		if (title != "") held.push("TITLE=" + title);
		if (artist != "") held.push("ARTIST=" + artist);
		if (song.composer != "") held.push("COMPOSER=" + song.composer);
		if (album != "") held.push("ALBUM=" + album);
		if (year != "") held.push("DATE=" + year);
		if (song.genre != "") held.push("GENRE=" + song.genre);
		if (track != "") held.push("TRACKNUMBER=" + track);
		if (comment != "") held.push("COMMENT=" + comment);

		final beats = session.song.tempo.beatsAt(0);
		if (beats > 0) held.push("BPM=" + Math.round(beats * 100) / 100);

		return held;
	}

	/**
		Writes the piece out as a driver file.

		@param where The file to write.
		@return What to say about it.
	**/
	function exportXgm(where:String):String {
		final named = suffixed(where, "xgm");
		final span = session.song.tempo.samplesAt(session.song.ends());

		final stream = Stream.reserved(span);
		final sequencer = new Sequencer(session.song);
		final strikes:Array<Int> = [];

		sequencer.declick = mixing.declick;
		sequencer.stuck = mixing.stuck;
		sequencer.strikes = strikes;
		sequencer.spanned(stream, 0, span);

		final made = Xgm.write(session.song, stream, strikes, 0, span, session.song.tempo.rate);
		final body = made.written;

		sys.io.File.saveBytes(named, body);

		final lost = sequencer.lost + stream.dropped + made.crowded + made.refused;

		if (lost == 0) {
			session.says(Locale.SAID_WROTE_DRIVER, "" + body.length, name(named),
				"" + made.samples, "" + made.struck, "" + made.frames);
		} else {
			session.says(Locale.SAID_WROTE_DRIVER_DROPPED, "" + body.length,
				name(named), "" + made.samples, "" + made.struck, "" + made.frames,
				"" + lost);
		}
		return named;
	}

	/**
		Writes the piece out as a midi file.

		@param where The file to write.
		@return What to say about it.
	**/
	public function exportMidi(where:String):String {
		final named = suffixed(where, "mid");

		sys.io.File.saveBytes(named, Midi.write(session.song));
		session.says(Locale.SAID_EXPORTED, name(named));
		return named;
	}

	/**
		Renders the piece and writes it as a wave file, on this thread.

		@param where The file to write.
		@return What to say about it.
	**/
	public function exportWav(where:String):String {
		final named = suffixed(where, "wav");
		final span = session.song.tempo.samplesAt(session.song.ends());

		final frames = Std.int(span * (RATE / Tempo.TICKS));
		if (frames <= 0) {
			session.says(Locale.SAID_NOTHING_TO_RENDER);
			return "";
		}

		final stream = Stream.reserved(span);
		final sequencer = new Sequencer(session.song);

		sequencer.declick = mixing.declick;
		sequencer.stuck = mixing.stuck;
		sequencer.spanned(stream, 0, span);

		final held = new Vector<cpp.Float32>(frames * 2);
		final render = new Render(RATE, Render.BLOCK);

		var done = 0;

		while (done < frames) {
			final from = Std.int(done * (Tempo.TICKS / RATE));
			final many = render.serve(stream, from, Render.BLOCK, 0);

			for (i in 0...many) {
				if ((done + i) * 2 + 1 >= held.length) break;
				held[(done + i) * 2] = render.block[i * 2];
				held[(done + i) * 2 + 1] = render.block[i * 2 + 1];
			}

			done += many;
		}

		sys.io.File.saveBytes(named, Wav.write(held, frames, 2, RATE));

		session.says(Locale.SAID_RENDERED,
			"" + (Math.round(frames * 10.0 / RATE) / 10), name(named));
		return named;
	}

	/**
		@param where A path.
		@param suffix A file suffix, with no dot.
		@return The path with that suffix, whatever it had before.
	**/
	public static function suffixed(where:String, suffix:String):String {
		final held = haxe.io.Path.extension(where).toLowerCase();
		return held == suffix ? where : where + "." + suffix;
	}

	/**
		@param where A path.
		@return Just the file name.
	**/
	public static function name(where:String):String {
		return haxe.io.Path.withoutDirectory(where);
	}

	/**
		@param where A path.
		@return The file name without its suffix.
	**/
	public static function bare(where:String):String {
		return haxe.io.Path.withoutExtension(name(where));
	}
}
