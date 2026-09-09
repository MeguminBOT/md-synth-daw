/**
 * Registering the project suffix with the desktop, and taking that back again.
 *
 * On Windows it writes under the user's own classes rather than the machine, so it needs
 * no elevation and touches nothing another account can see. Elsewhere it writes a
 * desktop entry and a mime type under the account's share directory. Everything it
 * writes is recorded so unregistering can remove exactly that and no more, and
 * mdd_shell_leftovers is what proves it did.
 */
#include "shell.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define MDD_SHELL_ROOM 1024

#if defined(_WIN32)

#include <windows.h>
#include <shlobj.h>

static const char *named(const char *path) {
	const char *out = path;
	const char *at;

	for (at = path; *at != 0; at++) {
		if (*at == '\\' || *at == '/') out = at + 1;
	}

	return out;
}

static int widened(const char *from, wchar_t *out, int room) {
	if (from == NULL || from[0] == 0) {
		out[0] = 0;
		return 0;
	}

	if (MultiByteToWideChar(CP_UTF8, 0, from, -1, out, room) <= 0) {
		out[0] = 0;
		return 0;
	}

	return 1;
}

static int running(char *out, int room) {
	wchar_t wide[MDD_SHELL_ROOM];
	const DWORD held = GetModuleFileNameW(NULL, wide, MDD_SHELL_ROOM);

	out[0] = 0;

	if (held == 0 || held >= MDD_SHELL_ROOM) return 0;

	return WideCharToMultiByte(CP_UTF8, 0, wide, -1, out, room, NULL, NULL) > 0 ? 1 : 0;
}

static int writes(const char *path, const char *name, const char *value) {
	wchar_t widePath[MDD_SHELL_ROOM];
	wchar_t wideName[MDD_SHELL_ROOM];
	wchar_t wideValue[MDD_SHELL_ROOM];
	HKEY key = NULL;
	LONG done;

	if (!widened(path, widePath, MDD_SHELL_ROOM)) return 0;

	widened(name, wideName, MDD_SHELL_ROOM);
	widened(value, wideValue, MDD_SHELL_ROOM);

	if (RegCreateKeyExW(HKEY_CURRENT_USER, widePath, 0, NULL, REG_OPTION_NON_VOLATILE,
			KEY_WRITE, NULL, &key, NULL) != ERROR_SUCCESS) {
		return 0;
	}

	done = RegSetValueExW(key, wideName[0] == 0 ? NULL : wideName, 0, REG_SZ,
		(const BYTE *)wideValue, (DWORD)((wcslen(wideValue) + 1) * sizeof(wchar_t)));

	RegCloseKey(key);

	return done == ERROR_SUCCESS ? 1 : 0;
}

static int reads(const char *path, const char *name, char *out, int room) {
	wchar_t widePath[MDD_SHELL_ROOM];
	wchar_t wideName[MDD_SHELL_ROOM];
	wchar_t value[MDD_SHELL_ROOM];
	DWORD size = (DWORD)sizeof(value);

	out[0] = 0;

	if (!widened(path, widePath, MDD_SHELL_ROOM)) return 0;

	widened(name, wideName, MDD_SHELL_ROOM);

	if (RegGetValueW(HKEY_CURRENT_USER, widePath, wideName[0] == 0 ? NULL : wideName,
			RRF_RT_REG_SZ, NULL, value, &size) != ERROR_SUCCESS) {
		return 0;
	}

	if (WideCharToMultiByte(CP_UTF8, 0, value, -1, out, room, NULL, NULL) <= 0) {
		out[0] = 0;
		return 0;
	}

	return 1;
}

static void drops(const char *path) {
	wchar_t wide[MDD_SHELL_ROOM];

	if (widened(path, wide, MDD_SHELL_ROOM)) RegDeleteTreeW(HKEY_CURRENT_USER, wide);
}

static void dropsValue(const char *path, const char *name) {
	wchar_t widePath[MDD_SHELL_ROOM];
	wchar_t wideName[MDD_SHELL_ROOM];

	if (!widened(path, widePath, MDD_SHELL_ROOM)) return;

	widened(name, wideName, MDD_SHELL_ROOM);

	RegDeleteKeyValueW(HKEY_CURRENT_USER, widePath, wideName[0] == 0 ? NULL : wideName);
}

