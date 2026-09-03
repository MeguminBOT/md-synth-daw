#include "crash.h"

#include <stdio.h>
#include <string.h>
#include <time.h>

#define MDD_CRASH_THREADS 8
#define MDD_CRASH_DEPTH 48
#define MDD_CRASH_ROW 4096
#define MDD_CRASH_NAME 64

static char mdd_crash_path[1024];
static char mdd_crash_label[128];
static int mdd_crash_announce;

static char mdd_crash_thread_name[MDD_CRASH_THREADS][MDD_CRASH_NAME];
static unsigned long mdd_crash_thread_owner[MDD_CRASH_THREADS];
static int mdd_crash_thread_count;

static char mdd_crash_top[512];

static void mdd_crash_copy(char *into, int room, const char *from) {
	if (into == NULL || room <= 0) return;

	into[0] = 0;
	if (from == NULL) return;

	strncpy(into, from, (size_t) room - 1);
	into[room - 1] = 0;
}

static const char *mdd_crash_tail(const char *path) {
	const char *found = path;

	for (const char *at = path; *at != 0; at++) {
		if (*at == '/' || *at == '\\') found = at + 1;
	}

	return found;
}

static const char *mdd_crash_owner(unsigned long id) {
	for (int index = 0; index < mdd_crash_thread_count; index++) {
		if (mdd_crash_thread_owner[index] == id) return mdd_crash_thread_name[index];
	}

	return "a thread it has no name for";
}

static void mdd_crash_remember(unsigned long id, const char *name) {
	for (int index = 0; index < mdd_crash_thread_count; index++) {
		if (mdd_crash_thread_owner[index] != id) continue;

		mdd_crash_copy(mdd_crash_thread_name[index], MDD_CRASH_NAME, name);
		return;
	}

	if (mdd_crash_thread_count >= MDD_CRASH_THREADS) return;

	const int at = mdd_crash_thread_count;

	mdd_crash_thread_owner[at] = id;
	mdd_crash_copy(mdd_crash_thread_name[at], MDD_CRASH_NAME, name);
	mdd_crash_thread_count = at + 1;
}

static int mdd_crash_haxe(const char *source, unsigned long line, char *file, int room,
	unsigned long *found) {
	if (source == NULL || file == NULL || room <= 0) return 0;

	FILE *from = fopen(source, "r");
	if (from == NULL) return 0;

	static char row[MDD_CRASH_ROW];

	unsigned long at = 0;
	unsigned long best = 0;
	int named = 0;

	file[0] = 0;

	while (fgets(row, sizeof(row), from) != NULL) {
		at++;
		if (at > line) break;

		if (named == 0) {
			const char *tail = strstr(row, ".hx\"");

			if (tail != NULL) {
				const char *head = tail;
				while (head > row && *head != '"') head--;

				if (*head == '"') {
					head++;

					int many = 0;

					while (head < tail + 3 && many < room - 1) {
						if (head[0] == '\\' && head[1] == '\\') head++;
						file[many++] = *head++;
					}

					if (many > 0) {
						file[many] = 0;
						named = 1;
					}
				}
			}
		}

		const char *mark = strstr(row, "HXLINE(");
		if (mark == NULL) mark = strstr(row, "HXDLIN(");
		if (mark == NULL) continue;

		mark += 7;
		while (*mark == ' ') mark++;

		unsigned long value = 0;
		int digits = 0;

		while (*mark >= '0' && *mark <= '9') {
			value = value * 10 + (unsigned long) (*mark - '0');
			mark++;
			digits++;
		}

		if (digits > 0) best = value;
	}

	fclose(from);

	*found = best;
	return named != 0 && best > 0;
}

#if defined(_WIN32)

#include <windows.h>
#include <dbghelp.h>

