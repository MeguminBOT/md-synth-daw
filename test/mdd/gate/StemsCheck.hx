package mdd.gate;

import mdd.app.Files;
import mdd.app.Session;
import mdd.format.Wav;
import mdd.play.Mixdown;
import mdd.play.Mixing;
import mdd.song.Clip;
import mdd.song.Instrument;
import mdd.song.Note;
import mdd.song.Part;
import mdd.song.Pattern;
import mdd.song.Song;
import mdd.song.Track;

/**
	A stem is the part rendered on its own, so what an export writes for one has to
	be what that part renders to by itself, every time.

	This is what says whether the bounce may be spread across processors. It holds
	the property any such change would have to keep: every stem byte for byte its
	own reference, and two exports of one piece agreeing.
**/
@:unreflective
class StemsCheck {
	/**
		How many parts the piece sounds, and so how many stems an export of it writes.
	**/
	static inline final SOUNDS = 6;

	static var failed:Int = 0;
	static var ran:Int = 0;

	public static function run(args:Array<String>):Int {
		final root = args.length > 0 ? args[0] : Gate.root;

		mdd.host.Native.ready();
		Sys.println("  stems");

		if (mdd.host.Sdl.init() == 0) {
			Sys.println("    SDL would not start: " + mdd.host.Sdl.error());
			return 1;
		}

		final song = piece();
		final parts = sounding(song);

		says("a piece sounds several parts", parts.length > 1,
			parts.length + " parts sound, so the export writes that many stems beside the"
			+ " mix");

		final first = exported(song, root + "/export/gate-stems-one.wav");
		final second = exported(song, root + "/export/gate-stems-two.wav");

		if (first == null || second == null) {
			says("a stem export finishes", false, "the export did not write");
			return done();
		}

		says("every part that sounds gets a stem", first.length == parts.length,
			first.length + " files written for " + parts.length + " sounding parts");

		matched(song, first, parts);
		repeated(first, second);

		return done();
	}

	/**
		Renders the piece with stems switched on, through the path the application
		uses, and reads back what it wrote.

		@param song The piece.
		@param into The file the mix goes to.
		@return The stems, each a part name and the bytes written for it, or null where
			the export did not finish.
	**/
	static function exported(song:Song, into:String):Null<Array<Held>> {
		final session = new Session(song);
		final files = new Files(session);
		final mixing = new Mixing();

		mixing.kind = Mixing.WAV;
		mixing.rate = 44100;
		mixing.padStart = 0;
		mixing.padEnd = 0;
		mixing.normalise = true;
		mixing.stems = true;

		files.mixing = mixing;

		final made = files.renders(into);
		final began = mdd.host.Sdl.ticks();

		while (!files.wroteYet()) {
			if (mdd.host.Sdl.ticks() - began > 60) return null;

			cpp.vm.Gc.safePoint();
			mdd.host.Sdl.sleep(0.002);
		}

		Sys.println("      export took "
			+ Math.round((mdd.host.Sdl.ticks() - began) * 100) / 100 + " s");

		if (files.wroteWrong != "") {
			says("a stem export raises nothing", false, files.wroteWrong);
			return null;
		}

		final where = haxe.io.Path.withoutExtension(into) + " stems";
		if (!sys.FileSystem.isDirectory(where)) return null;

		final out:Array<Held> = [];
		final names = sys.FileSystem.readDirectory(where);

		names.sort(function(one:String, two:String):Int return one < two ? -1 : 1);

		for (name in names) {
			out.push(new Held(haxe.io.Path.withoutExtension(name),
				sys.io.File.getBytes(where + "/" + name), made.gain));
		}

		return out;
	}

