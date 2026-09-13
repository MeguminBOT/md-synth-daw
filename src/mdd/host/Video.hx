package mdd.host;

@:include("video.h")

/**
	The scope video writer compiled into the binary: VP9 frames and Opus audio muxed into WebM.

	Frames and audio are handed over as they are made and nothing is kept on this side between
	calls, so a long video costs no more memory than a short one.
**/
extern class Video {
	/**
		Opens a WebM file and sets up both encoders.

		@param path Where to write, as UTF-8.
		@param width The frame width in pixels, which has to be even.
		@param height The frame height in pixels, which has to be even.
		@param fps Frames a second.
		@param kilobits The video bitrate aimed at, in kilobits a second. Constant quality ignores
			it, and constrained quality holds it as a ceiling.
		@param control The rate control, one of `Mixing.VBR` to `Mixing.Q`.
		@param quality The quantiser level the two quality controls aim at, nought to 63, where
			lower is better and larger.
		@param speed The encoder speed, five to nine, where higher is faster and worse.
		@param keyframes The longest run between key frames, in frames.
		@param screen One to tune for screen content, nought for the default tuning.
		@param rate The audio rate: 8000, 12000, 16000, 24000 or 48000 hertz.
		@param channels One or two.
		@param audioKilobits The Opus bitrate in kilobits a second.
		@param threads How many threads the VP9 encoder may use beside the one that feeds it, or
			nought for all but one of the processors.
		@return The file being written, or null where it or either encoder would not open.
	**/
	@:native("mdd_video_open")
	public static function open(path:cpp.ConstCharStar, width:Int, height:Int, fps:Int,
		kilobits:Int, control:Int, quality:Int, speed:Int, keyframes:Int, screen:Int, rate:Int,
		channels:Int, audioKilobits:Int, threads:Int):cpp.Star<VideoFile>;

	/**
		Encodes one frame and puts it in the file.

		@param video The file being written.
		@param rgba The frame, width times height times four bytes, top row first.
		@return Nought, or a negative number where the encoder or the muxer failed.
	**/
	@:native("mdd_video_frame")
	public static function frame(video:cpp.Star<VideoFile>, rgba:cpp.RawConstPointer<cpp.UInt8>):Int;

	/**
		Encodes audio and puts it in the file. Samples short of a whole packet wait for the next
		call, and the muxer holds audio back until a frame at or after its time arrives.

		@param video The file being written.
		@param samples Interleaved samples at plus or minus one.
		@param frames How many frames of samples.
		@return Nought, or a negative number where the encoder or the muxer failed.
	**/
	@:native("mdd_video_audio")
	public static function audio(video:cpp.Star<VideoFile>,
		samples:cpp.RawConstPointer<cpp.Float32>, frames:Int):Int;

	/**
		Flushes both encoders, finishes the file and frees it, which cannot be used after.

		@param video The file being written.
		@return Nought, or a negative number where the file could not be finished.
	**/
	@:native("mdd_video_close")
	public static function close(video:cpp.Star<VideoFile>):Int;
}
