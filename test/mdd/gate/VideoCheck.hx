package mdd.gate;

import haxe.ds.Vector;
import haxe.io.Bytes;
import mdd.host.Video;
import sys.FileSystem;

@:unreflective

/**
	A WebM file written by the video writer, read back as a container and, where ffmpeg is on
	the path, decoded.

	Two seconds of moving colour bars and a 440 Hz tone go in at 320 by 180 and thirty frames a
	second. The container is walked here, element by element, so the check does not depend on a
	decoder the application never ships: the document type, both tracks and what they carry,
	every frame and packet and when each lands, and the cues and duration a player seeks with.
	Decoding a frame and the audio back needs something that decodes, which only ffmpeg is, so
	that half reports itself not run where there is none.
**/
class VideoCheck {
	static inline final WIDE = 320;
	static inline final TALL = 180;
	static inline final FPS = 30;
	static inline final FRAMES = 60;
	static inline final RATE = 48000;
	static inline final TONE = 440.0;
	static inline final LOOKED = 30;

	static var failed:Int = 0;
	static var ran:Int = 0;

	static var docType:String = "";
	static var hasCues:Bool = false;
	static var duration:Float = -1;
	static var scale:Float = 1000000;
	static var cluster:Float = 0;
	static var entryNumber:Int = 0;
	static var entryType:Int = 0;
	static var entryCodec:String = "";

	static final numbers:Array<Int> = [];
	static final kinds:Array<Int> = [];
	static final codecs:Array<String> = [];
	static final blocks:Array<Int> = [];
	static final lastAt:Array<Float> = [];
	static final keyed:Array<Bool> = [];

	static var pixelWide:Int = 0;
	static var pixelTall:Int = 0;
	static var sampled:Float = 0;
	static var channels:Int = 0;

	/**
		@param args The gate's arguments, unused.
		@return Nought where every check that ran held.
	**/
	public static function run(args:Array<String>):Int {
		failed = 0;
		ran = 0;

		Sys.println("  video");

		final where = Gate.root + "/export/video";
		mdd.host.Paths.make(where);

		final path = where + "/bars.webm";
		if (FileSystem.exists(path)) FileSystem.deleteFile(path);

		written(path);

		if (FileSystem.exists(path)) {
			walked(path);
			decoded(path, where);
		}

		Sys.println("    " + (ran - failed) + " of " + ran + " checks");

		if (failed > 0) {
			Sys.println("    failed");
			return 1;
		}

		Sys.println("    passed");
		return 0;
	}

	/**
		@param frame Which frame.
		@return That frame's pixels: eight colour bars moving four pixels a frame.
	**/
	static function barsAt(frame:Int):Bytes {
		final colours = [0xFFFFFF, 0xFFFF00, 0x00FFFF, 0x00FF00, 0xFF00FF, 0xFF0000, 0x0000FF,
			0x202020];
		final out = Bytes.alloc(WIDE * TALL * 4);

		for (row in 0...TALL) {
			for (column in 0...WIDE) {
				final bar = Std.int(((column + frame * 4) % WIDE) / (WIDE / 8));
				final colour = colours[bar];
				final at = (row * WIDE + column) * 4;

				out.set(at, (colour >> 16) & 0xFF);
				out.set(at + 1, (colour >> 8) & 0xFF);
				out.set(at + 2, colour & 0xFF);
				out.set(at + 3, 0xFF);
			}
		}

		return out;
	}