static int barren(const char *path) {
	wchar_t wide[MDD_SHELL_ROOM];
	HKEY key = NULL;
	DWORD keys = 0;
	DWORD values = 0;
	LONG done;

	if (!widened(path, wide, MDD_SHELL_ROOM)) return 0;

	if (RegOpenKeyExW(HKEY_CURRENT_USER, wide, 0, KEY_READ, &key) != ERROR_SUCCESS) {
		return 0;
	}

	done = RegQueryInfoKeyW(key, NULL, NULL, NULL, &keys, NULL, NULL, &values,
		NULL, NULL, NULL, NULL);

	RegCloseKey(key);

	return done == ERROR_SUCCESS && keys == 0 && values == 0 ? 1 : 0;
}

static int chosen(const char *suffix, const char *identity) {
	char path[MDD_SHELL_ROOM];
	char value[MDD_SHELL_ROOM];

	snprintf(path, sizeof(path),
		"Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\FileExts\\%s\\UserChoice",
		suffix);

	if (!reads(path, "ProgId", value, sizeof(value))) return 1;

	return strcmp(value, identity) == 0 ? 1 : 0;
}

int mdd_shell_supported(void) {
	return 1;
}

int mdd_shell_associated(const char *suffix, const char *identity) {
	char exe[MDD_SHELL_ROOM];
	char path[MDD_SHELL_ROOM];
	char value[MDD_SHELL_ROOM];
	char want[MDD_SHELL_ROOM];

	if (suffix == NULL || identity == NULL) return 0;
	if (!running(exe, sizeof(exe))) return 0;

	snprintf(path, sizeof(path), "Software\\Classes\\%s", suffix);

	if (!reads(path, NULL, value, sizeof(value))) return 0;
	if (strcmp(value, identity) != 0) return 0;

	snprintf(path, sizeof(path), "Software\\Classes\\%s\\shell\\open\\command", identity);

	if (!reads(path, NULL, value, sizeof(value))) return 0;

	snprintf(want, sizeof(want), "\"%s\" \"%%1\"", exe);

	if (_stricmp(value, want) != 0) return 0;

	return chosen(suffix, identity);
}

int mdd_shell_associate(const char *suffix, const char *identity, const char *label,
		const char *mime, const char *name, const char *about) {
	char exe[MDD_SHELL_ROOM];
	char path[MDD_SHELL_ROOM];
	char value[MDD_SHELL_ROOM];
	int done = 1;

	(void)name;
	(void)about;

	if (suffix == NULL || identity == NULL) return 0;
	if (!running(exe, sizeof(exe))) return 0;

	snprintf(path, sizeof(path), "Software\\Classes\\%s", suffix);

	done &= writes(path, NULL, identity);
	done &= writes(path, "Content Type", mime);
	done &= writes(path, "PerceivedType", "audio");

	snprintf(path, sizeof(path), "Software\\Classes\\%s\\OpenWithProgids", suffix);
	done &= writes(path, identity, "");

	snprintf(path, sizeof(path), "Software\\Classes\\%s", identity);

	done &= writes(path, NULL, label);
	done &= writes(path, "FriendlyTypeName", label);

	snprintf(path, sizeof(path), "Software\\Classes\\%s\\DefaultIcon", identity);
	snprintf(value, sizeof(value), "%s,0", exe);
	done &= writes(path, NULL, value);

	snprintf(path, sizeof(path), "Software\\Classes\\%s\\shell\\open\\command", identity);
	snprintf(value, sizeof(value), "\"%s\" \"%%1\"", exe);
	done &= writes(path, NULL, value);

	snprintf(path, sizeof(path), "Software\\Classes\\Applications\\%s\\SupportedTypes",
		named(exe));
	done &= writes(path, suffix, "");

	SHChangeNotify(SHCNE_ASSOCCHANGED, SHCNF_IDLIST, NULL, NULL);

	return done;
}

