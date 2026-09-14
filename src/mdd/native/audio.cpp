/**
 * The audio device, through miniaudio.
 *
 * A device owns a ring the render thread writes into and the callback reads out of,
 * so the two never wait on each other. It is opened stopped, and nothing is played
 * until the ring has been primed, because a WASAPI device asks for more in its first
 * few callbacks than the buffer size it reports.
 */
#define MA_NO_DECODING
#define MA_NO_ENCODING
#define MA_NO_WAV
#define MA_NO_FLAC
#define MA_NO_MP3
#define MA_NO_GENERATION
#define MA_NO_ENGINE
#define MA_NO_NODE_GRAPH
#define MA_NO_RESOURCE_MANAGER
#define MA_IMPLEMENTATION
#include "miniaudio.h"

#include "audio.h"

#include <atomic>
#include <cstring>
#include <new>

namespace {
	constexpr unsigned int CAPACITY = 16384;
	constexpr unsigned int MASK = CAPACITY - 1;
	constexpr int LISTED = 64;

	struct Listed {
		ma_device_id id;
		char name[MA_MAX_DEVICE_NAME_LENGTH + 1];
	};

	Listed listed[LISTED];
	int listedCount = 0;
}

/**
 * Asks the system for its playback devices again and keeps up to LISTED of them.
 */
static int mdd_audio_list(void) {
	listedCount = 0;

	ma_context context;
	if (ma_context_init(nullptr, 0, nullptr, &context) != MA_SUCCESS) return 0;

	ma_device_info *playback = nullptr;
	ma_device_info *capture = nullptr;
	ma_uint32 playbackCount = 0;
	ma_uint32 captureCount = 0;

	if (ma_context_get_devices(&context, &playback, &playbackCount, &capture, &captureCount)
			== MA_SUCCESS) {
		for (ma_uint32 i = 0; i < playbackCount && listedCount < LISTED; i++) {
			listed[listedCount].id = playback[i].id;
			std::memcpy(listed[listedCount].name, playback[i].name, sizeof(listed[listedCount].name));
			listed[listedCount].name[MA_MAX_DEVICE_NAME_LENGTH] = '\0';
			listedCount++;
		}
	}

	ma_context_uninit(&context);
	return listedCount;
}

extern "C" int mdd_audio_count(void) {
	return mdd_audio_list();
}

extern "C" const char *mdd_audio_named(int index) {
	return index < 0 || index >= listedCount ? "" : listed[index].name;
}

struct MddDevice {
	float ring[CAPACITY * 2];
	std::atomic<unsigned int> head;
	std::atomic<unsigned int> tail;
	std::atomic<unsigned int> underruns;
	std::atomic<unsigned int> taken;

	ma_device device;
	bool opened;
	bool started;
};

static void mdd_audio_drain(ma_device *handle, void *output, const void *, ma_uint32 frameCount) {
	MddDevice *self = static_cast<MddDevice *>(handle->pUserData);
	float *out = static_cast<float *>(output);

	if (self == nullptr) {
		std::memset(out, 0, static_cast<size_t>(frameCount) * 2 * sizeof(float));
		return;
	}

	const unsigned int at = self->tail.load(std::memory_order_relaxed);
	const unsigned int have = self->head.load(std::memory_order_acquire) - at;
	const unsigned int take = have < frameCount ? have : frameCount;

	for (unsigned int i = 0; i < take; i++) {
		const unsigned int index = (at + i) & MASK;
		out[i * 2] = self->ring[index * 2];
		out[i * 2 + 1] = self->ring[index * 2 + 1];
	}

	for (unsigned int i = take; i < frameCount; i++) {
		out[i * 2] = 0.0f;
		out[i * 2 + 1] = 0.0f;
	}

	if (take < frameCount) self->underruns.fetch_add(1, std::memory_order_relaxed);

	self->taken.fetch_add(take, std::memory_order_relaxed);
	self->tail.store(at + take, std::memory_order_release);
}

extern "C" MddDevice *mdd_audio_open(int rate, int period, const char *name) {
	MddDevice *self = new (std::nothrow) MddDevice();
	if (self == nullptr) return nullptr;

	self->head.store(0, std::memory_order_relaxed);
	self->tail.store(0, std::memory_order_relaxed);
	self->underruns.store(0, std::memory_order_relaxed);
	self->taken.store(0, std::memory_order_relaxed);
	self->opened = false;
	self->started = false;

	ma_device_config config = ma_device_config_init(ma_device_type_playback);
	config.playback.format = ma_format_f32;
	config.playback.channels = 2;
	config.sampleRate = static_cast<ma_uint32>(rate > 0 ? rate : 0);
	config.dataCallback = mdd_audio_drain;
	config.pUserData = self;
	config.noPreSilencedOutputBuffer = MA_TRUE;
	config.performanceProfile = ma_performance_profile_low_latency;
	config.wasapi.usage = ma_wasapi_usage_pro_audio;
	config.wasapi.noAutoConvertSRC = MA_TRUE;

	if (period > 0) {
		config.periodSizeInFrames = static_cast<ma_uint32>(period);
		config.periods = 2;
	}

	ma_device_id chosen;

	if (name != nullptr && name[0] != '\0') {
		mdd_audio_list();

		for (int i = 0; i < listedCount; i++) {
			if (std::strcmp(listed[i].name, name) != 0) continue;

			chosen = listed[i].id;
			config.playback.pDeviceID = &chosen;
			break;
		}
	}

	if (ma_device_init(nullptr, &config, &self->device) != MA_SUCCESS) {
		delete self;
		return nullptr;
	}

	self->opened = true;
	return self;
}

