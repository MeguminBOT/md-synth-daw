package mdd.view;

import haxe.ds.Vector;
import mdd.format.Midi;
import mdd.format.Project;
import mdd.format.Transcription;
import mdd.format.Vgm;
import mdd.format.Wav;
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

	public static inline final RATE = 44100;
	public static inline final DAC_RATE = 8000;

	public var path(default, null):String = "";
	public var asking(default, null):Int = NOTHING;

	public var every:Float = 0;
	public var since(default, null):Float = 0;
	public var kept(default, null):Int = 0;
	public var recovered(default, null):String = "";

	var edits:Int = -1;

	public var onLoad:Null<Song -> Void> = null;

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

		session.say(path != "" ? "saved on its own" : "kept a recovery beside the settings");
		return true;
	}

	public function recovery():String {
		return Paths.within("projects") + "/recovered.mdd";
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
			case OPEN: Dialog.open(window, "mdd project", "mdd", where);
			case SAVE: Dialog.save(window, "mdd project", "mdd", where);
			case VGM: Dialog.save(window, "vgm", "vgm", where);
			case WAV: Dialog.save(window, "wav", "wav", where);
			case MIDI: Dialog.save(window, "midi", "mid", where);
			case XGM: Dialog.save(window, "xgm", "xgm", where);
			case AUDIO: Dialog.save(window, mixing.named(), mixing.suffix(), where);
			case READ_VGM: Dialog.open(window, "vgm", "vgm", where);
			case READ_MIDI: Dialog.open(window, "midi", "mid", where);
			case READ_WAV: Dialog.open(window, "wav", "wav", where);
			case READ_XGM: Dialog.open(window, "xgm", "xgm", where);
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

		took(what, where);
		return true;
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

		path = "";
		if (onLoad != null) onLoad(made.song);
		forget();

		session.say("read " + name(where) + ", " + made.notes + " notes on "
			+ made.song.patterns.length + " patterns at " + Math.round(made.beats)
			+ " bpm, " + xgm.samples + " samples and " + xgm.struck + " converter hits");
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
		final named = suffixed(where, "mdd");

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
		sys.io.File.saveBytes(named, Vgm.write(stream, 0, span, session.song.tempo.rate));

		session.say("exported " + stream.count + " register writes to " + name(named)
			+ (sequencer.lost + stream.dropped == 0 ? ""
			: ", " + (sequencer.lost + stream.dropped) + " dropped"));
		return named;
	}

	public var mixing:Mixing = new Mixing();

	public function exportAudio(where:String):String {
		final named = suffixed(where, mixing.suffix());
		final made = Mixdown.of(session.song, mixing);

		if (made.frames <= 0) {
			session.say("there is nothing to render");
			return "";
		}

		final bytes = mixing.kind == Mixing.FLAC
			? Flac.write(made.samples, made.frames, made.channels, made.rate, mixing.depth,
				tagged())
			: Wav.write(made.samples, made.frames, made.channels, made.rate, mixing.depth,
				mixing.dither && mixing.depth < 32);

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
		sys.io.File.saveBytes(named, made);

		session.say("exported " + made.length + " bytes to " + name(named)
			+ (sequencer.lost + stream.dropped == 0 ? ""
			: ", " + (sequencer.lost + stream.dropped) + " dropped"));
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
