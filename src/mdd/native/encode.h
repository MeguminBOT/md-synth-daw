#ifndef MDD_ENCODE_H
#define MDD_ENCODE_H

#ifdef __cplusplus
extern "C" {
#endif

int mdd_encode_vorbis(const float *samples, int frames, int channels, int rate,
	float quality, const char *tags, unsigned char *into, int room);

int mdd_encode_opus(const float *samples, int frames, int channels, int rate,
	int bitrate, const char *tags, unsigned char *into, int room);

#ifdef __cplusplus
}
#endif

#endif
