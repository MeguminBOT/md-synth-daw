#include "installer.h"

#if defined(_WIN32)

#include <windows.h>
#include <wchar.h>

#define MDD_INSTALLER_ROOM 1024

/**
 * @param path A folder, rewritten in place with backslashes and no separator at the end, which is
 *     how two spellings of one folder come to compare equal.
 */
static void normalised(wchar_t *path) {
	size_t length = wcslen(path);

	for (size_t i = 0; i < length; i++) {
		if (path[i] == L'/') path[i] = L'\\';
	}

	while (length > 3 && path[length - 1] == L'\\') path[--length] = 0;
}

int mdd_installer_everyone(const char *identity, const char *where) {
	wchar_t id[128];
	wchar_t key[MDD_INSTALLER_ROOM];
	wchar_t folder[MDD_INSTALLER_ROOM];
	wchar_t running[MDD_INSTALLER_ROOM];
	DWORD size = (DWORD)sizeof(folder);

	if (identity == NULL || where == NULL) return 0;
	if (MultiByteToWideChar(CP_UTF8, 0, identity, -1, id, 128) <= 0) return 0;
	if (MultiByteToWideChar(CP_UTF8, 0, where, -1, running, MDD_INSTALLER_ROOM) <= 0) return 0;

	swprintf(key, MDD_INSTALLER_ROOM, L"Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\{%ls}_is1",
		id);

	if (RegGetValueW(HKEY_LOCAL_MACHINE, key, L"Inno Setup: App Path", RRF_RT_REG_SZ, NULL, folder,
			&size) != ERROR_SUCCESS) {
		return 0;
	}

	normalised(folder);
	normalised(running);

	return CompareStringOrdinal(folder, -1, running, -1, TRUE) == CSTR_EQUAL;
}

#else

int mdd_installer_everyone(const char *identity, const char *where) {
	(void)identity;
	(void)where;
	return 0;
}

#endif
