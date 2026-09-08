#ifndef MDD_VARY_H
#define MDD_VARY_H

#ifdef __cplusplus
extern "C" {
#endif

unsigned char *mdd_vary_instance(const unsigned char *data, long size, float weight, long *made);

int mdd_vary_weight(const unsigned char *data, long size);

int mdd_vary_resting(const unsigned char *data, long size);

#ifdef __cplusplus
}
#endif

#endif
