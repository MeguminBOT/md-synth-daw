/**
 * The system file dialogs, through SDL.
 *
 * SDL answers a dialog on its own thread, so the result is kept in a small structure
 * the caller asks for the state of on a later frame. Nothing here blocks, which is
 * what lets the interface keep drawing and the audio keep playing while one is open.
 */
#include "dialog.h"

#include <atomic>
#include <cstring>
#include <new>

struct MddDialog {
	std::atomic<int> state;
	char path[1024];
	char label[64];
	char suffix[16];
	SDL_DialogFileFilter filter;
};

static void mdd_dialog_chose(void *userdata, const char *const *files, int) {
	MddDialog *self = static_cast<MddDialog *>(userdata);
	if (self == nullptr) return;

	if (files == nullptr) {
		self->state.store(MDD_DIALOG_FAILED, std::memory_order_release);
		return;
	}

	if (files[0] == nullptr) {
		self->state.store(MDD_DIALOG_CANCELLED, std::memory_order_release);
		return;
	}

	std::strncpy(self->path, files[0], sizeof(self->path) - 1);
	self->path[sizeof(self->path) - 1] = '\0';

	self->state.store(MDD_DIALOG_CHOSEN, std::memory_order_release);
}

static MddDialog *mdd_dialog_make(const char *label, const char *suffix) {
	MddDialog *self = new (std::nothrow) MddDialog();
	if (self == nullptr) return nullptr;

	self->state.store(MDD_DIALOG_WAITING, std::memory_order_relaxed);
	self->path[0] = '\0';

	std::strncpy(self->label, label == nullptr ? "" : label, sizeof(self->label) - 1);
	self->label[sizeof(self->label) - 1] = '\0';

	std::strncpy(self->suffix, suffix == nullptr ? "*" : suffix, sizeof(self->suffix) - 1);
	self->suffix[sizeof(self->suffix) - 1] = '\0';

	self->filter.name = self->label;
	self->filter.pattern = self->suffix;

	return self;
}

extern "C" MddDialog *mdd_dialog_open(SDL_Window *window, const char *label, const char *suffix,
		const char *where) {
	MddDialog *self = mdd_dialog_make(label, suffix);
	if (self == nullptr) return nullptr;

	SDL_ShowOpenFileDialog(mdd_dialog_chose, self, window, &self->filter, 1, where, false);
	return self;
}

extern "C" MddDialog *mdd_dialog_save(SDL_Window *window, const char *label, const char *suffix,
		const char *where) {
	MddDialog *self = mdd_dialog_make(label, suffix);
	if (self == nullptr) return nullptr;

	SDL_ShowSaveFileDialog(mdd_dialog_chose, self, window, &self->filter, 1, where);
	return self;
}

extern "C" MddDialog *mdd_dialog_folder(SDL_Window *window, const char *where) {
	MddDialog *self = mdd_dialog_make("", "*");
	if (self == nullptr) return nullptr;

	SDL_ShowOpenFolderDialog(mdd_dialog_chose, self, window, where, false);
	return self;
}

extern "C" int mdd_dialog_state(MddDialog *dialog) {
	return dialog == nullptr ? MDD_DIALOG_FAILED : dialog->state.load(std::memory_order_acquire);
}

extern "C" const char *mdd_dialog_path(MddDialog *dialog) {
	return dialog == nullptr ? "" : dialog->path;
}

extern "C" void mdd_dialog_close(MddDialog *dialog) {
	delete dialog;
}