extern "C" int mdd_audio_start(MddDevice *device) {
	if (device == nullptr || !device->opened) return 0;
	if (device->started) return 1;
	if (ma_device_start(&device->device) != MA_SUCCESS) return 0;

	device->started = true;
	return 1;
}

extern "C" void mdd_audio_stop(MddDevice *device) {
	if (device == nullptr || !device->started) return;

	ma_device_stop(&device->device);
	device->started = false;
}

extern "C" void mdd_audio_close(MddDevice *device) {
	if (device == nullptr) return;
	if (device->opened) ma_device_uninit(&device->device);
	delete device;
}

extern "C" int mdd_audio_rate(MddDevice *device) {
	return device == nullptr ? 0 : static_cast<int>(device->device.sampleRate);
}

extern "C" int mdd_audio_period(MddDevice *device) {
	return device == nullptr ? 0 : static_cast<int>(device->device.playback.internalPeriodSizeInFrames);
}

extern "C" int mdd_audio_periods(MddDevice *device) {
	return device == nullptr ? 0 : static_cast<int>(device->device.playback.internalPeriods);
}

extern "C" int mdd_audio_buffer(MddDevice *device) {
	if (device == nullptr) return 0;

#if defined(MA_WIN32)
	if (device->device.pContext != nullptr
			&& device->device.pContext->backend == ma_backend_wasapi) {
		return static_cast<int>(device->device.wasapi.actualBufferSizeInFramesPlayback);
	}
#endif

	return static_cast<int>(device->device.playback.internalPeriodSizeInFrames
		* device->device.playback.internalPeriods);
}

extern "C" const char *mdd_audio_name(MddDevice *device) {
	return device == nullptr ? "" : device->device.playback.name;
}

extern "C" int mdd_audio_capacity(MddDevice *device) {
	return device == nullptr ? 0 : static_cast<int>(CAPACITY);
}

extern "C" int mdd_audio_held(MddDevice *device) {
	if (device == nullptr) return 0;

	const unsigned int at = device->head.load(std::memory_order_relaxed);
	return static_cast<int>(at - device->tail.load(std::memory_order_acquire));
}

extern "C" int mdd_audio_room(MddDevice *device) {
	if (device == nullptr) return 0;
	return static_cast<int>(CAPACITY) - mdd_audio_held(device);
}

extern "C" int mdd_audio_write(MddDevice *device, const float *pairs, int frames) {
	if (device == nullptr || pairs == nullptr || frames <= 0) return 0;

	const unsigned int at = device->head.load(std::memory_order_relaxed);
	const unsigned int used = at - device->tail.load(std::memory_order_acquire);
	const unsigned int room = CAPACITY - used;
	const unsigned int want = static_cast<unsigned int>(frames);
	const unsigned int take = room < want ? room : want;

	for (unsigned int i = 0; i < take; i++) {
		const unsigned int index = (at + i) & MASK;
		device->ring[index * 2] = pairs[i * 2];
		device->ring[index * 2 + 1] = pairs[i * 2 + 1];
	}

	device->head.store(at + take, std::memory_order_release);
	return static_cast<int>(take);
}

extern "C" int mdd_audio_underruns(MddDevice *device) {
	return device == nullptr ? 0 : static_cast<int>(device->underruns.load(std::memory_order_relaxed));
}

extern "C" int mdd_audio_taken(MddDevice *device) {
	return device == nullptr ? 0 : static_cast<int>(device->taken.load(std::memory_order_relaxed));
}

extern "C" void mdd_audio_forget(MddDevice *device) {
	if (device == nullptr) return;
	device->underruns.store(0, std::memory_order_relaxed);
	device->taken.store(0, std::memory_order_relaxed);
}

extern "C" double mdd_audio_latency(MddDevice *device) {
	if (device == nullptr) return 0.0;

	const int rate = mdd_audio_rate(device);
	if (rate <= 0) return 0.0;

	return static_cast<double>(mdd_audio_held(device) + mdd_audio_period(device)) / rate;
}
