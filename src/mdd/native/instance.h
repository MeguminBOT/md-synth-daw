#ifndef MDD_INSTANCE_H
#define MDD_INSTANCE_H

#ifdef __cplusplus
extern "C" {
#endif

/**
 * Takes a named lock, so a second copy of the application can find the first.
 *
 * @param name The name to claim.
 * @return Nonzero where this process took it.
 */
int mdd_instance_claim(const char *name);

/**
 * @return Nonzero where this process holds it.
 */
int mdd_instance_held(void);

/**
 * Gives the lock back.
 */
void mdd_instance_release(void);

#ifdef __cplusplus
}
#endif

#endif
