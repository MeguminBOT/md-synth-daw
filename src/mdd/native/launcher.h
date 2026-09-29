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

/**
 * Starts a program as an administrator, which Windows asks to be allowed first, and blocks until
 * that is answered. The question comes up in front where this process's window is in front, and
 * only as a flashing button on the taskbar where nothing of this process is, which is how Windows
 * treats a request from the background: asking before this process closes is what keeps it on the
 * screen. The program gets no window and none of this process's handles.
 *
 * Windows only. Elsewhere this answers -1.
 *
 * @param program The program, found the way the shell finds one.
 * @param parameters The rest of its command line, in UTF-8.
 * @return 1 where it was started, 0 where the question was declined, and -1 where it could not be
 *     asked at all.
 */
int mdd_launcher_elevated(const char *program, const char *parameters);

#ifdef __cplusplus
}
#endif

#endif
