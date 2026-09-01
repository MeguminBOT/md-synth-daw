#ifndef MDD_DIALOG_H
#define MDD_DIALOG_H

#include <SDL3/SDL.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct MddDialog MddDialog;

#define MDD_DIALOG_WAITING 0
#define MDD_DIALOG_CHOSEN 1
#define MDD_DIALOG_CANCELLED 2
#define MDD_DIALOG_FAILED 3

MddDialog *mdd_dialog_open(SDL_Window *window, const char *label, const char *suffix,
	const char *where);
MddDialog *mdd_dialog_save(SDL_Window *window, const char *label, const char *suffix,
	const char *where);

int mdd_dialog_state(MddDialog *dialog);
const char *mdd_dialog_path(MddDialog *dialog);
void mdd_dialog_close(MddDialog *dialog);

#ifdef __cplusplus
}
#endif

#endif
