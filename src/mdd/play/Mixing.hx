package mdd.play;

/**
	Everything one export is set to: the format, the rate, what is padded and faded on,
	how it is normalised, which output stage it goes through, and the tags written into
	the file.

	It is plain settings and no behaviour, so an export panel can hold one of its own
	and hand a copy to the render. That is what keeps the export window and the
	preferences from sharing a setting neither of them meant to share.
**/
@:unreflective
final class Mixing {
	/**
		Format: uncompressed PCM in a RIFF wave.
	**/
	public static inline final WAV = 0;

	/**
		Format: FLAC, from this repository's own encoder.
	**/
	public static inline final FLAC = 1;

	/**
		Format: Ogg Vorbis.
	**/
	public static inline final OGG = 2;

	/**
		Format: Opus in an ogg stream.
	**/
	public static inline final OPUS = 3;

	/**
		Format: a WebM video of the scope, VP9 pictures over Opus audio.
	**/
	public static inline final WEBM = 4;

	/**
		How many formats there are.
	**/
	public static inline final KINDS = 5;

	/**
		The file suffix of each format.
	**/
	static final SUFFIXES:Array<String> = ["wav", "flac", "ogg", "opus", "webm"];

	/**
		The name of each format as the interface shows it.
	**/
	public static final NAMES:Array<String> = ["WAV", "FLAC", "Ogg Vorbis", "Opus", "WebM video"];

	/**
		The sample rates on offer.
	**/
	public static final RATES:Array<Int> = [22050, 32000, 44100, 48000, 88200, 96000];

	/**
		The bit depths on offer, for the formats that carry whole samples.
	**/
	static final DEPTHS:Array<Int> = [16, 24, 32];

	/**
		The bitrates on offer, in kilobits a second.
	**/
	public static final BITRATES:Array<Int> = [96, 128, 160, 192, 256, 320];

	/**
		The only rates Opus itself accepts. Anything else is pinned to 48000 rather than
		resampled behind the composer.
	**/
	static final OPUS_RATES:Array<Int> = [8000, 12000, 16000, 24000, 48000];

	/**
		The picture sizes a video is offered at, a width and a height for each.
	**/
	public static final SIZES:Array<Int> = [1280, 720, 1920, 1080];

	/**
		The frame rates a video is offered at.
	**/
	public static final FRAME_RATES:Array<Int> = [30, 60];

	/**
		Which format, one of `WAV` to `OPUS`.
	**/
	public var kind:Int = FLAC;

	/**
		The sample rate in hertz.
	**/
	public var rate:Int = 44100;

	/**
		Bits per sample, for `WAV` and `FLAC`.
	**/
	public var depth:Int = 16;

	/**
		Whether the file has two channels or one.
	**/
	public var stereo:Bool = true;

	/**
		Encoder effort. For FLAC it is the compression level; for Vorbis it is the quality.
	**/
	public var quality:Int = 3;

	/**
		Target bitrate in kilobits a second, for Opus.
	**/
	public var bitrate:Int = 192;

	/**
		Opus application: 0 for local listening and 1 for streaming.
	**/
	public var opusMode:Int = 0;

	/**
		Opus frame size in milliseconds.
	**/
	public var opusSpan:Int = 20;

	/**
		Opus bitrate mode: 0 variable, 1 constrained variable, 2 fixed.
	**/
	public var opusBitrateMode:Int = 0;

	/**
		Which of `SIZES` a video is drawn at, counted in pairs.
	**/
	public var size:Int = 0;

	/**
		Frames a second, for a video.
	**/
	public var fps:Int = 60;

	/**
		Seconds of silence before the piece.
	**/
	public var padStart:Float = 0;

	/**
		Seconds of silence after it.
	**/
	public var padEnd:Float = 1;

	/**
		Seconds of fade at the end, inside the piece.
	**/
	public var fade:Float = 0;

	/**
		Whether the peak is scaled to `ceiling`.
	**/
	public var normalise:Bool = true;

	/**
		Where the loudest sample lands, in decibels below full scale. This is peak based
		and says nothing about how loud the piece feels; nothing here measures LUFS.
	**/
	public var ceiling:Float = 0;

	/**
		Whether to dither when going down to a whole number of bits.
	**/
	public var dither:Bool = true;

	/**
		Which output stage the render goes through, from `mdd.play.Render`.
	**/
	public var console:Int = mdd.play.Render.MODEL_ONE;

	/**
		Whether the export writes one file per part beside the mix.

		Every stem is scaled by the gain the mix worked out rather than normalised on its
		own, so the stems sum back to the mix instead of each arriving at its own
		loudness.
	**/
	public var stems:Bool = false;

	/**
		Tag written into the file, where the format has tags.
	**/
	public var title:String = "";
	public var artist:String = "";
	public var album:String = "";
	public var comment:String = "";
	public var year:String = "";
	public var track:String = "";

	public function new() {}

	/**
		@return True for the formats that throw information away.
	**/
	inline function lossy():Bool {
		return kind == OGG || kind == OPUS || kind == WEBM;
	}

	/**
		@return True for the formats that carry whole numbered samples, so bit depth and dither mean
			something.
	**/
	public inline function whole():Bool {
		return kind == WAV || kind == FLAC;
	}

	/**
		@return The file suffix for this format, with no dot.
	**/
	public inline function suffix():String {
		return kind >= 0 && kind < SUFFIXES.length ? SUFFIXES[kind] : "wav";
	}

	/**
		@return The name of this format as the interface shows it.
	**/
	public inline function named():String {
		return kind >= 0 && kind < NAMES.length ? NAMES[kind] : "WAV";
	}

	/**
		@return Whether this export is a video rather than audio alone.
	**/
	public inline function moving():Bool {
		return kind == WEBM;
	}

	/**
		@return How wide a video is drawn, in pixels.
	**/
	public function wide():Int {
		final at = size < 0 ? 0 : (size * 2 >= SIZES.length ? SIZES.length - 2 : size * 2);
		return SIZES[at];
	}

	/**
		@return How tall a video is drawn, in pixels.
	**/
	public function tall():Int {
		final at = size < 0 ? 0 : (size * 2 >= SIZES.length ? SIZES.length - 2 : size * 2);
		return SIZES[at + 1];
	}

	/**
		@return The video bitrate aimed at, in kilobits a second, which rises with the picture size
			and the frame rate. A scope is lines on a flat ground and codes cheaply, so these sit
			well below what footage of the same size would want.
	**/
	public function kilobits():Int {
		final base = wide() >= 1920 ? 5000 : 2500;
		return fps > 30 ? Std.int(base * 1.6) : base;
	}

	/**
		@return The rate this export will actually be written at, which is 48000 for Opus unless the
			chosen rate is one Opus accepts.
	**/
	public function worksAt():Int {
		if (kind != OPUS && kind != WEBM) return rate;

		for (held in OPUS_RATES) if (held == rate) return rate;

		return 48000;
	}

	/**
		@return Two or one.
	**/
	public function channels():Int {
		return stereo ? 2 : 1;
	}

	/**
		Takes a copy, so a panel can hand its settings to a render without the two then
		sharing them.

		@return A new `Mixing` with the same values.
	**/
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
		out.size = size;
		out.fps = fps;
		out.padStart = padStart;
		out.padEnd = padEnd;
		out.fade = fade;
		out.normalise = normalise;
		out.ceiling = ceiling;
		out.dither = dither;
		out.console = console;
		out.stems = stems;
		out.title = title;
		out.artist = artist;
		out.album = album;
		out.comment = comment;
		out.year = year;
		out.track = track;

		return out;
	}
}
