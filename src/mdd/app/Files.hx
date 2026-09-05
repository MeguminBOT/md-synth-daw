package mdd.app;

import haxe.ds.Vector;
import mdd.format.Midi;
import mdd.format.Project;
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
final class Files {
	public static inline final NOTHING = 0;
	public static inline final OPEN = 1;
	public static inline final SAVE = 2;
	public static inline final VGM = 3;
	public static inline final WAV = 4;
	public static inline final MIDI = 5;
	public static inline final READ_VGM = 6;
	public static inline final READ_MIDI = 7;
	public static inline final READ_WAV = 8;
	public static inline final XGM = 9;
	public static inline final READ_XGM = 10;
	public static inline final AUDIO = 11;
	public static inline final TFI = 12;
	public static inline final READ_TFI = 13;

	public static inline final RATE = 44100;
	public static inline final DAC_RATE = 8000;

	public var path(default, null):String = "";
	public var asking(default, null):Int = NOTHING;

	public var every:Float = 0;
	public var since(default, null):Float = 0;
	public var kept(default, null):Int = 0;
	public var recovered(default, null):String = "";

	public var backupRoom:Float = 250 * 1024 * 1024;
	public var backupDays:Int = 30;

	public var projectsAt:String = "";
	public var presetsAt:String = "";

	var edits:Int = -1;

	public var onLoad:Null<Song -> Void> = null;
	public var savedInto:String = "";
	public var onBusy:Null<(String, String) -> Void> = null;
	public var onIdle:Null<Void -> Void> = null;
	public var onRender:Null<String -> Void> = null;

	public final session:Session;
	var chooser:cpp.Star<Chooser> = null;

	public function new(session:Session) {
		this.session = session;
	}

	public function tick(seconds:Float):Bool {
		if (every <= 0) return false;

		since += seconds;
		if (since < every) return false;

		since = 0;
		return keep();
	}

	public function keep():Bool {
		final depth = session.history.depth();
		if (depth == edits) return false;

		final where = path != "" ? path : recovery();

		try {
			Project.save(session.song, where);
		} catch (e:Dynamic) {
			session.say("that would not save on its own: " + e);
			return true;
		}

		edits = depth;
		kept++;
		recovered = path != "" ? "" : where;

		backed(where);

		session.say(path != "" ? "saved on its own" : "kept a recovery beside the settings");
		return true;
	}

	public function recovery():String {
		return within("projects") + "/recovered." + mdd.Config.SUFFIX;
	}

	public function within(what:String):String {
		final held = what == "projects" ? projectsAt : (what == "presets" ? presetsAt : "");

		if (held == "") return Paths.within(what);

		Paths.make(held);
		return held;
	}

	public function backups():String {
		return Paths.within("backups");
	}

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

	public function backedUp():Float {
		final where = backups();
		if (!FileSystem.exists(where)) return 0;

		var held = 0.0;

		for (name in FileSystem.readDirectory(where)) {
			if (!StringTools.endsWith(name.toLowerCase(), "." + mdd.Config.SUFFIX)) continue;
			held += FileSystem.stat(where + "/" + name).size;
		}

		return held;
	}