static const char *mdd_crash_cause(unsigned long code, const ULONG_PTR *held) {
	switch (code) {
		case EXCEPTION_ACCESS_VIOLATION:
			if (held == NULL) return "it reached an address that is not mapped";
			if (held[0] == 1) return "it wrote to an address that is not mapped";
			if (held[0] == 8) return "it jumped into memory that cannot be run";
			return "it read an address that is not mapped";

		case EXCEPTION_STACK_OVERFLOW: return "it ran out of stack";
		case EXCEPTION_INT_DIVIDE_BY_ZERO: return "it divided a whole number by zero";
		case EXCEPTION_FLT_DIVIDE_BY_ZERO: return "it divided a decimal by zero";
		case EXCEPTION_ILLEGAL_INSTRUCTION: return "it ran an instruction the processor refused";
		case EXCEPTION_PRIV_INSTRUCTION: return "it ran an instruction it is not allowed to";
		case EXCEPTION_ARRAY_BOUNDS_EXCEEDED: return "it indexed past the end of an array";
		case EXCEPTION_DATATYPE_MISALIGNMENT: return "it read a value from an unaligned address";
		case EXCEPTION_IN_PAGE_ERROR: return "a page it needed could not be read";
		case EXCEPTION_NONCONTINUABLE_EXCEPTION: return "it carried on from a fault it could not";
		case EXCEPTION_INT_OVERFLOW: return "whole number arithmetic overflowed";
		case EXCEPTION_FLT_STACK_CHECK: return "the floating point stack went wrong";
		case 0xE06D7363: return "a C++ exception reached the top with nothing to catch it";
		default: break;
	}

	return "it stopped on a fault";
}

static void mdd_crash_module(HANDLE process, DWORD64 address, char *into, int room) {
	IMAGEHLP_MODULE64 held;

	memset(&held, 0, sizeof(held));
	held.SizeOfStruct = sizeof(held);

	if (SymGetModuleInfo64(process, address, &held)) {
		mdd_crash_copy(into, room, held.ModuleName);
		return;
	}

	mdd_crash_copy(into, room, "an unknown module");
}

static void mdd_crash_place(FILE *into, const char *name, unsigned long long away,
	const char *source, unsigned long row, const char *module) {
	fprintf(into, "  %s + 0x%llX\n", name, away);

	if (source == NULL) {
		fprintf(into, "    in %s\n", module);
		return;
	}

	char file[512];
	unsigned long line = 0;

	if (!mdd_crash_haxe(source, row, file, sizeof(file), &line)) {
		fprintf(into, "    %s:%lu\n", mdd_crash_tail(source), row);
		return;
	}

	fprintf(into, "    %s:%lu   (%s:%lu)\n", file, line, mdd_crash_tail(source), row);

	if (mdd_crash_top[0] != 0) return;

	_snprintf_s(mdd_crash_top, sizeof(mdd_crash_top), _TRUNCATE, "%s, %s:%lu",
		name, file, line);
}

static void mdd_crash_inlined(FILE *into, HANDLE process, DWORD64 address,
	const char *module) {
	const DWORD many = SymAddrIncludeInlineTrace(process, address);
	if (many == 0) return;

	DWORD context = 0;
	DWORD index = 0;

	if (!SymQueryInlineTrace(process, address, 0, address, address, &context, &index)) return;

	for (DWORD step = 0; step < many; step++, context++) {
		char room[sizeof(SYMBOL_INFO) + 512];
		SYMBOL_INFO *found = (SYMBOL_INFO *) room;

		memset(room, 0, sizeof(room));
		found->SizeOfStruct = sizeof(SYMBOL_INFO);
		found->MaxNameLen = 500;

		DWORD64 away = 0;

		if (!SymFromInlineContext(process, address, context, &away, found)) continue;

		IMAGEHLP_LINE64 where;
		DWORD column = 0;

		memset(&where, 0, sizeof(where));
		where.SizeOfStruct = sizeof(where);

		const BOOL placed = SymGetLineFromInlineContext(process, address, context, 0,
			&column, &where);

		mdd_crash_place(into, found->Name, (unsigned long long) away,
			placed ? where.FileName : NULL, placed ? where.LineNumber : 0, module);
	}
}

