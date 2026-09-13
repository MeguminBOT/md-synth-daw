#ifndef MDD_VIDEO_H
#define MDD_VIDEO_H

#ifdef __cplusplus
extern "C" {
#endif

/**
 * One WebM file being written: its VP9 encoder, its Opus encoder, the muxer both feed, and the
 * thread that does the encoding. Opaque to the caller, and freed by mdd_video_close.
 */
typedef struct MddVideo MddVideo;

/**
 * Opens a WebM file, sets up both encoders and starts the thread that encodes.
 *
 * @param path Where to write, as UTF-8.
 * @param width The frame width in pixels, which has to be even.
 * @param height The frame height in pixels, which has to be even.
 * @param fps Frames a second.
 * @param kilobits The video bitrate aimed at, in kilobits a second. Constant quality ignores it,
 *     and constrained quality holds it as a ceiling.
 * @param control The rate control, in libvpx's order: nought variable, one constant, two
 *     constrained quality, three constant quality.
 * @param quality The quantiser level the two quality controls aim at, nought to 63, where lower
 *     is better and larger.
 * @param speed The encoder speed, five to nine, where higher is faster and worse. The encoder is
 *     built realtime only, and that build takes nothing below five.
 * @param keyframes The longest run between key frames, in frames.
 * @param screen Nonzero to tune for screen content, nought for the default tuning.
 * @param rate The audio rate in hertz: 8000, 12000, 16000, 24000 or 48000.
 * @param channels One or two.
 * @param audio_kilobits The Opus bitrate in kilobits a second.
 * @param threads How many threads the VP9 encoder may use beside the one that feeds it, or
 *     nought for all but one of the processors.
 * @return The video, or NULL where the file or either encoder would not open.
 */
MddVideo *mdd_video_open(const char *path, int width, int height, int fps, int kilobits,
	int control, int quality, int speed, int keyframes, int screen, int rate, int channels,
	int audio_kilobits, int threads);

/**
 * Copies one frame to be encoded and put in the file, and returns without waiting for it
 * unless several frames are already waiting, so the caller never gets far ahead of the encoder.
 * The copy is taken before this returns, so the pixels can be reused straight away.
 *
 * @param video The video.
 * @param rgba The frame, width times height times four bytes, top row first.
 * @return Nought, or a negative number where an earlier frame or run of audio failed.
 */
int mdd_video_frame(MddVideo *video, const unsigned char *rgba);

/**
 * Copies audio to be encoded and put in the file, after the frames and audio given before it.
 * Samples short of a whole Opus packet wait for the next run, and the muxer holds audio back
 * until a frame at or after its time arrives, so the file still comes out in time order.
 *
 * @param video The video.
 * @param samples Interleaved samples at plus or minus one.
 * @param frames How many frames of samples.
 * @return Nought, or a negative number where an earlier frame or run of audio failed.
 */
int mdd_video_audio(MddVideo *video, const float *samples, int frames);

/**
 * Encodes whatever is still waiting, flushes both encoders, finishes the file and frees the
 * video, which cannot be used after.
 *
 * @param video The video.
 * @return Nought, or a negative number where anything given failed or the file could not be
 *     finished.
 */
int mdd_video_close(MddVideo *video);

#ifdef __cplusplus
}
#endif

#endif
