#ifndef MDD_INSTANCE_H
#define MDD_INSTANCE_H

#ifdef __cplusplus
extern "C" {
#endif

int mdd_instance_claim(const char *name);
int mdd_instance_held(void);
void mdd_instance_release(void);

#ifdef __cplusplus
}
#endif

#endif