	/**
		Writes the video, a frame and the frame's audio at a time.

		@param path Where to write it.
	**/
	static function written(path:String):Void {
		final file = Video.open(path, WIDE, TALL, FPS, 800, RATE, 2, 96, 4);

		says("a video file opens", file != null, file != null ? "the writer is open on " + path
			: "the writer would not open, so nothing else here can run");

		if (file == null) return;

		final span = Std.int(RATE / FPS);
		final sound = new Vector<cpp.Float32>(span * 2);

		var faults = 0;
		var sample = 0;

		for (frame in 0...FRAMES) {
			for (index in 0...span) {
				final value = Math.sin(2 * Math.PI * TONE * sample / RATE) * 0.3;

				sound[index * 2] = value;
				sound[index * 2 + 1] = value;
				sample++;
			}

			if (Video.audio(file, cpp.Pointer.arrayElem(sound.toData(), 0).constRaw, span) != 0) {
				faults++;
			}

			final pixels = barsAt(frame);

			if (Video.frame(file, cpp.Pointer.arrayElem(pixels.getData(), 0).constRaw) != 0) {
				faults++;
			}
		}

		final closed = Video.close(file);
		final size = FileSystem.exists(path) ? FileSystem.stat(path).size : 0;

		says("and takes every frame and all the audio", faults == 0 && closed == 0 && size > 0,
			FRAMES + " frames and " + sample + " samples went in with " + faults
			+ " faults, closing said " + closed + ", and the file is " + size + " bytes");
	}

	/**
		Walks the file's elements and checks what they say.

		@param path The file.
	**/
	static function walked(path:String):Void {
		final bytes = sys.io.File.getBytes(path);

		cleared();
		walk(bytes, 0, bytes.length);

		final pictures = indexOf(1);
		final sounds = indexOf(2);

		says("it is WebM", docType == "webm", "the document type reads \"" + docType + "\"");

		final vp9 = pictures >= 0 && codecs[pictures] == "V_VP9";
		final opus = sounds >= 0 && codecs[sounds] == "A_OPUS";

		says("with a VP9 track and an Opus track", vp9 && opus && pixelWide == WIDE
			&& pixelTall == TALL && Std.int(sampled) == RATE && channels == 2,
			"the tracks carry " + codecs.join(" and ") + ", the picture is " + pixelWide + " by "
			+ pixelTall + ", the sound " + Std.int(sampled) + " Hz in " + channels + " channels");

		if (pictures < 0 || sounds < 0) return;

		final frameMs = 1000.0 / FPS;
		final lastFrame = (FRAMES - 1) * frameMs;

		says("every frame is in it, starting on a key frame",
			blocks[pictures] == FRAMES && keyed[pictures]
			&& Math.abs(lastAt[pictures] - lastFrame) < 1.5,
			blocks[pictures] + " frames of " + FRAMES + ", the first "
			+ (keyed[pictures] ? "a key frame" : "not a key frame") + ", the last at "
			+ round(lastAt[pictures]) + " ms against " + round(lastFrame));

		final seconds = FRAMES / FPS;
		final wanted = Std.int(seconds * 50);

		says("and the audio runs the whole length",
			blocks[sounds] >= wanted && blocks[sounds] <= wanted + 2
			&& lastAt[sounds] >= seconds * 1000 - 20,
			blocks[sounds] + " Opus packets for " + seconds + " s of twenty millisecond packets,"
			+ " the last at " + round(lastAt[sounds]) + " ms");

		final length = duration * scale / 1000000;

		says("and it carries cues and a duration to seek with",
			hasCues && Math.abs(length - seconds * 1000) < 50,
			(hasCues ? "cues are written" : "no cues") + ", and the duration is "
			+ round(length) + " ms");
	}

	/**
		Forgets what the last file walked said.
	**/
	static function cleared():Void {
		docType = "";
		hasCues = false;
		duration = -1;
		scale = 1000000;
		numbers.resize(0);
		kinds.resize(0);
		codecs.resize(0);
		blocks.resize(0);
		lastAt.resize(0);
		keyed.resize(0);
	}

	/**
		@param path A WebM file.
		@return How many frames its video track holds, or -1 where it has no video track.
	**/
	public static function framesIn(path:String):Int {
		final bytes = sys.io.File.getBytes(path);

		cleared();
		walk(bytes, 0, bytes.length);

		final pictures = indexOf(1);
		return pictures < 0 ? -1 : blocks[pictures];
	}

