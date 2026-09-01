#include "crash.h"

#include <stdio.h>
#include <string.h>
#include <time.h>

static char mdd_crash_path[1024] = {0};

static void mdd_crash_write(const char *kind, unsigned long long code,
	unsigned long long at) {
	if (mdd_crash_path[0] == 0) return;

	FILE *into = fopen(mdd_crash_path, "w");
	if (into == NULL) return;

	time_t when = time(NULL);

	fprintf(into, "%s", ctime(&when));
	fprintf(into, "%s\n", kind);
	fprintf(into, "code 0x%llX\n", code);
	fprintf(into, "at   0x%llX\n", at);

	fclose(into);
}

#if defined(_WIN32)

#include <windows.h>

static LONG WINAPI mdd_crash_caught(EXCEPTION_POINTERS *held) {
	unsigned long long at = 0;
	unsigned long long code = 0;

	if (held != NULL && held->ExceptionRecord != NULL) {
		code = (unsigned long long) held->ExceptionRecord->ExceptionCode;
		at = (unsigned long long) (size_t) held->ExceptionRecord->ExceptionAddress;
	}

	mdd_crash_write("the process stopped on a hardware fault", code, at);
	return EXCEPTION_CONTINUE_SEARCH;
}

extern "C" void mdd_crash_watch(const char *path) {
	if (path == NULL) return;

	strncpy(mdd_crash_path, path, sizeof(mdd_crash_path) - 1);
	mdd_crash_path[sizeof(mdd_crash_path) - 1] = 0;

	SetUnhandledExceptionFilter(mdd_crash_caught);
}

#else

#include <signal.h>
#include <stdlib.h>

static void mdd_crash_signalled(int number) {
	mdd_crash_write("the process stopped on a signal", (unsigned long long) number, 0);
	signal(number, SIG_DFL);
	raise(number);
}

extern "C" void mdd_crash_watch(const char *path) {
	if (path == NULL) return;

	strncpy(mdd_crash_path, path, sizeof(mdd_crash_path) - 1);
	mdd_crash_path[sizeof(mdd_crash_path) - 1] = 0;

	signal(SIGSEGV, mdd_crash_signalled);
	signal(SIGABRT, mdd_crash_signalled);
	signal(SIGILL, mdd_crash_signalled);
	signal(SIGFPE, mdd_crash_signalled);
}

#endif
