#ifndef MDD_ENCODE_H
#define MDD_ENCODE_H

#ifdef __cplusplus
extern "C" {
#endif

/**
 * Encodes Ogg Vorbis into a buffer the caller supplies.
 *
 * @param samples Interleaved samples at plus or minus one.
 * @param frames How many frames.
 * @param channels One or two.
 * @param rate The sample rate in hertz.
 * @param quality The Vorbis quality, 0 to 1.
 * @param tags The metadata, one entry a line.
 * @param into Where the file goes.
 * @param room How much room that buffer has.
 * @return How many bytes were written, or a negative number on a fault.
 */
int mdd_encode_vorbis(const float *samples, int frames, int channels, int rate,
	float quality, const char *tags, unsigned char *into, int room);

/**
 * Encodes Opus in an ogg stream into a buffer the caller supplies. Granule
 * positions are counted at 48 kHz whatever the source rate was, as the format
 * requires, and the pre-skip is written so the file decodes to exactly the sample
 * count it was given.
 *
 * @param samples Interleaved samples at plus or minus one.
 * @param frames How many frames.
 * @param channels One or two.
 * @param rate The sample rate in hertz.
 * @param bitrate The target bitrate in kilobits a second.
 * @param mode The application: local listening or streaming.
 * @param span_ms The frame size in milliseconds.
 * @param bitrate_mode Variable, constrained variable, or fixed.
 * @param tags The metadata, one entry a line.
 * @param into Where the file goes.
 * @param room How much room that buffer has.
 * @return How many bytes were written, or a negative number on a fault.
 */
int mdd_encode_opus(const float *samples, int frames, int channels, int rate,
	int bitrate, int mode, int span_ms, int bitrate_mode, const char *tags, unsigned char *into,
	int room);

#ifdef __cplusplus
}
#endif

#endif
