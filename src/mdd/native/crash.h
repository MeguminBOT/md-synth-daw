#ifndef MDD_CRASH_H
#define MDD_CRASH_H

#ifdef __cplusplus
extern "C" {
#endif

void mdd_crash_watch(const char *path, const char *label, int announce);
void mdd_crash_thread(const char *name);

#ifdef __cplusplus
}
#endif

#endif
