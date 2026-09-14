#ifndef MDD_AUDIO_H
#define MDD_AUDIO_H

#ifdef __cplusplus
extern "C" {
#endif

/**
 * An open device. Its contents belong to audio.cpp and nothing outside reads into it.
 */
typedef struct MddDevice MddDevice;

/**
 * Opens a device through miniaudio and builds the ring behind it. The device is
 * opened stopped, so it never plays what has not been written.
 *
 * @param rate The rate to ask for, in hertz.
 * @param period Frames per callback to ask for.
 * @param name The playback device to open, as mdd_audio_named gives it, or NULL or an empty
 *     string for the system default. A name that is no longer there opens the default.
 * @return The device, or NULL where none would open.
 */
MddDevice *mdd_audio_open(int rate, int period, const char *name);

/**
 * Lists the playback devices the system has now, which mdd_audio_named then reads.
 *
 * @return How many there are.
 */
int mdd_audio_count(void);

/**
 * @param index Which device, below what mdd_audio_count last answered.
 * @return Its name as UTF-8, or an empty string for an index outside the list.
 */
const char *mdd_audio_named(int index);

/**
 * Starts the device playing.
 *
 * @param device The device.
 * @return Nonzero where it started.
 */
int mdd_audio_start(MddDevice *device);

/**
 * Stops it.
 *
 * @param device The device.
 */
void mdd_audio_stop(MddDevice *device);

/**
 * Stops it, gives its ring back, and frees it.
 *
 * @param device The device.
 */
void mdd_audio_close(MddDevice *device);

/**
 * @param device The device.
 * @return The rate it opened at, which is not always the one asked for.
 */
int mdd_audio_rate(MddDevice *device);

/**
 * @param device The device.
 * @return Frames per callback.
 */
int mdd_audio_period(MddDevice *device);

/**
 * @param device The device.
 * @return How many callbacks have happened.
 */
int mdd_audio_periods(MddDevice *device);

/**
 * @param device The device.
 * @return The buffer size the backend reports.
 */
int mdd_audio_buffer(MddDevice *device);

/**
 * @param device The device.
 * @return What the device is called.
 */
const char *mdd_audio_name(MddDevice *device);

/**
 * Puts frames into the ring the callback reads from. Called from the render thread.
 *
 * @param device The device.
 * @param pairs Interleaved stereo samples.
 * @param frames How many frames to write.
 * @return How many were taken.
 */
int mdd_audio_write(MddDevice *device, const float *pairs, int frames);

/**
 * @param device The device.
 * @return How many frames the ring has room for.
 */
int mdd_audio_room(MddDevice *device);

/**
 * @param device The device.
 * @return How many frames are waiting in it.
 */
int mdd_audio_held(MddDevice *device);

/**
 * @param device The device.
 * @return How many frames the ring holds in all.
 */
int mdd_audio_capacity(MddDevice *device);

/**
 * @param device The device.
 * @return How many times the callback found nothing to play.
 */
int mdd_audio_underruns(MddDevice *device);

/**
 * @param device The device.
 * @return How many frames the callback has consumed.
 */
int mdd_audio_taken(MddDevice *device);

/**
 * Sets the underrun and frame counts back to nought.
 *
 * @param device The device.
 */
void mdd_audio_forget(MddDevice *device);

/**
 * @param device The device.
 * @return How far behind the device is, in seconds.
 */
double mdd_audio_latency(MddDevice *device);

#ifdef __cplusplus
}
#endif

#endif
