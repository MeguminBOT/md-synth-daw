#include "console.h"

#if defined(_WIN32)

#include <windows.h>
#include <stdio.h>

/**
 * @param which Which standard handle.
 * @return Nonzero where it already goes to a file or a pipe, as when the program was started
 *     with its output redirected, which a console must not take over.
 */
static int redirected(DWORD which) {
	const HANDLE held = GetStdHandle(which);
	if (held == NULL || held == INVALID_HANDLE_VALUE) return 0;

	const DWORD kind = GetFileType(held);
	return kind == FILE_TYPE_DISK || kind == FILE_TYPE_PIPE;
}

int mdd_console_attach(int open) {
	if (GetConsoleWindow() != NULL) return 1;

	const int input = redirected(STD_INPUT_HANDLE);
	const int output = redirected(STD_OUTPUT_HANDLE);
	const int error = redirected(STD_ERROR_HANDLE);

	int attached = AttachConsole(ATTACH_PARENT_PROCESS) ? 1 : 0;
	if (!attached && open) attached = AllocConsole() ? 1 : 0;
	if (!attached) return 0;

	if (!input) freopen("CONIN$", "r", stdin);
	if (!output) freopen("CONOUT$", "w", stdout);
	if (!error) freopen("CONOUT$", "w", stderr);

	SetConsoleCtrlHandler(NULL, TRUE);
	return 1;
}

#else

int mdd_console_attach(int open) {
	(void)open;
	return 0;
}

#endif
