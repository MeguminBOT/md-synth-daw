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
	public static final SIZES:Array<Int> = [1280, 720, 1920, 1080, 2560, 1440, 3840, 2160];

	/**
		The frame rates a video is offered at.
	**/
	public static final FRAME_RATES:Array<Int> = [24, 25, 30, 48, 50, 60];

	/**
		The longest runs between key frames a video is offered, in seconds.
	**/
	public static final KEYFRAME_INTERVALS:Array<Float> = [0.5, 1, 2, 5, 10];

	/**
		The Opus bitrate a video's audio starts at, in kilobits a second, which is what YouTube's
		recommended upload settings ask of stereo.
	**/
	public static inline final VIDEO_AUDIO_KILOBITS = 384;

	/**
		Rate control: the video bitrate is an average the encoder moves around.
	**/
	public static inline final VBR = 0;

	/**
		Rate control: the video bitrate is held.
	**/
	public static inline final CBR = 1;

	/**
		Rate control: a quality level, with the video bitrate as its ceiling.
	**/
	public static inline final CQ = 2;

	/**
		Rate control: a quality level, whatever it costs.
	**/
	public static inline final Q = 3;

	/**
		Which format, one of `WAV` to `WEBM`.
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

		The video settings start at YouTube's recommended upload settings where it gives one: 60
		frames, a variable bitrate at its figure for the size and frame rate, and a key frame every
		half second. It names no size, so a video starts at 2560 by 1440.
	**/
	public var size:Int = 2;

	/**
		Frames a second, for a video.
	**/
	public var fps:Int = 60;

	/**
		The video bitrate in kilobits a second, or nought to take one from the size and frame rate.
	**/
	public var videoBitrate:Int = 0;

	/**
		How the video bitrate is controlled, one of `VBR` to `Q`.
	**/
	public var rateControl:Int = VBR;

	/**
		The quantiser level `CQ` and `Q` aim at, nought to 63, where lower is better and larger.
	**/
	public var qualityLevel:Int = 24;

	/**
		The VP9 encoder speed, five to nine, where higher is faster and worse.
	**/
	public var encoderSpeed:Int = 5;

	/**
		The longest run between key frames, in seconds. Half a second is YouTube's closed group of
		pictures half the frame rate long.
	**/
	public var keyframeInterval:Float = 0.5;

	/**
		Whether the video encoder is tuned for screen content, which a scope is.
	**/
	public var screen:Bool = true;

	/**
		Whether a video keeps its colour at full resolution, 4:4:4 in VP9 profile 1, rather than
		halving it both ways as 4:2:0. A scope is thin coloured lines, which lose more than half
		their colour at 4:2:0.
	**/
	public var fullChroma:Bool = true;

	/**
		What a video's scope shows, the scope's own `WAVEFORM` or `SPECTRUM`: nought for the
		waveform and one for the spectrum.
	**/
	public var scopeView:Int = 0;

	/**
		Which of the scope's speeds a video's lanes run at, by index, the scope's starting speed
		unless chosen.
	**/
	public var scopeSpeed:Int = 2;

	/**
		Which of the scope's accuracies a video's lanes keep, by index, the scope's starting
		accuracy unless chosen.
	**/
	public var scopeAccuracy:Int = 0;

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
		Whether the writes smooth the edges the parts would otherwise click on, which is what the
		sequencer's own switch does. A register format written to hold exactly what a piece plays
		can be written with it off.
	**/
	public var declick:Bool = true;

	/**
		Which output stage the render goes through, from `mdd.play.Render`.
	**/
	public var console:Int = mdd.play.Render.MODEL_ONE;

	/**
		Stems: none written beside the mix.
	**/
	public static inline final NO_STEMS = 0;

	/**
		Stems: one file per track that plays notes, named after the track.
	**/
	public static inline final TRACK_STEMS = 1;

	/**
		Stems: one file per part the arrangement sounds, named after the part.
	**/
	public static inline final CHANNEL_STEMS = 2;

	/**
		Which stems the export writes beside the mix: `NO_STEMS`, `TRACK_STEMS` or `CHANNEL_STEMS`.

		Every stem is scaled by the gain the mix worked out rather than normalised on its
		own, so the stems sum back to the mix instead of each arriving at its own
		loudness.
	**/
	public var stems:Int = NO_STEMS;

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
		@return The video bitrate aimed at, in kilobits a second: `videoBitrate` where it is set,
			and otherwise YouTube's recommended bitrate for an SDR upload of the picture size, where
			48 frames a second and above take its high frame rate figure. Where YouTube gives a
			range, this is the low end of it.
	**/
	public function kilobits():Int {
		if (videoBitrate > 0) return videoBitrate;

		final lines = tall();
		final high = fps > 30;

		if (lines >= 2160) return high ? 53000 : 35000;
		if (lines >= 1440) return high ? 24000 : 16000;
		if (lines >= 1080) return high ? 12000 : 8000;

		return high ? 7500 : 5000;
	}

	/**
		@return The longest run between key frames, in frames, never below one.
	**/
	public function keyframeDistance():Int {
		final frames = Math.round(fps * keyframeInterval);
		return frames < 1 ? 1 : frames;
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
		out.videoBitrate = videoBitrate;
		out.rateControl = rateControl;
		out.qualityLevel = qualityLevel;
		out.encoderSpeed = encoderSpeed;
		out.keyframeInterval = keyframeInterval;
		out.screen = screen;
		out.fullChroma = fullChroma;
		out.scopeView = scopeView;
		out.scopeSpeed = scopeSpeed;
		out.scopeAccuracy = scopeAccuracy;
		out.padStart = padStart;
		out.padEnd = padEnd;
		out.fade = fade;
		out.normalise = normalise;
		out.ceiling = ceiling;
		out.dither = dither;
		out.console = console;
		out.declick = declick;
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
