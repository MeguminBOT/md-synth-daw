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

	snprintf(mdd_crash_top, sizeof(mdd_crash_top), "%s, %s:%lu",
		name, file, line);
}

#if defined(_MSC_VER)
#define MDD_CRASH_INLINE 1
#else
#define MDD_CRASH_INLINE 0
#endif

#if MDD_CRASH_INLINE

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

#else

static void mdd_crash_inlined(FILE *into, HANDLE process, DWORD64 address,
	const char *module) {
	(void) into;
	(void) process;
	(void) address;
	(void) module;
}

#endif

#if !defined(_MSC_VER)
#include <cxxabi.h>
#endif

#define MDD_CRASH_SOURCE 512
#define MDD_CRASH_COFF_ENTRY 18
#define MDD_CRASH_COFF_SECTION 40

struct mdd_crash_coff {
	const unsigned char *sections;
	const unsigned char *symbols;
	const char *strings;
	unsigned long count;
	unsigned int many;

	const unsigned char *lines;
	unsigned long lineBytes;
	unsigned long long preferred;
};

static char mdd_crash_coff_path[1024];
static mdd_crash_coff mdd_crash_coff_held;
static int mdd_crash_coff_ready;

static unsigned short mdd_crash_word(const unsigned char *at) {
	return (unsigned short) (at[0] | (at[1] << 8));
}

static unsigned long mdd_crash_long(const unsigned char *at) {
	return (unsigned long) at[0] | ((unsigned long) at[1] << 8)
		| ((unsigned long) at[2] << 16) | ((unsigned long) at[3] << 24);
}

static unsigned long long mdd_crash_quad(const unsigned char *at) {
	return (unsigned long long) mdd_crash_long(at)
		| ((unsigned long long) mdd_crash_long(at + 4) << 32);
}

static unsigned long long mdd_crash_uleb(const unsigned char **at,
	const unsigned char *end) {
	unsigned long long out = 0;
	unsigned int shift = 0;

	while (*at < end) {
		const unsigned char byte = *(*at)++;

		if (shift < 64) out |= (unsigned long long) (byte & 0x7F) << shift;
		shift += 7;

		if ((byte & 0x80) == 0) break;
	}

	return out;
}

static long long mdd_crash_sleb(const unsigned char **at, const unsigned char *end) {
	long long out = 0;
	unsigned int shift = 0;
	unsigned char byte = 0;

	while (*at < end) {
		byte = *(*at)++;

		if (shift < 64) out |= (long long) (byte & 0x7F) << shift;
		shift += 7;

		if ((byte & 0x80) == 0) break;
	}

	if (shift < 64 && (byte & 0x40) != 0) out |= -((long long) 1 << shift);
	return out;
}

static int mdd_crash_coff_open(mdd_crash_coff *into, const char *path) {
	memset(into, 0, sizeof(*into));

	HANDLE file = CreateFileA(path, GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_WRITE,
		NULL, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, NULL);

	if (file == INVALID_HANDLE_VALUE) return 0;

	HANDLE mapping = CreateFileMappingA(file, NULL, PAGE_READONLY, 0, 0, NULL);
	CloseHandle(file);

	if (mapping == NULL) return 0;

	const unsigned char *image = (const unsigned char *)
		MapViewOfFile(mapping, FILE_MAP_READ, 0, 0, 0);

	CloseHandle(mapping);

	if (image == NULL) return 0;
	if (image[0] != 'M' || image[1] != 'Z') return 0;

	const unsigned char *pe = image + mdd_crash_long(image + 0x3C);
	if (pe[0] != 'P' || pe[1] != 'E' || pe[2] != 0 || pe[3] != 0) return 0;

	const unsigned long table = mdd_crash_long(pe + 12);
	const unsigned long count = mdd_crash_long(pe + 16);

	if (table == 0 || count == 0) return 0;

	into->many = mdd_crash_word(pe + 6);
	into->sections = pe + 24 + mdd_crash_word(pe + 20);
	into->symbols = image + table;
	into->count = count;
	into->strings = (const char *)
		(into->symbols + (size_t) count * MDD_CRASH_COFF_ENTRY);

	const unsigned char *optional = pe + 24;

	into->preferred = mdd_crash_word(optional) == 0x20B
		? mdd_crash_quad(optional + 24)
		: (unsigned long long) mdd_crash_long(optional + 28);

	for (unsigned int index = 0; index < into->many; index++) {
		const unsigned char *one = into->sections
			+ (size_t) index * MDD_CRASH_COFF_SECTION;

		char name[16];

		memcpy(name, one, 8);
		name[8] = 0;

		const char *said = name;

		if (name[0] == '/') {
			const unsigned long at = (unsigned long) atol(name + 1);
			said = into->strings + at;
		}

		if (strcmp(said, ".debug_line") != 0) continue;

		into->lines = image + mdd_crash_long(one + 20);
		into->lineBytes = mdd_crash_long(one + 16);
		break;
	}

	return 1;
}

