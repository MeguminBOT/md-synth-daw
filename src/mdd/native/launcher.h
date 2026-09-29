#ifndef MDD_LAUNCHER_H
#define MDD_LAUNCHER_H

#ifdef __cplusplus
extern "C" {
#endif

/**
 * Starts a command line on its own and returns at once: it gets no window, and none of the
 * handles this process holds, so it can outlive this process without keeping any of them open.
 * A handle it did inherit would keep a file this process holds open for as long as the command
 * runs, which is what the update handover waits on to see this process close.
 *
 * Windows only. Elsewhere a program started from a shell is already its own, and this answers
 * nought.
 *
 * @param command The whole command line, in UTF-8, the way CreateProcess reads one.
 * @return Nonzero where it was started.
 */
int mdd_launcher_detached(const char *command);

#ifdef __cplusplus
}
#endif

#endif
