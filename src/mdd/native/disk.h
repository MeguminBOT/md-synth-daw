#ifndef MDD_DISK_H
#define MDD_DISK_H

#ifdef __cplusplus
extern "C" {
#endif

/**
 * Puts one file in place of another in a single step, so that whatever reads the name afterwards
 * finds either the old file or the new one and never neither. POSIX `rename` already does that;
 * on Windows `MoveFileExW` does when it is told to replace, where the standard library's rename
 * refuses a name that is taken and a caller had to delete the old file first.
 *
 * @param from The file just written, in UTF-8.
 * @param onto The name it takes, in UTF-8. Whatever was there is replaced.
 * @return Nonzero where it was moved.
 */
int mdd_disk_replace(const char *from, const char *onto);

#ifdef __cplusplus
}
#endif

#endif