static int mdd_crash_coff_named(const mdd_crash_coff *held, unsigned long long rva,
	char *into, int room, unsigned long long *away) {
	unsigned long long best = 0;
	const unsigned char *found = NULL;

	for (unsigned long index = 0; index < held->count; index++) {
		const unsigned char *one = held->symbols
			+ (size_t) index * MDD_CRASH_COFF_ENTRY;

		const short section = (short) mdd_crash_word(one + 12);
		const unsigned char storage = one[16];

		index += one[17];

		if (section <= 0 || (unsigned int) section > held->many) continue;
		if (storage != 2 && storage != 3 && storage != 6) continue;

		const unsigned char *where = held->sections
			+ (size_t) (section - 1) * MDD_CRASH_COFF_SECTION;

		const unsigned long long at = (unsigned long long) mdd_crash_long(where + 12)
			+ (unsigned long long) mdd_crash_long(one + 8);

		if (at > rva || at < best) continue;

		best = at;
		found = one;
	}

	if (found == NULL) return 0;

	if (mdd_crash_long(found) == 0) {
		mdd_crash_copy(into, room, held->strings + mdd_crash_long(found + 4));
	} else {
		char name[9];

		memcpy(name, found, 8);
		name[8] = 0;

		mdd_crash_copy(into, room, name);
	}

	*away = rva - best;
	return into[0] != 0;
}

static const char *mdd_crash_dwarf_folder(const unsigned char *folders,
	const unsigned char *end, unsigned long long want) {
	const unsigned char *at = folders;
	unsigned long long index = 1;

	while (at < end && *at != 0) {
		const char *name = (const char *) at;

		while (at < end && *at != 0) at++;
		if (at < end) at++;

		if (index == want) return name;
		index++;
	}

	return NULL;
}

static int mdd_crash_dwarf_file(const unsigned char *folders, const unsigned char *files,
	const unsigned char *end, unsigned long long want, const char *prefix,
	char *into, int room) {
	const unsigned char *at = files;
	unsigned long long index = 1;

	while (at < end && *at != 0) {
		const char *name = (const char *) at;

		while (at < end && *at != 0) at++;
		if (at < end) at++;

		const unsigned long long folder = mdd_crash_uleb(&at, end);

		mdd_crash_uleb(&at, end);
		mdd_crash_uleb(&at, end);

		if (index++ != want) continue;

		const char *where = folder == 0 ? NULL
			: mdd_crash_dwarf_folder(folders, files - 1, folder);

		if (name[0] == '/' || (name[0] != 0 && name[1] == ':')) {
			mdd_crash_copy(into, room, name);
			return 1;
		}

		if (where == NULL) {
			snprintf(into, (size_t) room, "%s/%s", prefix, name);
			return 1;
		}

		if (where[0] == '/' || (where[0] != 0 && where[1] == ':')) {
			snprintf(into, (size_t) room, "%s/%s", where, name);
			return 1;
		}

		snprintf(into, (size_t) room, "%s/%s/%s", prefix, where, name);
		return 1;
	}

	return 0;
}