	static function indexOf(kind:Int):Int {
		for (index in 0...kinds.length) if (kinds[index] == kind) return index;
		return -1;
	}

	static function trackAt(number:Int):Int {
		for (index in 0...numbers.length) if (numbers[index] == number) return index;
		return -1;
	}

	/**
		@param bytes The file.
		@param at Where an element's size or identifier starts.
		@return How many bytes the variable length number there takes.
	**/
	static function widthAt(bytes:Bytes, at:Int):Int {
		final first = bytes.get(at);

		for (bit in 0...8) {
			if ((first & (0x80 >> bit)) != 0) return bit + 1;
		}

		return 8;
	}

	/**
		Walks a run of elements, going into the ones that hold others.

		@param bytes The file.
		@param from Where the run starts.
		@param until Where it ends.
	**/
	static function walk(bytes:Bytes, from:Int, until:Int):Void {
		var at = from;

		while (at < until) {
			final idWide = widthAt(bytes, at);
			var id = 0;

			for (index in 0...idWide) id = (id << 8) | bytes.get(at + index);

			at += idWide;

			final sizeWide = widthAt(bytes, at);
			var size = bytes.get(at) & (0xFF >> sizeWide);
			var unknown = size == (0xFF >> sizeWide);

			for (index in 1...sizeWide) {
				final next = bytes.get(at + index);
				size = size * 256 + next;
				if (next != 0xFF) unknown = false;
			}

			at += sizeWide;

			final end = unknown || at + size > until ? until : at + size;

			switch (id) {
				case 0x1A45DFA3, 0x18538067, 0x1654AE6B, 0x1F43B675, 0x1549A966, 0xE0, 0xE1,
						0xA0:
					walk(bytes, at, end);

				case 0xAE:
					entryNumber = 0;
					entryType = 0;
					entryCodec = "";

					walk(bytes, at, end);

					numbers.push(entryNumber);
					kinds.push(entryType);
					codecs.push(entryCodec);
					blocks.push(0);
					lastAt.push(-1);
					keyed.push(false);

				case 0x4282: docType = bytes.getString(at, end - at);
				case 0x86: entryCodec = bytes.getString(at, end - at);
				case 0xD7: entryNumber = unsigned(bytes, at, end);
				case 0x83: entryType = unsigned(bytes, at, end);
				case 0xB0: pixelWide = unsigned(bytes, at, end);
				case 0xBA: pixelTall = unsigned(bytes, at, end);
				case 0x9F: channels = unsigned(bytes, at, end);
				case 0xB5: sampled = floating(bytes, at, end);
				case 0x4489: duration = floating(bytes, at, end);
				case 0x2AD7B1: scale = unsigned(bytes, at, end);
				case 0xE7: cluster = unsigned(bytes, at, end);
				case 0x1C53BB6B: hasCues = true;

				case 0xA3, 0xA1:
					final trackWide = widthAt(bytes, at);
					final track = bytes.get(at) & (0xFF >> trackWide);
					final place = trackAt(track);

					if (place >= 0) {
						final high = bytes.get(at + trackWide);
						final low = bytes.get(at + trackWide + 1);
						var relative = (high << 8) | low;
						if (relative >= 0x8000) relative -= 0x10000;

						final flags = bytes.get(at + trackWide + 2);
						final when = (cluster + relative) * scale / 1000000;

						if (blocks[place] == 0) keyed[place] = id == 0xA3 && (flags & 0x80) != 0;

						blocks[place]++;
						if (when > lastAt[place]) lastAt[place] = when;
					}

				case _:
			}

			at = end;
		}
	}

	static function unsigned(bytes:Bytes, from:Int, until:Int):Int {
		var value = 0;
		for (at in from...until) value = (value << 8) | bytes.get(at);
		return value;
	}

