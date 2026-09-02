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

#include <dbghelp.h>

static void mdd_crash_named(FILE *into, HANDLE process, DWORD64 address) {
	char room[sizeof(SYMBOL_INFO) + 512];
	SYMBOL_INFO *found = (SYMBOL_INFO *) room;

	memset(room, 0, sizeof(room));
	found->SizeOfStruct = sizeof(SYMBOL_INFO);
	found->MaxNameLen = 500;

	DWORD64 away = 0;

	if (SymFromAddr(process, address, &away, found)) {
		fprintf(into, "  %s + 0x%llX\n", found->Name, (unsigned long long) away);
		return;
	}

	fprintf(into, "  0x%llX\n", (unsigned long long) address);
}

static void mdd_crash_walked(EXCEPTION_POINTERS *held) {
	if (mdd_crash_path[0] == 0 || held == NULL) return;

	FILE *into = fopen(mdd_crash_path, "a");
	if (into == NULL) return;

	HANDLE process = GetCurrentProcess();

	SymSetOptions(SYMOPT_DEFERRED_LOADS | SYMOPT_UNDNAME | SYMOPT_LOAD_LINES);
	SymInitialize(process, NULL, TRUE);

	CONTEXT frame = *held->ContextRecord;
	STACKFRAME64 walk;

	memset(&walk, 0, sizeof(walk));
	walk.AddrPC.Offset = frame.Rip;
	walk.AddrPC.Mode = AddrModeFlat;
	walk.AddrFrame.Offset = frame.Rbp;
	walk.AddrFrame.Mode = AddrModeFlat;
	walk.AddrStack.Offset = frame.Rsp;
	walk.AddrStack.Mode = AddrModeFlat;

	fprintf(into, "the stack it stopped on\n");

	for (int depth = 0; depth < 40; depth++) {
		if (!StackWalk64(IMAGE_FILE_MACHINE_AMD64, process, GetCurrentThread(), &walk,
			&frame, NULL, SymFunctionTableAccess64, SymGetModuleBase64, NULL)) break;

		if (walk.AddrPC.Offset == 0) break;

		mdd_crash_named(into, process, walk.AddrPC.Offset);
	}

	SymCleanup(process);
	fclose(into);
}

static LONG WINAPI mdd_crash_caught(EXCEPTION_POINTERS *held) {
	unsigned long long at = 0;
	unsigned long long code = 0;

	if (held != NULL && held->ExceptionRecord != NULL) {
		code = (unsigned long long) held->ExceptionRecord->ExceptionCode;
		at = (unsigned long long) (size_t) held->ExceptionRecord->ExceptionAddress;
	}

	mdd_crash_write("the process stopped on a hardware fault", code, at);
	mdd_crash_walked(held);

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