static int mdd_crash_dwarf(const mdd_crash_coff *held, const unsigned long long *wanted,
	int many, const char *prefix, char *paths, int stride, unsigned long *lines) {
	if (held->lines == NULL || held->lineBytes == 0) return 0;

	const unsigned char *at = held->lines;
	const unsigned char *over = held->lines + held->lineBytes;

	unsigned long long best[MDD_CRASH_DEPTH];
	int found = 0;

	for (int index = 0; index < many; index++) best[index] = 0;

	while (at + 16 < over) {
		const unsigned long length = mdd_crash_long(at);
		const unsigned char *unit = at + 4;
		const unsigned char *tail = unit + length;

		at = tail;

		if (length == 0 || length == 0xFFFFFFFF || tail > over) break;

		const unsigned int version = mdd_crash_word(unit);
		if (version < 2 || version > 4) continue;

		const unsigned long header = mdd_crash_long(unit + 2);
		const unsigned char *after = unit + 6 + header;

		if (after > tail) continue;

		const unsigned char *step = unit + 6;

		const unsigned int minimum = *step++;
		if (version >= 4) step++;

		const unsigned char first = *step++;
		const int lineBase = (signed char) *step++;
		const unsigned int lineRange = *step++;
		const unsigned int opcodeBase = *step++;

		const unsigned char *sizes = step;
		step += opcodeBase == 0 ? 0 : opcodeBase - 1;

		const unsigned char *folders = step;

		while (step < after && *step != 0) {
			while (step < after && *step != 0) step++;
			if (step < after) step++;
		}

		if (step < after) step++;

		const unsigned char *names = step;

		if (lineRange == 0 || opcodeBase == 0 || minimum == 0) continue;

		unsigned long long address = 0;
		unsigned long long file = 1;
		unsigned long line = 1;
		int running = first != 0;

		const unsigned char *pen = after;

		unsigned long long wasAddress = 0;
		unsigned long long wasFile = 1;
		unsigned long wasLine = 1;
		int started = 0;

		while (pen < tail) {
			const unsigned char opcode = *pen++;
			int row = 0;
			int ends = 0;

			if (opcode >= opcodeBase) {
				const unsigned int adjusted = opcode - opcodeBase;

				address += (unsigned long long) (adjusted / lineRange) * minimum;
				line = (unsigned long) ((long) line + lineBase
					+ (long) (adjusted % lineRange));
				row = 1;
			} else if (opcode == 0) {
				const unsigned long long size = mdd_crash_uleb(&pen, tail);
				const unsigned char *next = pen + size;

				if (size == 0 || next > tail) break;

				const unsigned char kind = *pen;

				if (kind == 1) {
					ends = 1;
					row = 1;
				} else if (kind == 2 && size >= 9) {
					address = mdd_crash_quad(pen + 1);
				}

				pen = next;
			} else {
				switch (opcode) {
					case 1: row = 1; break;
					case 2: address += mdd_crash_uleb(&pen, tail) * minimum; break;
					case 3: line = (unsigned long) ((long long) line
						+ mdd_crash_sleb(&pen, tail)); break;
					case 4: file = mdd_crash_uleb(&pen, tail); break;
					case 5: mdd_crash_uleb(&pen, tail); break;
					case 6: break;
					case 7: break;
					case 8: address += (unsigned long long)
						((255 - opcodeBase) / lineRange) * minimum; break;
					case 9: address += mdd_crash_word(pen); pen += 2; break;
					case 10: break;
					case 11: break;
					case 12: mdd_crash_uleb(&pen, tail); break;
					default: {
						const unsigned int skip = opcode - 1 < opcodeBase - 1
							? sizes[opcode - 1] : 0;
						for (unsigned int one = 0; one < skip; one++) {
							mdd_crash_uleb(&pen, tail);
						}
						break;
					}
				}
			}

			if (!row) continue;

			if (started && wasAddress <= address && wasLine > 0) {
				for (int index = 0; index < many; index++) {
					const unsigned long long ask = wanted[index];

					if (ask < wasAddress || ask >= address) continue;
					if (wasAddress < best[index]) continue;

					if (!mdd_crash_dwarf_file(folders, names, after, wasFile, prefix,
						paths + (size_t) index * stride, stride)) continue;

					best[index] = wasAddress;
					lines[index] = wasLine;
					found++;
				}
			}

			wasAddress = address;
			wasFile = file;
			wasLine = line;
			started = 1;

			if (!ends) continue;

			address = 0;
			file = 1;
			line = 1;
			running = first != 0;
			started = 0;
			(void) running;
		}
	}

	return found;
}

static void mdd_crash_lined(const DWORD64 *found, int many, char *sources, int stride,
	unsigned long *rows) {
	if (many <= 0) return;

	HMODULE owner = NULL;

	if (!GetModuleHandleExA(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS
		| GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
		(LPCSTR) (uintptr_t) found[0], &owner)) return;

	char path[1024];
	if (GetModuleFileNameA(owner, path, sizeof(path)) == 0) return;

	if (strcmp(path, mdd_crash_coff_path) != 0) {
		mdd_crash_copy(mdd_crash_coff_path, sizeof(mdd_crash_coff_path), path);
		mdd_crash_coff_ready = mdd_crash_coff_open(&mdd_crash_coff_held, path);
	}

	if (!mdd_crash_coff_ready) return;
	if (mdd_crash_coff_held.lines == NULL) return;

	const DWORD64 base = (DWORD64) (uintptr_t) owner;
	unsigned long long wanted[MDD_CRASH_DEPTH];

	for (int index = 0; index < many; index++) {
		HMODULE holds = NULL;

		const int same = GetModuleHandleExA(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS
			| GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
			(LPCSTR) (uintptr_t) found[index], &holds) && holds == owner;

		wanted[index] = same
			? mdd_crash_coff_held.preferred + (found[index] - base) : 0;
	}

	char prefix[512];

	mdd_crash_copy(prefix, sizeof(prefix), path);

	char *tail = strrchr(prefix, '\\');
	char *slash = strrchr(prefix, '/');

	if (slash != NULL && (tail == NULL || slash > tail)) tail = slash;
	if (tail == NULL) return;

	*tail = 0;

	char *stem = tail + 1;
	char *dot = strrchr(stem, '.');

	if (dot != NULL) *dot = 0;

	char *over = strrchr(prefix, '\\');
	slash = strrchr(prefix, '/');

	if (slash != NULL && (over == NULL || slash > over)) over = slash;
	if (over == NULL) return;

	*over = 0;

	char where[512];
	snprintf(where, sizeof(where), "%s/obj/%s", prefix, stem);

	mdd_crash_dwarf(&mdd_crash_coff_held, wanted, many, where, sources, stride, rows);
}

