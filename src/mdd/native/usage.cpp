/**
 * What this process is costing the machine: processor, memory and graphics memory.
 *
 * Processor use is a difference of two readings rather than an instant, so the first
 * call after starting answers nothing useful and the ones after it are a mean over the
 * gap.
 */
#include "usage.h"

#ifdef _WIN32

#include <windows.h>
#include <psapi.h>
#include <pdh.h>
#include <pdhmsg.h>
#include <cstdio>
#include <cstdlib>

static ULONGLONG lastWall = 0;
static ULONGLONG lastBusy = 0;
static double heldCpu = 0;

static PDH_HQUERY gpuQuery = nullptr;
static PDH_HCOUNTER gpuCounter = nullptr;
static bool gpuReady = false;

static ULONGLONG filed(const FILETIME &held) {
	ULARGE_INTEGER out;

	out.LowPart = held.dwLowDateTime;
	out.HighPart = held.dwHighDateTime;

	return out.QuadPart;
}

extern "C" void mdd_usage_start() {
	FILETIME made, done, kernel, user;

	if (GetProcessTimes(GetCurrentProcess(), &made, &done, &kernel, &user)) {
		lastBusy = filed(kernel) + filed(user);
		lastWall = filed(made);

		FILETIME now;
		GetSystemTimeAsFileTime(&now);
		lastWall = filed(now);
	}

	if (PdhOpenQueryW(nullptr, 0, &gpuQuery) != ERROR_SUCCESS) return;

	wchar_t path[128];
	swprintf(path, 128, L"\\GPU Engine(pid_%lu*)\\Utilization Percentage",
		(unsigned long)GetCurrentProcessId());

	if (PdhAddEnglishCounterW(gpuQuery, path, 0, &gpuCounter) != ERROR_SUCCESS) {
		PdhCloseQuery(gpuQuery);
		gpuQuery = nullptr;
		return;
	}

	PdhCollectQueryData(gpuQuery);
	gpuReady = true;
}

extern "C" void mdd_usage_stop() {
	if (gpuQuery == nullptr) return;

	PdhCloseQuery(gpuQuery);

	gpuQuery = nullptr;
	gpuCounter = nullptr;
	gpuReady = false;
}

extern "C" double mdd_usage_cpu() {
	FILETIME made, done, kernel, user, now;

	if (!GetProcessTimes(GetCurrentProcess(), &made, &done, &kernel, &user)) return heldCpu;

	GetSystemTimeAsFileTime(&now);

	const ULONGLONG busy = filed(kernel) + filed(user);
	const ULONGLONG wall = filed(now);

	if (wall > lastWall && busy >= lastBusy) {
		SYSTEM_INFO about;
		GetSystemInfo(&about);

		const double cores = about.dwNumberOfProcessors < 1 ? 1
			: (double)about.dwNumberOfProcessors;

		heldCpu = (double)(busy - lastBusy) / (double)(wall - lastWall) * 100.0 / cores;
		if (heldCpu < 0) heldCpu = 0;
		if (heldCpu > 100) heldCpu = 100;
	}

	lastBusy = busy;
	lastWall = wall;

	return heldCpu;
}

extern "C" double mdd_usage_ram() {
	PROCESS_MEMORY_COUNTERS held;

	if (!GetProcessMemoryInfo(GetCurrentProcess(), &held, sizeof(held))) return 0;
	return (double)held.WorkingSetSize / (1024.0 * 1024.0);
}

extern "C" double mdd_usage_gpu() {
	if (!gpuReady) return -1;

	if (PdhCollectQueryData(gpuQuery) != ERROR_SUCCESS) return -1;

	PDH_FMT_COUNTERVALUE_ITEM_W *items = nullptr;
	DWORD bytes = 0;
	DWORD count = 0;

	PDH_STATUS state = PdhGetFormattedCounterArrayW(gpuCounter, PDH_FMT_DOUBLE, &bytes,
		&count, nullptr);

	if (state != (PDH_STATUS)PDH_MORE_DATA || bytes == 0) return 0;

	items = (PDH_FMT_COUNTERVALUE_ITEM_W *)malloc(bytes);
	if (items == nullptr) return 0;

	double much = 0;

	if (PdhGetFormattedCounterArrayW(gpuCounter, PDH_FMT_DOUBLE, &bytes, &count, items)
			== ERROR_SUCCESS) {
		for (DWORD index = 0; index < count; index++) {
			much += items[index].FmtValue.doubleValue;
		}
	}

	free(items);

	if (much < 0) much = 0;
	if (much > 100) much = 100;

	return much;
}

#else

#include <sys/resource.h>
#include <sys/time.h>
#include <unistd.h>
#include <cstdio>

#ifdef __APPLE__
#include <mach/mach.h>
#endif

static double heldBusy = 0;
static double heldWall = 0;
static double heldCpu = 0;

static double mdd_usage_now() {
	struct timeval held;
	gettimeofday(&held, nullptr);

	return held.tv_sec + held.tv_usec / 1000000.0;
}

static double mdd_usage_spent() {
	struct rusage held;
	if (getrusage(RUSAGE_SELF, &held) != 0) return -1;

	return held.ru_utime.tv_sec + held.ru_utime.tv_usec / 1000000.0
		+ held.ru_stime.tv_sec + held.ru_stime.tv_usec / 1000000.0;
}

extern "C" void mdd_usage_start() {
	heldBusy = mdd_usage_spent();
	heldWall = mdd_usage_now();
}

extern "C" void mdd_usage_stop() {}

extern "C" double mdd_usage_cpu() {
	const double busy = mdd_usage_spent();
	const double wall = mdd_usage_now();

	if (busy < 0) return heldCpu;

	if (wall > heldWall && busy >= heldBusy) {
		const long cores = sysconf(_SC_NPROCESSORS_ONLN);
		const double many = cores < 1 ? 1.0 : (double) cores;

		heldCpu = (busy - heldBusy) / (wall - heldWall) * 100.0 / many;

		if (heldCpu < 0) heldCpu = 0;
		if (heldCpu > 100) heldCpu = 100;
	}

	heldBusy = busy;
	heldWall = wall;

	return heldCpu;
}

extern "C" double mdd_usage_ram() {
#ifdef __APPLE__
	mach_task_basic_info info;
	mach_msg_type_number_t many = MACH_TASK_BASIC_INFO_COUNT;

	if (task_info(mach_task_self(), MACH_TASK_BASIC_INFO, (task_info_t) &info, &many)
			!= KERN_SUCCESS) {
		return -1;
	}

	return (double) info.resident_size / (1024.0 * 1024.0);
#else
	FILE *file = fopen("/proc/self/statm", "r");
	if (file == nullptr) return -1;

	long total = 0;
	long resident = 0;

	const int read = fscanf(file, "%ld %ld", &total, &resident);
	fclose(file);

	if (read != 2) return -1;

	return (double) resident * (double) sysconf(_SC_PAGESIZE) / (1024.0 * 1024.0);
#endif
}

extern "C" double mdd_usage_gpu() {
	return -1;
}

#endif
