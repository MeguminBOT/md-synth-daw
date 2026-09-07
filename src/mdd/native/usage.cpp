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

	if (state != PDH_MORE_DATA || bytes == 0) return 0;

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

extern "C" void mdd_usage_start() {}
extern "C" void mdd_usage_stop() {}
extern "C" double mdd_usage_cpu() { return -1; }
extern "C" double mdd_usage_ram() { return -1; }
extern "C" double mdd_usage_gpu() { return -1; }

#endif
