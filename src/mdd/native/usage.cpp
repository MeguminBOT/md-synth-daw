/**
 * What this process is costing the machine: processor, memory and graphics memory.
 *
 * Processor use is a difference of two readings rather than an instant, so the first
 * call after starting answers nothing useful and the ones after it are a mean over the
 * gap.
 *
 * The graphics figures are this process's own on Windows, through the performance counters,
 * and on Linux, through what the kernel's graphics driver writes about each client in
 * /proc/self/fdinfo, which amdgpu, i915, xe and nvidia do and a driver without it answers
 * nothing. macOS keeps no figure for one process, so there they are the whole device's, read
 * from the accelerator's own statistics.
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
static PDH_HCOUNTER vramCounter = nullptr;
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

	swprintf(path, 128, L"\\GPU Process Memory(pid_%lu*)\\Dedicated Usage",
		(unsigned long)GetCurrentProcessId());

	if (PdhAddEnglishCounterW(gpuQuery, path, 0, &vramCounter) != ERROR_SUCCESS) {
		vramCounter = nullptr;
	}

	PdhCollectQueryData(gpuQuery);
	gpuReady = true;
}

extern "C" void mdd_usage_stop() {
	if (gpuQuery == nullptr) return;

	PdhCloseQuery(gpuQuery);

	gpuQuery = nullptr;
	gpuCounter = nullptr;
	vramCounter = nullptr;
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

extern "C" double mdd_usage_peak() {
	PROCESS_MEMORY_COUNTERS held;

	if (!GetProcessMemoryInfo(GetCurrentProcess(), &held, sizeof(held))) return -1;
	return (double)held.PeakWorkingSetSize / (1024.0 * 1024.0);
}

extern "C" double mdd_usage_vram() {
	if (!gpuReady || vramCounter == nullptr) return -1;

	if (PdhCollectQueryData(gpuQuery) != ERROR_SUCCESS) return -1;

	DWORD bytes = 0;
	DWORD count = 0;

	PDH_STATUS state = PdhGetFormattedCounterArrayW(vramCounter, PDH_FMT_LARGE, &bytes,
		&count, nullptr);

	if (state != (PDH_STATUS)PDH_MORE_DATA || bytes == 0) return 0;

	PDH_FMT_COUNTERVALUE_ITEM_W *items = (PDH_FMT_COUNTERVALUE_ITEM_W *)malloc(bytes);
	if (items == nullptr) return 0;

	double much = 0;

	if (PdhGetFormattedCounterArrayW(vramCounter, PDH_FMT_LARGE, &bytes, &count, items)
			== ERROR_SUCCESS) {
		for (DWORD index = 0; index < count; index++) {
			much += (double)items[index].FmtValue.largeValue;
		}
	}

	free(items);

	if (much < 0) much = 0;
	return much / (1024.0 * 1024.0);
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
#include <cstdlib>
#include <cstring>
#include <ctime>

#ifdef __APPLE__
#include <mach/mach.h>
#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOKitLib.h>
#elif defined(__linux__) && !defined(__ANDROID__)
#include <dirent.h>
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

extern "C" double mdd_usage_peak() {
	struct rusage held;

	if (getrusage(RUSAGE_SELF, &held) != 0) return -1;

#ifdef __APPLE__
	return (double) held.ru_maxrss / (1024.0 * 1024.0);
#else
	return (double) held.ru_maxrss / 1024.0;
#endif
}

#if defined(__APPLE__)

/**
 * @param from A dictionary.
 * @param key A key in it.
 * @param into Where the number it holds goes.
 * @return Whether it holds a number.
 */
static bool mdd_usage_number(CFDictionaryRef from, CFStringRef key, double *into) {
	const void *held = CFDictionaryGetValue(from, key);
	if (held == nullptr || CFGetTypeID(held) != CFNumberGetTypeID()) return false;

	return CFNumberGetValue((CFNumberRef)held, kCFNumberDoubleType, into);
}

/**
 * Reads the first graphics accelerator that keeps statistics: how busy it is, in percent, and how
 * much memory it has in use, in bytes, -1 for either it does not say.
 *
 * @param busy Where how busy it is goes.
 * @param memory Where the memory in use goes.
 * @return Whether an accelerator answered at all.
 */
static bool mdd_usage_accelerator(double *busy, double *memory) {
	*busy = -1;
	*memory = -1;

	io_iterator_t found = 0;

	if (IOServiceGetMatchingServices(MACH_PORT_NULL, IOServiceMatching("IOAccelerator"), &found)
			!= KERN_SUCCESS) {
		return false;
	}

	bool answered = false;
	io_object_t service = 0;

	while (!answered && (service = IOIteratorNext(found)) != 0) {
		CFMutableDictionaryRef properties = nullptr;

		if (IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0)
				== KERN_SUCCESS && properties != nullptr) {
			const void *held = CFDictionaryGetValue(properties, CFSTR("PerformanceStatistics"));

			if (held != nullptr && CFGetTypeID(held) == CFDictionaryGetTypeID()) {
				const CFDictionaryRef stats = (CFDictionaryRef)held;
				double value = 0;

				if (mdd_usage_number(stats, CFSTR("Device Utilization %"), &value)) {
					*busy = value;
					answered = true;
				}

				if (mdd_usage_number(stats, CFSTR("In use system memory"), &value)
						|| mdd_usage_number(stats, CFSTR("vramUsedBytes"), &value)) {
					*memory = value;
					answered = true;
				}
			}

			CFRelease(properties);
		}

		IOObjectRelease(service);
	}

	IOObjectRelease(found);
	return answered;
}

