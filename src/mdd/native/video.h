#ifndef MDD_VIDEO_H
#define MDD_VIDEO_H

#ifdef __cplusplus
extern "C" {
#endif

/**
 * One WebM file being written: its VP9 encoder, its Opus encoder and the muxer both feed.
 * Opaque to the caller, and freed by mdd_video_close.
 */
typedef struct MddVideo MddVideo;

/**
 * Opens a WebM file and sets up both encoders.
 *
 * @param path Where to write, as UTF-8.
 * @param width The frame width in pixels, which has to be even.
 * @param height The frame height in pixels, which has to be even.
 * @param fps Frames a second.
 * @param kilobits The video bitrate aimed at, in kilobits a second.
 * @param rate The audio rate in hertz: 8000, 12000, 16000, 24000 or 48000.
 * @param channels One or two.
 * @param audio_kilobits The Opus bitrate in kilobits a second.
 * @param threads How many threads the VP9 encoder may use.
 * @return The video, or NULL where the file or either encoder would not open.
 */
MddVideo *mdd_video_open(const char *path, int width, int height, int fps, int kilobits,
	int rate, int channels, int audio_kilobits, int threads);

/**
 * Encodes one frame and puts it in the file.
 *
 * @param video The video.
 * @param rgba The frame, width times height times four bytes, top row first.
 * @return Nought, or a negative number where the encoder or the muxer failed.
 */
int mdd_video_frame(MddVideo *video, const unsigned char *rgba);

/**
 * Encodes audio and puts it in the file. Samples that do not fill a whole Opus packet wait for
 * the next call, and the muxer holds audio back until a frame at or after its time arrives, so
 * audio and frames can be given in any order as long as each is in order on its own.
 *
 * @param video The video.
 * @param samples Interleaved samples at plus or minus one.
 * @param frames How many frames of samples.
 * @return Nought, or a negative number where the encoder or the muxer failed.
 */
int mdd_video_audio(MddVideo *video, const float *samples, int frames);

/**
 * Flushes both encoders, finishes the file and frees the video, which cannot be used after.
 *
 * @param video The video.
 * @return Nought, or a negative number where the file could not be finished.
 */
int mdd_video_close(MddVideo *video);

#ifdef __cplusplus
}
#endif

#endif
