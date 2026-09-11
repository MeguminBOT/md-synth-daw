/**
 * The system file dialogs.
 *
 * A dialog is answered on a thread of its own and the result kept in a small structure
 * the caller asks for the state of on a later frame. Nothing here blocks, which is what
 * lets the interface keep drawing and the audio keep playing while one is open.
 *
 * On Windows the dialogs are opened directly through IFileDialog rather than through
 * SDL. SDL asks for that one first and falls back to SHBrowseForFolder when it cannot
 * have it, and the fallback is the folder tree Windows shipped in 2001: no address bar,
 * no typing a path, no places on the side. Which of the two a person got depended on
 * the SDL build rather than on anything this application chose, and choosing is the
 * point.
 *
 * Everywhere else SDL's own dialogs are the system ones already.
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
	char where[1024];
	SDL_DialogFileFilter filter;
};

static MddDialog *mdd_dialog_make(const char *label, const char *suffix, const char *where) {
	MddDialog *self = new (std::nothrow) MddDialog();
	if (self == nullptr) return nullptr;

	self->state.store(MDD_DIALOG_WAITING, std::memory_order_relaxed);
	self->path[0] = '\0';

	std::strncpy(self->label, label == nullptr ? "" : label, sizeof(self->label) - 1);
	self->label[sizeof(self->label) - 1] = '\0';

	std::strncpy(self->suffix, suffix == nullptr ? "*" : suffix, sizeof(self->suffix) - 1);
	self->suffix[sizeof(self->suffix) - 1] = '\0';

	std::strncpy(self->where, where == nullptr ? "" : where, sizeof(self->where) - 1);
	self->where[sizeof(self->where) - 1] = '\0';

	self->filter.name = self->label;
	self->filter.pattern = self->suffix;

	return self;
}

#if defined(_WIN32)

#include <windows.h>
#include <shobjidl.h>
#include <thread>

/**
 * What a dialog is being asked for.
 */
#define MDD_DIALOG_READ 0
#define MDD_DIALOG_WRITE 1
#define MDD_DIALOG_FOLDER 2

static int mdd_dialog_widen(const char *from, wchar_t *out, int room) {
	out[0] = 0;
	if (from == nullptr || from[0] == '\0') return 0;

	return MultiByteToWideChar(CP_UTF8, 0, from, -1, out, room);
}

static void mdd_dialog_narrow(const wchar_t *from, char *out, int room) {
	out[0] = '\0';
	if (from == nullptr) return;

	WideCharToMultiByte(CP_UTF8, 0, from, -1, out, room, nullptr, nullptr);
	out[room - 1] = '\0';
}

/**
 * Turns the suffix list a caller gives into the one a filter takes.
 *
 * A caller writes "vgm" or "vgm;vgz", which is what SDL's filters take. IFileDialog
 * wants each one starred and dotted, so "vgm;vgz" becomes "*.vgm;*.vgz".
 */
static void mdd_dialog_starred(const char *from, wchar_t *out, int room) {
	int at = 0;

	out[0] = 0;
	if (from == nullptr || from[0] == '\0') return;

	const char *walk = from;

	while (*walk != '\0' && at < room - 6) {
		if (at > 0) out[at++] = L';';

		out[at++] = L'*';
		out[at++] = L'.';

		while (*walk != '\0' && *walk != ';' && at < room - 2) {
			out[at++] = (wchar_t) *walk;
			walk++;
		}

		while (*walk == ';') walk++;
	}

	out[at] = 0;
}

/**
 * The first suffix on its own, which is what a save dialog appends where a name was
 * typed without one.
 */
static void mdd_dialog_first(const char *from, wchar_t *out, int room) {
	int at = 0;

	out[0] = 0;
	if (from == nullptr) return;

	while (from[at] != '\0' && from[at] != ';' && at < room - 1) {
		out[at] = (wchar_t) from[at];
		at++;
	}

	out[at] = 0;
}

static HWND mdd_dialog_owner(SDL_Window *window) {
	if (window == nullptr) return nullptr;

	SDL_PropertiesID held = SDL_GetWindowProperties(window);
	return (HWND) SDL_GetPointerProperty(held, SDL_PROP_WINDOW_WIN32_HWND_POINTER, nullptr);
}

/**
 * Opens the dialog and waits on it.
 *
 * Modality is per thread, so a dialog shown from this one would leave the window that
 * owns it taking clicks behind it. The owner is disabled for as long as it is up,
 * which is what makes it behave the way a person expects one to.
 *
 * Nothing here touches `self` after the state is stored, because the frame that reads
 * that state is free to free it.
 */