static void mdd_crash_frame(FILE *into, HANDLE process, DWORD64 address) {
	char room[sizeof(SYMBOL_INFO) + 512];
	SYMBOL_INFO *found = (SYMBOL_INFO *) room;

	memset(room, 0, sizeof(room));
	found->SizeOfStruct = sizeof(SYMBOL_INFO);
	found->MaxNameLen = 500;

	char module[128];
	mdd_crash_module(process, address, module, sizeof(module));

	DWORD64 away = 0;

	if (!SymFromAddr(process, address, &away, found)) {
		fprintf(into, "  0x%llX in %s\n", (unsigned long long) address, module);
		return;
	}

	mdd_crash_inlined(into, process, address, module);

	IMAGEHLP_LINE64 where;
	DWORD column = 0;

	memset(&where, 0, sizeof(where));
	where.SizeOfStruct = sizeof(where);

	const BOOL placed = SymGetLineFromAddr64(process, address, &column, &where);

	mdd_crash_place(into, found->Name, (unsigned long long) away,
		placed ? where.FileName : NULL, placed ? where.LineNumber : 0, module);
}

static void mdd_crash_walked(FILE *into, EXCEPTION_POINTERS *held) {
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

	fprintf(into, "where it stopped\n");

	for (int depth = 0; depth < MDD_CRASH_DEPTH; depth++) {
		if (!StackWalk64(IMAGE_FILE_MACHINE_AMD64, process, GetCurrentThread(), &walk,
			&frame, NULL, SymFunctionTableAccess64, SymGetModuleBase64, NULL)) break;

		if (walk.AddrPC.Offset == 0) break;

		mdd_crash_frame(into, process, walk.AddrPC.Offset);
	}

	SymCleanup(process);
}

static void mdd_crash_told(const char *cause) {
	if (mdd_crash_announce == 0) return;

	char said[2048];

	if (mdd_crash_top[0] != 0) {
		_snprintf_s(said, sizeof(said), _TRUNCATE,
			"%s stopped.\n\n%s, on %s,\nin %s.\n\nThe whole report is in\n%s",
			mdd_crash_label, cause, mdd_crash_owner(GetCurrentThreadId()),
			mdd_crash_top, mdd_crash_path);
	} else {
		_snprintf_s(said, sizeof(said), _TRUNCATE,
			"%s stopped.\n\n%s, on %s.\n\nThe whole report is in\n%s",
			mdd_crash_label, cause, mdd_crash_owner(GetCurrentThreadId()),
			mdd_crash_path);
	}

	MessageBoxA(NULL, said, mdd_crash_label,
		MB_OK | MB_ICONERROR | MB_TOPMOST | MB_SETFOREGROUND);
}

static LONG WINAPI mdd_crash_caught(EXCEPTION_POINTERS *held) {
	if (mdd_crash_path[0] == 0 || held == NULL || held->ExceptionRecord == NULL) {
		return EXCEPTION_CONTINUE_SEARCH;
	}

	const unsigned long code = (unsigned long) held->ExceptionRecord->ExceptionCode;
	const ULONG_PTR *what = held->ExceptionRecord->ExceptionInformation;
	const char *cause = mdd_crash_cause(code, what);

	FILE *into = fopen(mdd_crash_path, "w");

	if (into != NULL) {
		time_t when = time(NULL);

		fprintf(into, "%s stopped on %s", mdd_crash_label, ctime(&when));
		fprintf(into, "\nwhat happened\n");
		fprintf(into, "  %s\n", cause);
		fprintf(into, "  on %s\n", mdd_crash_owner(GetCurrentThreadId()));
		fprintf(into, "  fault 0x%08lX at 0x%llX\n", code,
			(unsigned long long) (size_t) held->ExceptionRecord->ExceptionAddress);

		if (code == EXCEPTION_ACCESS_VIOLATION || code == EXCEPTION_IN_PAGE_ERROR) {
			fprintf(into, "  the address it wanted was 0x%llX\n",
				(unsigned long long) what[1]);
		}

		fprintf(into, "\n");
		mdd_crash_walked(into, held);
		fclose(into);
	}

	mdd_crash_told(cause);

	if (IsDebuggerPresent()) return EXCEPTION_CONTINUE_SEARCH;
	return EXCEPTION_EXECUTE_HANDLER;
}

