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
 * Gives the lock back, and stops listening for a second copy.
 */
void mdd_instance_release(void);

/**
 * Starts listening for a second copy handing over what it was opened with: a named pipe on
 * Windows and a socket beside the lock file elsewhere. Only the copy holding the lock listens.
 *
 * @param name The name the lock was claimed under.
 * @return Nonzero where it is listening.
 */
int mdd_instance_listen(const char *name);

/**
 * Hands text to the copy holding the lock and lets it come to the front. Blocks, retrying,
 * while that copy has the lock but is not listening yet.
 *
 * @param name The name the lock was claimed under.
 * @param text What to hand over, in UTF-8, which may be empty.
 * @param wait The most milliseconds to keep retrying.
 * @return Nonzero where the other copy took all of it.
 */
int mdd_instance_hand(const char *name, const char *text, int wait);

/**
 * Takes one handover a second copy made, without waiting for one to arrive. A copy that has
 * connected is read until it closes, for at most a quarter of a second.
 *
 * @return How many bytes arrived, which may be nought, or -1 where no copy handed anything
 *     over. The text is read back with mdd_instance_taken.
 */
int mdd_instance_take(void);

/**
 * @return The text the last mdd_instance_take read, in UTF-8. Valid until the next take.
 */
const char *mdd_instance_taken(void);

/**
 * @return How many arguments the process was started with, its own name included, where the
 *     platform keeps them as something other than UTF-8, or -1 where the runtime's own list is
 *     already right. Windows keeps a wide command line, and the narrow one the runtime reads
 *     carries the system code page.
 */
int mdd_instance_arguments(void);

/**
 * @param index Which argument, nought being the program itself.
 * @return It in UTF-8, or an empty string out of range. Valid until the next call.
 */
const char *mdd_instance_argument(int index);

#ifdef __cplusplus
}
#endif

#endif
