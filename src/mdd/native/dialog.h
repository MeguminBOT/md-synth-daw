#ifndef MDD_DIALOG_H
#define MDD_DIALOG_H

#include <SDL3/SDL.h>

#ifdef __cplusplus
extern "C" {
#endif

/**
 * A dialog that is still open. Its contents belong to dialog.cpp.
 */
typedef struct MddDialog MddDialog;

/**
 * State: still open.
 */
#define MDD_DIALOG_WAITING 0

/**
 * State: a path was picked.
 */
#define MDD_DIALOG_CHOSEN 1

/**
 * State: closed without picking.
 */
#define MDD_DIALOG_CANCELLED 2

/**
 * State: it would not open at all.
 */
#define MDD_DIALOG_FAILED 3

/**
 * Opens a dialog for choosing a file to read. It does not block: ask it for its
 * state on a later frame.
 *
 * @param window The window it belongs to.
 * @param label What the dialog is called.
 * @param suffix The file suffix to filter by.
 * @param where The folder to start in.
 * @return The open dialog.
 */
MddDialog *mdd_dialog_open(SDL_Window *window, const char *label, const char *suffix,
	const char *where);

/**
 * Opens a dialog for choosing where to write.
 *
 * @param window The window it belongs to.
 * @param label What the dialog is called.
 * @param suffix The file suffix to filter by.
 * @param where The folder to start in.
 * @return The open dialog.
 */
MddDialog *mdd_dialog_save(SDL_Window *window, const char *label, const char *suffix,
	const char *where);

/**
 * Opens a dialog for choosing a folder.
 *
 * @param window The window it belongs to.
 * @param where The folder to start in.
 * @return The open dialog.
 */
MddDialog *mdd_dialog_folder(SDL_Window *window, const char *where);

/**
 * @param dialog An open dialog.
 * @return One of the MDD_DIALOG_ values.
 */
int mdd_dialog_state(MddDialog *dialog);

/**
 * @param dialog A dialog that has been chosen.
 * @return The path that was picked.
 */
const char *mdd_dialog_path(MddDialog *dialog);

/**
 * Closes a dialog and frees it.
 *
 * @param dialog An open dialog.
 */
void mdd_dialog_close(MddDialog *dialog);

#ifdef __cplusplus
}
#endif

#endif
