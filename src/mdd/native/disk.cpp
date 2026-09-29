#include "disk.h"

#include <stdio.h>
#include <stdlib.h>

#if defined(_WIN32)

#include <windows.h>

/**
 * @param text UTF-8 text.
 * @return The same text in UTF-16, which the caller frees, or NULL where it would not convert.
 */
static wchar_t *mdd_disk_widened(const char *text) {
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

int mdd_disk_replace(const char *from, const char *onto) {
	if (from == NULL || onto == NULL) return 0;

	wchar_t *source = mdd_disk_widened(from);
	wchar_t *target = mdd_disk_widened(onto);

	const BOOL moved = source != NULL && target != NULL
		&& MoveFileExW(source, target, MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH);

	free(source);
	free(target);

	return moved ? 1 : 0;
}

#else

int mdd_disk_replace(const char *from, const char *onto) {
	if (from == NULL || onto == NULL) return 0;
	return rename(from, onto) == 0 ? 1 : 0;
}

#endif
