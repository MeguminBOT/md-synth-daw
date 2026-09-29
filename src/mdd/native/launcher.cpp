#include "launcher.h"

#if defined(_WIN32)

#include <windows.h>
#include <stdlib.h>

int mdd_launcher_detached(const char *command) {
	if (command == NULL || command[0] == 0) return 0;

	const int room = MultiByteToWideChar(CP_UTF8, 0, command, -1, NULL, 0);
	if (room <= 0) return 0;

	wchar_t *line = (wchar_t *)malloc(sizeof(wchar_t) * (size_t)room);
	if (line == NULL) return 0;

	if (MultiByteToWideChar(CP_UTF8, 0, command, -1, line, room) <= 0) {
		free(line);
		return 0;
	}

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

#else

int mdd_launcher_detached(const char *command) {
	(void)command;
	return 0;
}

#endif