	public function forget():Void {
		edits = session.history.depth();
		since = 0;
	}

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
			case READ_VGM: Dialog.open(window, "vgm", "vgm", where);
			case READ_MIDI: Dialog.open(window, "midi", "mid", where);
			case READ_WAV: Dialog.open(window, "wav", "wav", where);
			case READ_XGM: Dialog.open(window, "xgm", "xgm", where);
			case TFI: Dialog.save(window, "tfi", "tfi", where);
			case READ_TFI: Dialog.open(window, "tfi", "tfi", where);
			case _: null;
		}

		if (chooser == null) asking = NOTHING;
	}

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
			session.say("nothing chosen");
			session.changed();
			return true;
		}

		if (what == AUDIO) {
			if (onRender != null) onRender(where);
			else took(what, where);

			return true;
		}

		if (onBusy != null) onBusy(labelled(what), name(where));

		took(what, where);

		if (onIdle != null) onIdle();
		return true;
	}

	public static function labelled(what:Int):String {
		return switch (what) {
			case OPEN: Locale.WORKING_OPENING;
			case SAVE: Locale.WORKING_SAVING;
			case READ_VGM, READ_XGM, READ_MIDI, READ_WAV: Locale.WORKING_IMPORTING;
			case _: Locale.WORKING_EXPORTING;
		}
	}

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
				case READ_TFI: readTfi(where);
				case _:
			}
		} catch (e:Dynamic) {
			session.say("that would not work: " + e);
		}

		session.changed();
	}

	public function load(where:String):Void {
		final song = Project.open(where);


		path = where;
		if (onLoad != null) onLoad(song);
		forget();

		session.say("opened " + name(where) + ", " + song.patterns.length + " patterns and "
			+ song.instruments.length + " instruments");
	}

	public function readVgm(where:String):Void {
		final into = new Stream(1 << 22);
		final vgm = Vgm.read(sys.io.File.getBytes(where), into);
		final made = Transcription.of(into, vgm.rate, name(where));

		if (vgm.title != "") made.song.name = vgm.title;
		if (vgm.author != "") made.song.author = vgm.author;

		path = "";
		if (onLoad != null) onLoad(made.song);
		forget();

		session.say("read " + name(where) + ", " + made.notes + " notes on "
			+ made.song.patterns.length + " patterns at " + Math.round(made.beats) + " bpm");
	}

	public function readXgm(where:String):Void {
		final into = new Stream(1 << 22);
		final xgm = Xgm.read(sys.io.File.getBytes(where), into);
		final made = Transcription.of(into, xgm.rate, name(where));

		if (xgm.title != "") made.song.name = xgm.title;
		if (xgm.author != "") made.song.author = xgm.author;

		path = "";
		if (onLoad != null) onLoad(made.song);
		forget();

		session.say("read " + name(where) + ", " + made.notes + " notes on "
			+ made.song.patterns.length + " patterns at " + Math.round(made.beats)
			+ " bpm, " + xgm.samples + " samples and " + xgm.struck + " converter hits"
			+ (xgm.unknown == 0 ? "" : ", stopped at a command it does not know, "
			+ StringTools.hex(xgm.stopped, 2)));
	}

	public function readWav(where:String):mdd.song.Sample {
		final wav = Wav.read(sys.io.File.getBytes(where));
		final made = new mdd.song.Sample(name(where), DAC_RATE);

		made.hold(wav.bytes(DAC_RATE));
		session.holds();
		session.song.samples.push(made);
		session.frees();

		session.say("read " + name(where) + ", " + made.length() + " bytes at "
			+ DAC_RATE + " Hz");
		session.changed();

		return made;
	}

	public function readMidi(where:String):Void {
		final song = Midi.read(sys.io.File.getBytes(where), name(where));


		path = "";
		if (onLoad != null) onLoad(song);
		forget();

		session.say("read " + name(where) + ", " + song.patterns.length + " patterns and "
			+ song.instruments.length + " instruments");
	}

	public function save(where:String):String {
		final named = suffixed(where, mdd.Config.SUFFIX);

		Project.save(session.song, named);
		path = named;
		forget();

		session.say("saved " + name(named));
		return named;
	}

	public static inline final PER_SECOND = 32768;
	public static inline final LEAST_ROOM = 1 << 20;
	public static inline final MOST_ROOM = 1 << 25;

	public static function roomFor(span:Int):Int {
		final seconds = span / Tempo.TICKS;
		final want = Std.int(seconds * PER_SECOND);

		return want < LEAST_ROOM ? LEAST_ROOM : (want > MOST_ROOM ? MOST_ROOM : want);
	}

	public function exportVgm(where:String):String {
		final named = suffixed(where, "vgm");
		final span = session.song.tempo.samplesAt(session.song.ends());

		final stream = new Stream(roomFor(span));
		final sequencer = new Sequencer(session.song);

		sequencer.spanned(stream, 0, span);
		sys.io.File.saveBytes(named, Vgm.write(stream, 0, span, session.song.tempo.rate,
			session.song.name, session.song.author));

		session.say("exported " + stream.count + " register writes to " + name(named)
			+ (sequencer.lost + stream.dropped == 0 ? ""
			: ", " + (sequencer.lost + stream.dropped) + " dropped"));
		return named;
	}

	public var mixing:Mixing = new Mixing();

	public var mixdown:Null<Mixdown> = null;

	public function renders():Mixdown {
		final made = Mixdown.made();

		mixdown = made;
		sys.thread.Thread.create(function():Void {
			try {
				made.runs(session.song, mixing);
			} catch (e:Dynamic) {
				made.stops();
			}
		});

		return made;
	}

	public function readTfi(where:String):Void {
		final held = mdd.format.Tfi.read(sys.io.File.getBytes(where));

		if (held == null) {
			session.say("that is not a tfi");
			return;
		}

		final made = new mdd.song.Instrument(name(where), mdd.song.Part.Fm1);

		made.patch = held;
		made.icon = mdd.Icon.NAMES.indexOf("synthesizer");

		session.song.instrument(made);

		final index = session.song.instruments.length - 1;
		session.song.rack[session.part.index()] = index;

		if (savedInto != "") {
			session.song.bank(0).remove(index);
			session.song.banked(savedInto).add(index);
		}

		final into = within("presets");
		final named = into + "/" + safely(name(where)) + ".tfi";

		if (!FileSystem.exists(named)) {
			Paths.make(into);
			sys.io.File.saveBytes(named, mdd.format.Tfi.write(held));
		}

		session.say(name(where));
	}

	public function writeTfi(where:String):String {
		final at = session.song.rack[session.part.index()];
		final held = session.song.instrumentAt(at);

		if (held == null || held.patch == null) {
			session.say("this channel has no patch");
			return "";
		}

		final named = suffixed(where, "tfi");
		sys.io.File.saveBytes(named, mdd.format.Tfi.write(held.patch));

		session.say(name(named));
		return named;
	}

	public function liftsPatches():Int {
		final where = within("presets");
		final song = session.song;

		var many = 0;

		for (index in 0...song.instruments.length) {
			final held = song.instruments[index];

			final patch = held.patch;
			if (patch == null || held.sample >= 0) continue;

			final named = where + "/" + safely(held.name) + ".tfi";
			if (FileSystem.exists(named) && sameTfi(named, patch)) continue;

			if (FileSystem.exists(named)) {
				var at = 2;
				var tried = where + "/" + safely(held.name) + " " + at + ".tfi";

				while (FileSystem.exists(tried) && !sameTfi(tried, patch)) {
					at++;
					tried = where + "/" + safely(held.name) + " " + at + ".tfi";
				}

				if (FileSystem.exists(tried)) continue;
				sys.io.File.saveBytes(tried, mdd.format.Tfi.write(patch));
			} else sys.io.File.saveBytes(named, mdd.format.Tfi.write(patch));

			many++;
		}

		return many;
	}

	function sameTfi(where:String, patch:mdd.song.Patch):Bool {
		try {
			final held = mdd.format.Tfi.read(sys.io.File.getBytes(where));
			return held != null && mdd.format.Tfi.same(held, patch);
		} catch (e:Dynamic) {
			return false;
		}
	}

	public static function safely(said:String):String {
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

	public function exportAudio(where:String):String {
		return wrote(where, Mixdown.of(session.song, mixing));
	}

	public function wrote(where:String, made:Mixdown):String {
		final named = suffixed(where, mixing.suffix());

		if (made.frames <= 0) {
			session.say("there is nothing to render");
			return "";
		}

		final bytes = switch (mixing.kind) {
			case Mixing.FLAC:
				Flac.write(made.samples, made.frames, made.channels, made.rate,
					mixing.depth, tagged());

			case Mixing.OGG:
				Coded.vorbis(made.samples, made.frames, made.channels, made.rate,
					Coded.QUALITIES[mixing.quality], tagged());

			case Mixing.OPUS:
				Coded.opus(made.samples, made.frames, made.channels, made.rate,
					Coded.BITRATES[mixing.quality], tagged());

			case _:
				Wav.write(made.samples, made.frames, made.channels, made.rate, mixing.depth,
					mixing.dither && mixing.depth < 32);
		}

		sys.io.File.saveBytes(named, bytes);

		session.say("rendered " + Math.round(made.seconds() * 10) / 10 + " s to "
			+ name(named) + ", " + Math.round(bytes.length / 1024) + " kb"
			+ (mixing.normalise ? ", up " + Math.round(2000 * Math.log(made.gain)
				/ Math.log(10)) / 100 + " dB" : ""));

		return named;
	}

	function tagged():Array<String> {
		final held:Array<String> = [];

		if (mixing.title != "") held.push("TITLE=" + mixing.title);
		if (mixing.artist != "") held.push("ARTIST=" + mixing.artist);
		if (mixing.album != "") held.push("ALBUM=" + mixing.album);
		if (mixing.year != "") held.push("DATE=" + mixing.year);
		if (mixing.track != "") held.push("TRACKNUMBER=" + mixing.track);
		if (mixing.comment != "") held.push("COMMENT=" + mixing.comment);

		return held;
	}

	public function exportXgm(where:String):String {
		final named = suffixed(where, "xgm");
		final span = session.song.tempo.samplesAt(session.song.ends());

		final stream = new Stream(roomFor(span));
		final sequencer = new Sequencer(session.song);

		sequencer.spanned(stream, 0, span);

		final made = Xgm.write(session.song, stream, 0, span, session.song.tempo.rate);
		final body = made.written;

		sys.io.File.saveBytes(named, body);

		final lost = sequencer.lost + stream.dropped + made.crowded + made.refused;

		session.say("exported " + body.length + " bytes to " + name(named) + ", "
			+ made.samples + " samples and " + made.struck + " converter hits across "
			+ made.frames + " frames" + (lost == 0 ? "" : ", " + lost + " dropped"));
		return named;
	}

	public function exportMidi(where:String):String {
		final named = suffixed(where, "mid");

		sys.io.File.saveBytes(named, Midi.write(session.song));
		session.say("exported " + name(named));
		return named;
	}

	public function exportWav(where:String):String {
		final named = suffixed(where, "wav");
		final span = session.song.tempo.samplesAt(session.song.ends());

		final frames = Std.int(span * (RATE / Tempo.TICKS));
		if (frames <= 0) {
			session.say("there is nothing to render");
			return "";
		}

		final stream = new Stream(roomFor(span));
		final sequencer = new Sequencer(session.song);
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

		session.say("rendered " + Math.round(frames * 10.0 / RATE) / 10 + " s to " + name(named));
		return named;
	}

	public static function suffixed(where:String, suffix:String):String {
		final held = haxe.io.Path.extension(where).toLowerCase();
		return held == suffix ? where : where + "." + suffix;
	}

	public static function name(where:String):String {
		return haxe.io.Path.withoutDirectory(where);
	}
}