extern "C" double mdd_usage_gpu() {
	double busy = -1;
	double memory = -1;

	if (!mdd_usage_accelerator(&busy, &memory) || busy < 0) return -1;

	return busy > 100 ? 100 : busy;
}

extern "C" double mdd_usage_vram() {
	double busy = -1;
	double memory = -1;

	if (!mdd_usage_accelerator(&busy, &memory) || memory < 0) return -1;

	return memory / (1024.0 * 1024.0);
}

#elif defined(__linux__) && !defined(__ANDROID__)

/**
 * The most graphics clients of this process told apart, which is far more than one renderer
 * opens.
 */
#define MDD_USAGE_CLIENTS 64

static double heldEngines = -1;
static double heldEngineWall = 0;
static double heldGpu = -1;

/**
 * @param line A line of fdinfo, from the colon on.
 * @return The size it gives in bytes, reading a unit of KiB, MiB or GiB after the number.
 */
static double mdd_usage_bytes(const char *line) {
	char *end = nullptr;
	const double much = std::strtod(line, &end);

	if (end == nullptr) return much;
	while (*end == ' ' || *end == '\t') end++;

	if (std::strncmp(end, "KiB", 3) == 0) return much * 1024.0;
	if (std::strncmp(end, "MiB", 3) == 0) return much * 1024.0 * 1024.0;
	if (std::strncmp(end, "GiB", 3) == 0) return much * 1024.0 * 1024.0 * 1024.0;

	return much;
}

/**
 * Reads every graphics client this process holds, each once however many descriptors reach it:
 * the nanoseconds its engines have been busy, added up, and the video memory resident in it.
 *
 * @param engines Where the busy nanoseconds go.
 * @param memory Where the bytes of video memory go.
 * @return How many clients there were, nought where the driver writes none of this.
 */
static int mdd_usage_clients(double *engines, double *memory) {
	*engines = 0;
	*memory = 0;

	DIR *folder = opendir("/proc/self/fdinfo");
	if (folder == nullptr) return 0;

	unsigned long seen[MDD_USAGE_CLIENTS];
	int clients = 0;
	char path[64];
	char line[256];
	struct dirent *entry = nullptr;

	while ((entry = readdir(folder)) != nullptr) {
		if (entry->d_name[0] == '.') continue;

		std::snprintf(path, sizeof(path), "/proc/self/fdinfo/%s", entry->d_name);

		FILE *file = std::fopen(path, "r");
		if (file == nullptr) continue;

		bool drawn = false;
		bool named = false;
		unsigned long client = 0;
		double busy = 0;
		double resident = 0;
		double older = 0;

		while (std::fgets(line, sizeof(line), file) != nullptr) {
			const char *colon = std::strchr(line, ':');
			if (colon == nullptr) continue;

			if (std::strncmp(line, "drm-driver:", 11) == 0) {
				drawn = true;
			} else if (std::strncmp(line, "drm-client-id:", 14) == 0) {
				client = std::strtoul(colon + 1, nullptr, 10);
				named = true;
			} else if (std::strncmp(line, "drm-engine-", 11) == 0
					&& std::strncmp(line + 11, "capacity-", 9) != 0) {
				busy += std::strtod(colon + 1, nullptr);
			} else if (std::strncmp(line, "drm-resident-vram", 17) == 0
					|| std::strncmp(line, "drm-resident-local", 18) == 0) {
				resident += mdd_usage_bytes(colon + 1);
			} else if (std::strncmp(line, "drm-memory-vram", 15) == 0) {
				older += mdd_usage_bytes(colon + 1);
			}
		}

		std::fclose(file);

		if (!drawn) continue;

		bool again = false;

		if (named) {
			for (int at = 0; at < clients && at < MDD_USAGE_CLIENTS; at++) {
				if (seen[at] == client) again = true;
			}
		}

		if (again) continue;

		if (clients < MDD_USAGE_CLIENTS) seen[clients] = client;
		clients++;

		*engines += busy;
		*memory += resident > 0 ? resident : older;
	}

	closedir(folder);
	return clients;
}

/**
 * @return A monotonic clock, in nanoseconds.
 */
static double mdd_usage_ticking() {
	struct timespec held;
	clock_gettime(CLOCK_MONOTONIC, &held);

	return held.tv_sec * 1000000000.0 + held.tv_nsec;
}

extern "C" double mdd_usage_gpu() {
	double engines = 0;
	double memory = 0;

	if (mdd_usage_clients(&engines, &memory) == 0) return -1;

	const double now = mdd_usage_ticking();

	if (heldEngines >= 0 && now > heldEngineWall && engines >= heldEngines) {
		heldGpu = (engines - heldEngines) / (now - heldEngineWall) * 100.0;

		if (heldGpu < 0) heldGpu = 0;
		if (heldGpu > 100) heldGpu = 100;
	}

	heldEngines = engines;
	heldEngineWall = now;

	return heldGpu < 0 ? 0 : heldGpu;
}

extern "C" double mdd_usage_vram() {
	double engines = 0;
	double memory = 0;

	if (mdd_usage_clients(&engines, &memory) == 0) return -1;

	return memory / (1024.0 * 1024.0);
}

#else

extern "C" double mdd_usage_gpu() {
	return -1;
}

extern "C" double mdd_usage_vram() {
	return -1;
}

#endif

#endif