static void mdd_crash_room(void) {
	ULONG room = 65536;
	SetThreadStackGuarantee(&room);
}

extern "C" void mdd_crash_watch(const char *path, const char *label, int announce) {
	if (path == NULL) return;

	mdd_crash_copy(mdd_crash_path, sizeof(mdd_crash_path), path);
	mdd_crash_copy(mdd_crash_label, sizeof(mdd_crash_label),
		label == NULL ? "The application" : label);

	mdd_crash_announce = announce;
	mdd_crash_top[0] = 0;

	mdd_crash_remember(GetCurrentThreadId(), "the main thread");
	mdd_crash_room();

	SetUnhandledExceptionFilter(mdd_crash_caught);
	SetErrorMode(SEM_FAILCRITICALERRORS | SEM_NOOPENFILEERRORBOX);
}

extern "C" void mdd_crash_thread(const char *name) {
	mdd_crash_remember(GetCurrentThreadId(), name);
	mdd_crash_room();
}

#else

#include <pthread.h>
#include <signal.h>
#include <stdlib.h>
#include <unistd.h>

#if defined(__linux__) || defined(__APPLE__)
#include <execinfo.h>
#define MDD_CRASH_BACKTRACE 1
#endif

static unsigned long mdd_crash_here(void) {
	return (unsigned long) (size_t) pthread_self();
}

static const char *mdd_crash_cause(int number) {
	switch (number) {
		case SIGSEGV: return "it reached an address that is not mapped";
		case SIGBUS: return "it read a value from an address it could not";
		case SIGILL: return "it ran an instruction the processor refused";
		case SIGFPE: return "an arithmetic fault stopped it";
		case SIGABRT: return "it gave up on a fault it could not carry on from";
		default: break;
	}

	return "it stopped on a signal";
}

static void mdd_crash_signalled(int number, siginfo_t *held, void *) {
	if (mdd_crash_path[0] != 0) {
		FILE *into = fopen(mdd_crash_path, "w");

		if (into != NULL) {
			time_t when = time(NULL);

			fprintf(into, "%s stopped on %s", mdd_crash_label, ctime(&when));
			fprintf(into, "\nwhat happened\n");
			fprintf(into, "  %s\n", mdd_crash_cause(number));
			fprintf(into, "  on %s\n", mdd_crash_owner(mdd_crash_here()));
			fprintf(into, "  signal %d\n", number);

			if (held != NULL) {
				fprintf(into, "  the address it wanted was 0x%llX\n",
					(unsigned long long) (size_t) held->si_addr);
			}

			fprintf(into, "\nwhere it stopped\n");
			fflush(into);

#if defined(MDD_CRASH_BACKTRACE)
			void *frames[MDD_CRASH_DEPTH];
			const int many = backtrace(frames, MDD_CRASH_DEPTH);
			backtrace_symbols_fd(frames, many, fileno(into));
#endif

			fclose(into);
		}
	}

	signal(number, SIG_DFL);
	raise(number);
}

extern "C" void mdd_crash_watch(const char *path, const char *label, int announce) {
	if (path == NULL) return;

	mdd_crash_copy(mdd_crash_path, sizeof(mdd_crash_path), path);
	mdd_crash_copy(mdd_crash_label, sizeof(mdd_crash_label),
		label == NULL ? "The application" : label);

	mdd_crash_announce = announce;
	mdd_crash_top[0] = 0;

	mdd_crash_remember(mdd_crash_here(), "the main thread");

	struct sigaction how;

	memset(&how, 0, sizeof(how));
	how.sa_sigaction = mdd_crash_signalled;
	how.sa_flags = SA_SIGINFO | SA_ONSTACK;
	sigemptyset(&how.sa_mask);

	sigaction(SIGSEGV, &how, NULL);
	sigaction(SIGBUS, &how, NULL);
	sigaction(SIGILL, &how, NULL);
	sigaction(SIGFPE, &how, NULL);
	sigaction(SIGABRT, &how, NULL);
}

extern "C" void mdd_crash_thread(const char *name) {
	mdd_crash_remember(mdd_crash_here(), name);
}

#endif