	static function floating(bytes:Bytes, from:Int, until:Int):Float {
		if (until - from == 4) {
			return haxe.io.FPHelper.i32ToFloat(unsigned(bytes, from, until));
		}

		if (until - from == 8) {
			return haxe.io.FPHelper.i64ToDouble(unsigned(bytes, from + 4, until),
				unsigned(bytes, from, from + 4));
		}

		return 0;
	}

	/**
		Decodes one frame and the audio back with ffmpeg, where there is one.

		@param path The file.
		@param where A folder to decode into.
	**/
	static function decoded(path:String, where:String):Void {
		if (!present("ffmpeg")) {
			Sys.println("    not run: ffmpeg is not on the path, so nothing decoded the file back");
			return;
		}

		final picture = where + "/frame.rgb";
		final sound = where + "/sound.raw";

		if (FileSystem.exists(picture)) FileSystem.deleteFile(picture);
		if (FileSystem.exists(sound)) FileSystem.deleteFile(sound);

		final pictured = Sys.command("ffmpeg", ["-v", "error", "-y", "-i", path, "-vf",
			"trim=start_frame=" + LOOKED + ":end_frame=" + (LOOKED + 1), "-frames:v", "1",
			"-f", "rawvideo", "-pix_fmt", "rgb24", picture]);

		final expected = barsAt(LOOKED);

		if (pictured != 0 || !FileSystem.exists(picture)) {
			says("ffmpeg decodes a frame back", false, "ffmpeg said " + pictured);
		} else {
			final got = sys.io.File.getBytes(picture);
			var apart = 0.0;
			var counted = 0;

			if (got.length == WIDE * TALL * 3) {
				for (index in 0...WIDE * TALL) {
					for (channel in 0...3) {
						final diff = got.get(index * 3 + channel) - expected.get(index * 4 + channel);
						apart += diff < 0 ? -diff : diff;
						counted++;
					}
				}
			}

			final mean = counted == 0 ? 255.0 : apart / counted;

			says("ffmpeg decodes a frame back to the bars that went in",
				got.length == WIDE * TALL * 3 && mean < 12,
				"frame " + LOOKED + " comes back " + got.length + " bytes, " + round(mean)
				+ " levels from the source on average");
		}

		final sounded = Sys.command("ffmpeg", ["-v", "error", "-y", "-i", path, "-f", "s16le",
			"-ac", "1", "-ar", "" + RATE, sound]);

		if (sounded != 0 || !FileSystem.exists(sound)) {
			says("and decodes the audio back", false, "ffmpeg said " + sounded);
			return;
		}

		final raw = sys.io.File.getBytes(sound);
		final many = Std.int(raw.length / 2);

		var crossings = 0;
		var last = 0;

		final from = Std.int(RATE * 0.25);
		final until = many - Std.int(RATE * 0.25);

		for (index in from...until) {
			var value = raw.get(index * 2) | (raw.get(index * 2 + 1) << 8);
			if (value >= 0x8000) value -= 0x10000;

			if (last < 0 && value >= 0) crossings++;
			last = value;
		}

		final span = (until - from) / RATE;
		final hertz = span <= 0 ? 0.0 : crossings / span;
		final wanted = Std.int(FRAMES / FPS * RATE);

		says("and decodes the audio back to the tone that went in",
			Math.abs(many - wanted) <= 960 && Math.abs(hertz - TONE) < 3,
			many + " samples against " + wanted + ", at " + round(hertz) + " Hz against "
			+ TONE);
	}

	/**
		@param tool A program.
		@return Whether it runs from the path.
	**/
	public static function present(tool:String):Bool {
		try {
			final process = new sys.io.Process(tool, ["-version"]);
			final code = process.exitCode();

			process.close();
			return code == 0;
		} catch (e:Dynamic) {
			return false;
		}
	}

	static function round(value:Float):Float {
		return Math.round(value * 100) / 100;
	}

	static function says(name:String, ok:Bool, said:String):Void {
		ran++;
		if (!ok) failed++;

		Sys.println("    " + StringTools.rpad(name, " ", 34) + said + (ok ? "" : "   FAILED"));
	}
}
