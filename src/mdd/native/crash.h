#ifndef MDD_CRASH_H
#define MDD_CRASH_H

#ifdef __cplusplus
extern "C" {
#endif

/**
 * Installs the fault handler. A report names the Haxe file and line for every
 * frame, out of a release build that carries no Haxe stack at all, by reading the
 * generated C++ at the line the symbols name.
 *
 * @param path Where a report is written.
 * @param label What to call the process in it.
 * @param announce Nonzero to tell the reader a report was written.
 */
void mdd_crash_watch(const char *path, const char *label, int announce);

/**
 * Names the calling thread in any report, and reserves the last of its stack for
 * the handler. A stack overflow leaves no room to report a stack overflow: the
 * handler runs on the stack that just ran out, faults again, and the process dies
 * with nothing written. Every thread that could overflow has to call this, not
 * only the first.
 *
 * @param name What to call this thread.
 */
void mdd_crash_thread(const char *name);

#ifdef __cplusplus
}
#endif

#endif
