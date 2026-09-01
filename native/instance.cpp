#include "instance.h"

#include <stdio.h>
#include <string.h>

#if defined(_WIN32)

#include <windows.h>

static HANDLE mdd_instance_local = NULL;
static HANDLE mdd_instance_global = NULL;
static int mdd_instance_first = 0;

int mdd_instance_claim(const char *name) {
	char held[256];

	if (mdd_instance_local != NULL) return mdd_instance_first;
	if (name == NULL || name[0] == 0) return 1;

	mdd_instance_local = CreateMutexA(NULL, FALSE, name);
	mdd_instance_first = GetLastError() == ERROR_ALREADY_EXISTS ? 0 : 1;

	snprintf(held, sizeof(held), "Global\\%s", name);
	mdd_instance_global = CreateMutexA(NULL, FALSE, held);

	if (mdd_instance_global != NULL && GetLastError() == ERROR_ALREADY_EXISTS)
		mdd_instance_first = 0;

	return mdd_instance_first;
}

int mdd_instance_held(void) {
	return mdd_instance_local != NULL ? mdd_instance_first : 0;
}

void mdd_instance_release(void) {
	if (mdd_instance_global != NULL) {
		CloseHandle(mdd_instance_global);
		mdd_instance_global = NULL;
	}

	if (mdd_instance_local != NULL) {
		CloseHandle(mdd_instance_local);
		mdd_instance_local = NULL;
	}

	mdd_instance_first = 0;
}

#else

#include <fcntl.h>
#include <stdlib.h>
#include <sys/file.h>
#include <sys/stat.h>
#include <unistd.h>

static int mdd_instance_lock = -1;
static int mdd_instance_first = 0;
static char mdd_instance_path[512];

static void mdd_instance_where(const char *name, char *into, size_t room) {
	const char *base = getenv("XDG_RUNTIME_DIR");

	if (base == NULL || base[0] == 0) base = "/tmp";
	snprintf(into, room, "%s/%s.lock", base, name);
}

int mdd_instance_claim(const char *name) {
	if (mdd_instance_lock >= 0) return mdd_instance_first;
	if (name == NULL || name[0] == 0) return 1;

	mdd_instance_where(name, mdd_instance_path, sizeof(mdd_instance_path));
	mdd_instance_lock = open(mdd_instance_path, O_CREAT | O_RDWR, 0644);

	if (mdd_instance_lock < 0) return 1;

	mdd_instance_first = flock(mdd_instance_lock, LOCK_EX | LOCK_NB) == 0 ? 1 : 0;
	return mdd_instance_first;
}

int mdd_instance_held(void) {
	return mdd_instance_lock >= 0 ? mdd_instance_first : 0;
}

void mdd_instance_release(void) {
	if (mdd_instance_lock < 0) return;

	if (mdd_instance_first) {
		flock(mdd_instance_lock, LOCK_UN);
		unlink(mdd_instance_path);
	}

	close(mdd_instance_lock);
	mdd_instance_lock = -1;
	mdd_instance_first = 0;
}

#endif