	/**
		Renders each part on its own, on this thread, and compares it to what the
		workers wrote for the same part.

		@param song The piece.
		@param held What the export wrote.
		@param parts Which parts sound.
	**/
	static function matched(song:Song, held:Array<Held>, parts:Array<Int>):Void {
		final mixing = new Mixing();

		mixing.kind = Mixing.WAV;
		mixing.rate = 44100;
		mixing.padStart = 0;
		mixing.padEnd = 0;
		mixing.normalise = true;

		var same = 0;
		var off = "";

		for (one in held) {
			final index = named(one.name, parts);

			if (index < 0) {
				off = one.name + " is not a part that sounds";
				continue;
			}

			final alone = Mixdown.made();

			alone.onlyPart = index;
			alone.sharedGain = one.gain;

			alone.runs(song, mixing);

			final want = Wav.write(alone.samples, alone.frames, alone.channels,
				alone.rate, mixing.depth, mixing.dither && mixing.depth < 32);

			if (want.compare(one.bytes) == 0) same++;
			else off = one.name + " differs, " + one.bytes.length + " bytes written"
				+ " against " + want.length + " rendered alone";
		}

		says("a stem is the part rendered on its own", same == held.length && off == "",
			off == "" ? same + " of " + held.length + " stems are byte for byte what the"
				+ " same part renders to on one thread" : off);
	}

	/**
		@param one One export.
		@param two Another of the same piece.
	**/
	static function repeated(one:Array<Held>, two:Array<Held>):Void {
		var same = 0;
		var off = "";

		for (index in 0...one.length) {
			if (index >= two.length) {
				off = "the second export wrote " + two.length + " stems";
				break;
			}

			if (one[index].name != two[index].name) {
				off = one[index].name + " against " + two[index].name;
				break;
			}

			if (one[index].bytes.compare(two[index].bytes) == 0) same++;
			else off = one[index].name + " differs between two exports of one piece";
		}

		says("and two exports of one piece agree", same == one.length && off == "",
			off == "" ? same + " of " + one.length + " stems are byte for byte the same"
				+ " across two runs" : off);
	}

	/**
		@param name A part name as a stem file carries it.
		@param parts Which parts sound.
		@return Which part it is, or -1 where none of them is called that.
	**/
	static function named(name:String, parts:Array<Int>):Int {
		for (index in parts) {
			final part:Part = index;
			if (part.name() == name) return index;
		}

		return -1;
	}

	/**
		@param song A piece.
		@return Which of its parts the arrangement sounds.
	**/
	static function sounding(song:Song):Array<Int> {
		final out:Array<Int> = [];

		for (index in 0...Part.COUNT) if (song.carries(index)) out.push(index);

		return out;
	}

	/**
		@return A short piece sounding several parts, so an export has more stems to
			write than it has workers to write them with.
	**/
	static function piece():Song {
		final song = new Song("stems", 96, 120);

		for (index in 0...Part.COUNT) {
			final part:Part = index;
			song.instrument(new Instrument(part.name().toLowerCase(), part));
			song.rack[index] = index;
		}

		final pattern = new Pattern("one", 384);
		song.add(pattern);

		for (index in 0...SOUNDS) {
			final part:Part = index;
			if (part.sampled()) continue;

			final lane = pattern.lane(part);

			lane.add(new Note(0, 96, 60 + index, 100));
			lane.add(new Note(192, 96, 48 + index, 90));
		}

		final track = song.track(new Track("one"));
		track.add(new Clip(0, 0, 384));

		return song;
	}

	static function says(name:String, ok:Bool, said:String):Void {
		ran++;
		if (!ok) failed++;
		Sys.println("    " + StringTools.rpad(name, " ", 46) + said + (ok ? "" : "   FAILED"));
	}

	static function done():Int {
		Sys.println("    " + (ran - failed) + " of " + ran + " checks");
		Sys.println(failed == 0 ? "    passed" : "    failed");

		return failed == 0 ? 0 : 1;
	}
}

/**
	One stem an export wrote, kept so it can be compared against the same part rendered
	on its own and against another export of the same piece.
**/
@:unreflective
private class Held {
	public final name:String;
	public final bytes:haxe.io.Bytes;

	/**
		The gain the mix arrived at, which every stem of that export is scaled by.
	**/
	public final gain:Float;

	public function new(name:String, bytes:haxe.io.Bytes, gain:Float) {
		this.name = name;
		this.bytes = bytes;
		this.gain = gain;
	}
}
