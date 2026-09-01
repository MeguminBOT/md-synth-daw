#ifndef MDD_AUDIO_H
#define MDD_AUDIO_H

#ifdef __cplusplus
extern "C" {
#endif

typedef struct MddDevice MddDevice;

MddDevice *mdd_audio_open(int rate, int period);
int mdd_audio_start(MddDevice *device);
void mdd_audio_stop(MddDevice *device);
void mdd_audio_close(MddDevice *device);

int mdd_audio_rate(MddDevice *device);
int mdd_audio_period(MddDevice *device);
int mdd_audio_periods(MddDevice *device);
int mdd_audio_buffer(MddDevice *device);
const char *mdd_audio_name(MddDevice *device);

int mdd_audio_write(MddDevice *device, const float *pairs, int frames);
int mdd_audio_room(MddDevice *device);
int mdd_audio_held(MddDevice *device);
int mdd_audio_capacity(MddDevice *device);

int mdd_audio_underruns(MddDevice *device);
int mdd_audio_taken(MddDevice *device);
void mdd_audio_forget(MddDevice *device);

double mdd_audio_latency(MddDevice *device);

#ifdef __cplusplus
}
#endif

#endif
