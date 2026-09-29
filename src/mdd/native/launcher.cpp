#include "launcher.h"

#if defined(_WIN32)

#include <windows.h>
#include <shellapi.h>
#include <objbase.h>
#include <stdlib.h>

/**
 * @param text UTF-8 text.
 * @return The same text in UTF-16, which the caller frees, or NULL where it would not convert.
 */
static wchar_t *widened(const char *text) {
	if (text == NULL) return NULL;

	const int room = MultiByteToWideChar(CP_UTF8, 0, text, -1, NULL, 0);
	if (room <= 0) return NULL;

	wchar_t *out = (wchar_t *)malloc(sizeof(wchar_t) * (size_t)room);
	if (out == NULL) return NULL;

	if (MultiByteToWideChar(CP_UTF8, 0, text, -1, out, room) <= 0) {
		free(out);
		return NULL;
	}

	return out;
}

int mdd_launcher_detached(const char *command) {
	if (command == NULL || command[0] == 0) return 0;

	wchar_t *line = widened(command);
	if (line == NULL) return 0;

	STARTUPINFOW startup;
	PROCESS_INFORMATION process;

	ZeroMemory(&startup, sizeof(startup));
	ZeroMemory(&process, sizeof(process));
	startup.cb = sizeof(startup);

	const BOOL started = CreateProcessW(NULL, line, NULL, NULL, FALSE,
		CREATE_NO_WINDOW | CREATE_NEW_PROCESS_GROUP, NULL, NULL, &startup, &process);

	free(line);

	if (!started) return 0;

	CloseHandle(process.hThread);
	CloseHandle(process.hProcess);

	return 1;
}

int mdd_launcher_elevated(const char *program, const char *parameters) {
	if (program == NULL || program[0] == 0) return -1;

	wchar_t *file = widened(program);
	wchar_t *said = widened(parameters == NULL ? "" : parameters);

	if (file == NULL || said == NULL) {
		free(file);
		free(said);
		return -1;
	}

	HWND owner = GetForegroundWindow();
	DWORD holder = 0;

	if (owner != NULL) GetWindowThreadProcessId(owner, &holder);
	if (holder != GetCurrentProcessId()) owner = NULL;

	SHELLEXECUTEINFOW asked;
	ZeroMemory(&asked, sizeof(asked));
	asked.cbSize = sizeof(asked);
	asked.fMask = SEE_MASK_NOASYNC | SEE_MASK_FLAG_NO_UI;
	asked.hwnd = owner;
	asked.lpVerb = L"runas";
	asked.lpFile = file;
	asked.lpParameters = said;
	asked.nShow = SW_HIDE;

	const HRESULT apartment = CoInitializeEx(NULL, COINIT_APARTMENTTHREADED | COINIT_DISABLE_OLE1DDE);
	const BOOL started = ShellExecuteExW(&asked);
	const DWORD fault = started ? ERROR_SUCCESS : GetLastError();

	if (SUCCEEDED(apartment)) CoUninitialize();

	free(file);
	free(said);

	if (started) return 1;
	return fault == ERROR_CANCELLED ? 0 : -1;
}

int mdd_launcher_process(void) {
	return (int)GetCurrentProcessId();
}

#else

#include <unistd.h>

int mdd_launcher_detached(const char *command) {
	(void)command;
	return 0;
}

int mdd_launcher_elevated(const char *program, const char *parameters) {
	(void)program;
	(void)parameters;
	return -1;
}

int mdd_launcher_process(void) {
	return (int)getpid();
}

#endif
