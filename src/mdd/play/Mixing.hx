package mdd.play;

@:unreflective
final class Mixing {
	public static inline final WAV = 0;
	public static inline final FLAC = 1;
	public static inline final OGG = 2;
	public static inline final OPUS = 3;
	public static inline final KINDS = 4;

	static final SUFFIXES:Array<String> = ["wav", "flac", "ogg", "opus"];
	public static final NAMES:Array<String> = ["WAV", "FLAC", "Ogg Vorbis", "Opus"];

	public static final RATES:Array<Int> = [22050, 32000, 44100, 48000, 88200, 96000];
	static final DEPTHS:Array<Int> = [16, 24, 32];
	public static final BITRATES:Array<Int> = [96, 128, 160, 192, 256, 320];

	static final OPUS_RATES:Array<Int> = [8000, 12000, 16000, 24000, 48000];

	public var kind:Int = FLAC;
	public var rate:Int = 44100;
	public var depth:Int = 16;
	public var stereo:Bool = true;

	public var quality:Int = 3;
	public var bitrate:Int = 192;

	public var opusMode:Int = 0;
	public var opusSpan:Int = 20;
	public var opusBitrateMode:Int = 0;

	public var padStart:Float = 0;
	public var padEnd:Float = 1;
	public var fade:Float = 0;

	public var normalise:Bool = true;
	public var ceiling:Float = 0;
	public var dither:Bool = true;
	public var console:Int = mdd.play.Render.MODEL_ONE;

	public var title:String = "";
	public var artist:String = "";
	public var album:String = "";
	public var comment:String = "";
	public var year:String = "";
	public var track:String = "";

	public function new() {}

	inline function lossy():Bool {
		return kind == OGG || kind == OPUS;
	}

	public inline function whole():Bool {
		return kind == WAV || kind == FLAC;
	}

	public inline function suffix():String {
		return kind >= 0 && kind < SUFFIXES.length ? SUFFIXES[kind] : "wav";
	}

	public inline function named():String {
		return kind >= 0 && kind < NAMES.length ? NAMES[kind] : "WAV";
	}

	public function worksAt():Int {
		if (kind != OPUS) return rate;

		for (held in OPUS_RATES) if (held == rate) return rate;

		return 48000;
	}

	public function channels():Int {
		return stereo ? 2 : 1;
	}

	public function copy():Mixing {
		final out = new Mixing();

		out.kind = kind;
		out.rate = rate;
		out.depth = depth;
		out.stereo = stereo;
		out.quality = quality;
		out.bitrate = bitrate;
		out.opusMode = opusMode;
		out.opusSpan = opusSpan;
		out.opusBitrateMode = opusBitrateMode;
		out.padStart = padStart;
		out.padEnd = padEnd;
		out.fade = fade;
		out.normalise = normalise;
		out.ceiling = ceiling;
		out.dither = dither;
		out.console = console;
		out.title = title;
		out.artist = artist;
		out.album = album;
		out.comment = comment;
		out.year = year;
		out.track = track;

		return out;
	}
}