static void mdd_crash_plainly(char *into, int room) {
#if defined(_MSC_VER)
	(void) into;
	(void) room;
#else
	if (into[0] != '_' || into[1] != 'Z') return;

	int state = 0;
	char *out = abi::__cxa_demangle(into, NULL, NULL, &state);

	if (state == 0 && out != NULL) mdd_crash_copy(into, room, out);
#endif
}

static int mdd_crash_owned(DWORD64 address, char *into, int room,
	unsigned long long *away) {
	HMODULE owner = NULL;

	if (!GetModuleHandleExA(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS
		| GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
		(LPCSTR) (uintptr_t) address, &owner)) return 0;

	char path[1024];
	if (GetModuleFileNameA(owner, path, sizeof(path)) == 0) return 0;

	if (strcmp(path, mdd_crash_coff_path) != 0) {
		mdd_crash_copy(mdd_crash_coff_path, sizeof(mdd_crash_coff_path), path);
		mdd_crash_coff_ready = mdd_crash_coff_open(&mdd_crash_coff_held, path);
	}

	if (!mdd_crash_coff_ready) return 0;

	if (!mdd_crash_coff_named(&mdd_crash_coff_held,
		address - (DWORD64) (uintptr_t) owner, into, room, away)) return 0;

	mdd_crash_plainly(into, room);
	return 1;
}

static void mdd_crash_frame(FILE *into, HANDLE process, DWORD64 address,
	const char *source, unsigned long row) {
	char room[sizeof(SYMBOL_INFO) + 512];
	SYMBOL_INFO *found = (SYMBOL_INFO *) room;

	memset(room, 0, sizeof(room));
	found->SizeOfStruct = sizeof(SYMBOL_INFO);
	found->MaxNameLen = 500;

	char module[128];
	mdd_crash_module(process, address, module, sizeof(module));

	DWORD64 away = 0;

	if (!SymFromAddr(process, address, &away, found)) {
		char named[512];
		unsigned long long past = 0;

		if (mdd_crash_owned(address, named, sizeof(named), &past)) {
			mdd_crash_place(into, named, past, source, row, module);
			return;
		}

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

	DWORD64 found[MDD_CRASH_DEPTH];
	int many = 0;

	while (many < MDD_CRASH_DEPTH) {
		if (!StackWalk64(IMAGE_FILE_MACHINE_AMD64, process, GetCurrentThread(), &walk,
			&frame, NULL, SymFunctionTableAccess64, SymGetModuleBase64, NULL)) break;

		if (walk.AddrPC.Offset == 0) break;

		found[many++] = walk.AddrPC.Offset;
	}

	static char sources[MDD_CRASH_DEPTH][MDD_CRASH_SOURCE];
	unsigned long rows[MDD_CRASH_DEPTH];

	for (int index = 0; index < many; index++) {
		sources[index][0] = 0;
		rows[index] = 0;
	}

	mdd_crash_lined(found, many, sources[0], MDD_CRASH_SOURCE, rows);

	fprintf(into, "where it stopped\n");

	for (int index = 0; index < many; index++) {
		mdd_crash_frame(into, process, found[index],
			rows[index] == 0 ? NULL : sources[index], rows[index]);
	}

	if (mdd_crash_coff_ready) {
		fprintf(into, "\n  the names and lines above come from the symbol table and the DWARF in\n");
		fprintf(into, "  the binary itself, because DbgHelp reads neither. A call that was put\n");
		fprintf(into, "  inline into another is missing from the walk: msvc or clang-cl shows it.\n");
	}

	SymCleanup(process);
}

static void mdd_crash_told(const char *cause) {
	if (mdd_crash_announce == 0) return;

	char said[2048];

	if (mdd_crash_top[0] != 0) {
		snprintf(said, sizeof(said),
			"%s stopped.\n\n%s, on %s,\nin %s.\n\nThe whole report is in\n%s",
			mdd_crash_label, cause, mdd_crash_owner(GetCurrentThreadId()),
			mdd_crash_top, mdd_crash_path);
	} else {
		snprintf(said, sizeof(said),
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
