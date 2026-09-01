package mdd.view;

import haxe.ds.Vector;
import mdd.format.Midi;
import mdd.format.Project;
import mdd.format.Vgm;
import mdd.format.Wav;
import mdd.host.Chooser;
import mdd.host.Dialog;
import mdd.host.Paths;
import mdd.host.Window;
import mdd.play.Render;
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

	public static inline final RATE = 44100;

	public var path(default, null):String = "";
	public var asking(default, null):Int = NOTHING;

	public var onLoad:Null<Song -> Void> = null;

	final session:Session;
	var chooser:cpp.Star<Chooser> = null;

	public function new(session:Session) {
		this.session = session;
	}

	public function ask(window:cpp.Star<Window>, what:Int):Void {
		if (asking != NOTHING) return;

		final where = path != "" ? haxe.io.Path.directory(path) : Paths.documents();

		asking = what;

		chooser = switch (what) {
			case OPEN: Dialog.open(window, "mdd project", "mdd", where);
			case SAVE: Dialog.save(window, "mdd project", "mdd", where);
			case VGM: Dialog.save(window, "vgm", "vgm", where);
			case WAV: Dialog.save(window, "wav", "wav", where);
			case MIDI: Dialog.save(window, "midi", "mid", where);
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
				case WAV: exportWav(where);
				case MIDI: exportMidi(where);
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

		session.say("opened " + name(where) + ", " + song.patterns.length + " patterns and "
			+ song.instruments.length + " instruments");
	}

	public function save(where:String):String {
		final named = suffixed(where, "mdd");

		Project.save(session.song, named);
		path = named;

		session.say("saved " + name(named));
		return named;
	}

	public function exportVgm(where:String):String {
		final named = suffixed(where, "vgm");
		final span = session.song.tempo.samplesAt(session.song.ends());

		final stream = new Stream(4194304);
		final sequencer = new Sequencer(session.song);

		var at = 0;
		while (at < span) {
			var until = at + 65536;
			if (until > span) until = span;

			sequencer.emit(stream, at, until);
			at = until;
		}

		sys.io.File.saveBytes(named, Vgm.write(stream, 0, span, session.song.tempo.rate));

		session.say("exported " + stream.count + " register writes to " + name(named));
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

		final stream = new Stream(4194304);
		final sequencer = new Sequencer(session.song);
		sequencer.emit(stream, 0, span);

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