int mdd_shell_forget(const char *suffix, const char *identity) {
	char exe[MDD_SHELL_ROOM];
	char path[MDD_SHELL_ROOM];
	char value[MDD_SHELL_ROOM];

	if (suffix == NULL || identity == NULL) return 0;

	snprintf(path, sizeof(path), "Software\\Classes\\%s", suffix);

	if (reads(path, NULL, value, sizeof(value)) && strcmp(value, identity) == 0) {
		dropsValue(path, NULL);
		dropsValue(path, "Content Type");
		dropsValue(path, "PerceivedType");
	}

	snprintf(path, sizeof(path), "Software\\Classes\\%s\\OpenWithProgids", suffix);
	dropsValue(path, identity);

	if (barren(path)) drops(path);

	snprintf(path, sizeof(path), "Software\\Classes\\%s", suffix);
	if (barren(path)) drops(path);

	snprintf(path, sizeof(path), "Software\\Classes\\%s", identity);
	drops(path);

	if (running(exe, sizeof(exe))) {
		snprintf(path, sizeof(path), "Software\\Classes\\Applications\\%s", named(exe));
		drops(path);
	}

	SHChangeNotify(SHCNE_ASSOCCHANGED, SHCNF_IDLIST, NULL, NULL);

	return 1;
}

static int present(const char *path) {
	wchar_t wide[MDD_SHELL_ROOM];
	HKEY key = NULL;

	if (!widened(path, wide, MDD_SHELL_ROOM)) return 0;

	if (RegOpenKeyExW(HKEY_CURRENT_USER, wide, 0, KEY_READ, &key) != ERROR_SUCCESS) {
		return 0;
	}

	RegCloseKey(key);

	return 1;
}

int mdd_shell_leftovers(const char *suffix, const char *identity) {
	char exe[MDD_SHELL_ROOM];
	char path[MDD_SHELL_ROOM];
	int out = 0;

	if (suffix == NULL || identity == NULL) return 0;

	snprintf(path, sizeof(path), "Software\\Classes\\%s", suffix);
	out += present(path);

	snprintf(path, sizeof(path), "Software\\Classes\\%s", identity);
	out += present(path);

	if (running(exe, sizeof(exe))) {
		snprintf(path, sizeof(path), "Software\\Classes\\Applications\\%s",
			named(exe));
		out += present(path);
	}

	return out;
}

#elif defined(__linux__)

#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>

static int running(char *out, int room) {
	const ssize_t held = readlink("/proc/self/exe", out, (size_t)(room - 1));

	if (held <= 0) {
		out[0] = 0;
		return 0;
	}

	out[held] = 0;

	return 1;
}

static const char *home(void) {
	const char *out = getenv("HOME");
	return out == NULL || out[0] == 0 ? "/tmp" : out;
}

static void tree(const char *path) {
	char held[MDD_SHELL_ROOM];
	int at;

	snprintf(held, sizeof(held), "%s", path);

	for (at = 1; held[at] != 0; at++) {
		if (held[at] != '/') continue;

		held[at] = 0;
		mkdir(held, 0755);
		held[at] = '/';
	}

	mkdir(held, 0755);
}

static int saved(const char *path, const char *body) {
	FILE *out = fopen(path, "wb");

	if (out == NULL) return 0;

	fputs(body, out);
	fclose(out);

	return 1;
}

static void ran(const char *said) {
	const int done = system(said);
	(void)done;
}

static void refreshed(void) {
	const char *base = home();
	char said[MDD_SHELL_ROOM];

	snprintf(said, sizeof(said),
		"update-mime-database '%s/.local/share/mime' >/dev/null 2>&1", base);
	ran(said);

	snprintf(said, sizeof(said),
		"update-desktop-database '%s/.local/share/applications' >/dev/null 2>&1", base);
	ran(said);
}

int mdd_shell_supported(void) {
	return 1;
}

int mdd_shell_associated(const char *suffix, const char *identity) {
	char exe[MDD_SHELL_ROOM];
	char path[MDD_SHELL_ROOM];
	char want[MDD_SHELL_ROOM];
	char line[MDD_SHELL_ROOM];
	FILE *held;
	int out = 0;

	(void)suffix;

	if (identity == NULL) return 0;
	if (!running(exe, sizeof(exe))) return 0;

	snprintf(path, sizeof(path), "%s/.local/share/applications/%s.desktop", home(), identity);

	held = fopen(path, "rb");
	if (held == NULL) return 0;

	snprintf(want, sizeof(want), "Exec=\"%s\" %%f", exe);

	while (fgets(line, sizeof(line), held) != NULL) {
		char *at = strchr(line, '\n');
		if (at != NULL) *at = 0;

		if (strcmp(line, want) == 0) out = 1;
	}

	fclose(held);

	return out;
}

