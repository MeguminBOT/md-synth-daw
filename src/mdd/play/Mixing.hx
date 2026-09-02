package mdd.play;

@:unreflective
final class Mixing {
	public static inline final WAV = 0;
	public static inline final FLAC = 1;
	public static inline final OGG = 2;
	public static inline final OPUS = 3;
	public static inline final MP3 = 4;
	public static inline final KINDS = 5;

	public static final SUFFIXES:Array<String> = ["wav", "flac", "ogg", "opus", "mp3"];
	public static final NAMES:Array<String> = ["WAV", "FLAC", "Ogg Vorbis", "Opus", "MP3"];

	public static final RATES:Array<Int> = [22050, 32000, 44100, 48000, 88200, 96000];
	public static final DEPTHS:Array<Int> = [16, 24, 32];
	public static final BITRATES:Array<Int> = [96, 128, 160, 192, 256, 320];

	public var kind:Int = WAV;
	public var rate:Int = 44100;
	public var depth:Int = 16;
	public var stereo:Bool = true;

	public var quality:Int = 5;
	public var bitrate:Int = 192;

	public var padStart:Float = 0;
	public var padEnd:Float = 1;
	public var fade:Float = 0;

	public var normalise:Bool = true;
	public var ceiling:Float = -1;
	public var dither:Bool = true;

	public var title:String = "";
	public var artist:String = "";
	public var album:String = "";
	public var comment:String = "";
	public var year:String = "";
	public var track:String = "";

	public function new() {}

	public inline function lossy():Bool {
		return kind == OGG || kind == OPUS || kind == MP3;
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
		out.padStart = padStart;
		out.padEnd = padEnd;
		out.fade = fade;
		out.normalise = normalise;
		out.ceiling = ceiling;
		out.dither = dither;
		out.title = title;
		out.artist = artist;
		out.album = album;
		out.comment = comment;
		out.year = year;
		out.track = track;

		return out;
	}
}