static void mdd_dialog_waits(MddDialog *self, HWND owner, int what) {
	HRESULT started = CoInitializeEx(nullptr,
		COINIT_APARTMENTTHREADED | COINIT_DISABLE_OLE1DDE);

	const bool writing = what == MDD_DIALOG_WRITE;
	IFileDialog *dialog = nullptr;

	HRESULT made = CoCreateInstance(writing ? CLSID_FileSaveDialog : CLSID_FileOpenDialog,
		nullptr, CLSCTX_INPROC_SERVER,
		writing ? IID_IFileSaveDialog : IID_IFileOpenDialog, (void **) &dialog);

	if (FAILED(made) || dialog == nullptr) {
		self->state.store(MDD_DIALOG_FAILED, std::memory_order_release);
		if (SUCCEEDED(started)) CoUninitialize();
		return;
	}

	DWORD options = 0;

	dialog->GetOptions(&options);
	options |= FOS_FORCEFILESYSTEM | FOS_NOCHANGEDIR;

	if (what == MDD_DIALOG_FOLDER) options |= FOS_PICKFOLDERS;
	if (what == MDD_DIALOG_READ) options |= FOS_FILEMUSTEXIST | FOS_PATHMUSTEXIST;
	if (writing) options |= FOS_OVERWRITEPROMPT;

	dialog->SetOptions(options);

	wchar_t wide[1024];

	if (mdd_dialog_widen(self->label, wide, 1024) > 0) dialog->SetTitle(wide);

	wchar_t name[64];
	wchar_t pattern[128];

	if (what != MDD_DIALOG_FOLDER && self->suffix[0] != '\0' && self->suffix[0] != '*') {
		mdd_dialog_widen(self->label, name, 64);
		mdd_dialog_starred(self->suffix, pattern, 128);

		COMDLG_FILTERSPEC filter;

		filter.pszName = name[0] == 0 ? pattern : name;
		filter.pszSpec = pattern;

		dialog->SetFileTypes(1, &filter);

		wchar_t first[16];
		mdd_dialog_first(self->suffix, first, 16);

		if (first[0] != 0) dialog->SetDefaultExtension(first);
	}

	if (mdd_dialog_widen(self->where, wide, 1024) > 0) {
		IShellItem *folder = nullptr;

		if (SUCCEEDED(SHCreateItemFromParsingName(wide, nullptr, IID_IShellItem,
				(void **) &folder)) && folder != nullptr) {
			dialog->SetFolder(folder);
			folder->Release();
		}
	}

	const BOOL was = owner == nullptr ? FALSE : IsWindowEnabled(owner);
	if (was) EnableWindow(owner, FALSE);

	HRESULT shown = dialog->Show(owner);

	if (was) {
		EnableWindow(owner, TRUE);
		SetActiveWindow(owner);
	}

	int ends = MDD_DIALOG_FAILED;

	if (SUCCEEDED(shown)) {
		IShellItem *picked = nullptr;

		if (SUCCEEDED(dialog->GetResult(&picked)) && picked != nullptr) {
			PWSTR held = nullptr;

			if (SUCCEEDED(picked->GetDisplayName(SIGDN_FILESYSPATH, &held)) && held != nullptr) {
				mdd_dialog_narrow(held, self->path, sizeof(self->path));
				CoTaskMemFree(held);

				ends = MDD_DIALOG_CHOSEN;
			}

			picked->Release();
		}
	} else if (shown == HRESULT_FROM_WIN32(ERROR_CANCELLED)) {
		ends = MDD_DIALOG_CANCELLED;
	}

	dialog->Release();

	self->state.store(ends, std::memory_order_release);
	if (SUCCEEDED(started)) CoUninitialize();
}

static MddDialog *mdd_dialog_starts(SDL_Window *window, const char *label, const char *suffix,
		const char *where, int what) {
	MddDialog *self = mdd_dialog_make(label, suffix, where);
	if (self == nullptr) return nullptr;

	HWND owner = mdd_dialog_owner(window);

	std::thread(mdd_dialog_waits, self, owner, what).detach();
	return self;
}

extern "C" MddDialog *mdd_dialog_open(SDL_Window *window, const char *label, const char *suffix,
		const char *where) {
	return mdd_dialog_starts(window, label, suffix, where, MDD_DIALOG_READ);
}

extern "C" MddDialog *mdd_dialog_save(SDL_Window *window, const char *label, const char *suffix,
		const char *where) {
	return mdd_dialog_starts(window, label, suffix, where, MDD_DIALOG_WRITE);
}

extern "C" MddDialog *mdd_dialog_folder(SDL_Window *window, const char *where) {
	return mdd_dialog_starts(window, "", "*", where, MDD_DIALOG_FOLDER);
}

#else

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

extern "C" MddDialog *mdd_dialog_open(SDL_Window *window, const char *label, const char *suffix,
		const char *where) {
	MddDialog *self = mdd_dialog_make(label, suffix, where);
	if (self == nullptr) return nullptr;

	SDL_ShowOpenFileDialog(mdd_dialog_chose, self, window, &self->filter, 1, where, false);
	return self;
}

extern "C" MddDialog *mdd_dialog_save(SDL_Window *window, const char *label, const char *suffix,
		const char *where) {
	MddDialog *self = mdd_dialog_make(label, suffix, where);
	if (self == nullptr) return nullptr;

	SDL_ShowSaveFileDialog(mdd_dialog_chose, self, window, &self->filter, 1, where);
	return self;
}

extern "C" MddDialog *mdd_dialog_folder(SDL_Window *window, const char *where) {
	MddDialog *self = mdd_dialog_make("", "*", where);
	if (self == nullptr) return nullptr;

	SDL_ShowOpenFolderDialog(mdd_dialog_chose, self, window, where, false);
	return self;
}

#endif

extern "C" int mdd_dialog_state(MddDialog *dialog) {
	return dialog == nullptr ? MDD_DIALOG_FAILED : dialog->state.load(std::memory_order_acquire);
}

extern "C" const char *mdd_dialog_path(MddDialog *dialog) {
	return dialog == nullptr ? "" : dialog->path;
}

extern "C" void mdd_dialog_close(MddDialog *dialog) {
	delete dialog;
}