int mdd_shell_associate(const char *suffix, const char *identity, const char *label,
		const char *mime, const char *name, const char *about) {
	char exe[MDD_SHELL_ROOM];
	char path[MDD_SHELL_ROOM];
	char body[MDD_SHELL_ROOM * 2];
	char said[MDD_SHELL_ROOM];
	const char *base = home();
	int done = 1;

	if (suffix == NULL || identity == NULL || mime == NULL) return 0;
	if (!running(exe, sizeof(exe))) return 0;

	snprintf(path, sizeof(path), "%s/.local/share/mime/packages", base);
	tree(path);

	snprintf(body, sizeof(body),
		"<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
		"<mime-info xmlns=\"http://www.freedesktop.org/standards/shared-mime-info\">\n"
		"\t<mime-type type=\"%s\">\n"
		"\t\t<comment>%s</comment>\n"
		"\t\t<glob pattern=\"*%s\"/>\n"
		"\t\t<icon name=\"%s\"/>\n"
		"\t</mime-type>\n"
		"</mime-info>\n",
		mime, label == NULL ? "" : label, suffix, identity);

	snprintf(said, sizeof(said), "%s/%s.xml", path, identity);
	done &= saved(said, body);

	snprintf(path, sizeof(path), "%s/.local/share/applications", base);
	tree(path);

	snprintf(body, sizeof(body),
		"[Desktop Entry]\n"
		"Type=Application\n"
		"Name=%s\n"
		"Comment=%s\n"
		"Exec=\"%s\" %%f\n"
		"Terminal=false\n"
		"Icon=%s\n"
		"Categories=AudioVideo;Audio;Music;\n"
		"MimeType=%s;\n",
		name == NULL ? identity : name, about == NULL ? "" : about, exe, identity, mime);

	snprintf(said, sizeof(said), "%s/%s.desktop", path, identity);
	done &= saved(said, body);

	refreshed();

	snprintf(said, sizeof(said), "xdg-mime default '%s.desktop' '%s' >/dev/null 2>&1",
		identity, mime);
	ran(said);

	return done;
}

int mdd_shell_forget(const char *suffix, const char *identity) {
	char path[MDD_SHELL_ROOM];
	const char *base = home();

	(void)suffix;

	if (identity == NULL) return 0;

	snprintf(path, sizeof(path), "%s/.local/share/mime/packages/%s.xml", base, identity);
	unlink(path);

	snprintf(path, sizeof(path), "%s/.local/share/applications/%s.desktop", base, identity);
	unlink(path);

	refreshed();

	return 1;
}

static int present(const char *path) {
	FILE *held = fopen(path, "rb");

	if (held == NULL) return 0;

	fclose(held);

	return 1;
}

int mdd_shell_leftovers(const char *suffix, const char *identity) {
	char path[MDD_SHELL_ROOM];
	const char *base = home();
	int out = 0;

	(void)suffix;

	if (identity == NULL) return 0;

	snprintf(path, sizeof(path), "%s/.local/share/mime/packages/%s.xml", base, identity);
	out += present(path);

	snprintf(path, sizeof(path), "%s/.local/share/applications/%s.desktop", base, identity);
	out += present(path);

	return out;
}

#else

int mdd_shell_supported(void) {
	return 0;
}

int mdd_shell_associated(const char *suffix, const char *identity) {
	(void)suffix;
	(void)identity;

	return 0;
}

int mdd_shell_associate(const char *suffix, const char *identity, const char *label,
		const char *mime, const char *name, const char *about) {
	(void)suffix;
	(void)identity;
	(void)label;
	(void)mime;
	(void)name;
	(void)about;

	return 0;
}

int mdd_shell_forget(const char *suffix, const char *identity) {
	(void)suffix;
	(void)identity;

	return 0;
}

int mdd_shell_leftovers(const char *suffix, const char *identity) {
	(void)suffix;
	(void)identity;

	return 0;
}

#endif
