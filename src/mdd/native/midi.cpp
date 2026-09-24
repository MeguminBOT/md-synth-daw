/**
 * MIDI input: opening a port and queueing what arrives on it.
 *
 * Messages arrive on the driver's own thread, so they go into a small lock free ring
 * the main thread takes from. Input only; nothing here sends.
 *
 * Windows opens its MIDI input devices. macOS opens CoreMIDI's sources, which include any
 * other application's virtual ports. Linux reads the kernel's raw MIDI devices,
 * /dev/snd/midiC<card>D<device>, which is every keyboard and interface plugged in and needs no
 * library at all, and does not reach a port only the ALSA sequencer offers. Both of the last
 * two hand over bytes rather than messages, so they go through one parser.
 */
#include "midi.h"

#include <atomic>
#include <cstring>

#define MDD_MIDI_ROOM 1024

static std::atomic<unsigned int> mddMidiWritten(0);
static std::atomic<unsigned int> mddMidiRead(0);
static std::atomic<unsigned int> mddMidiLost(0);

static int mddMidiRing[MDD_MIDI_ROOM];
static char mddMidiNamed[128];

static void mdd_midi_push(int message) {
	const unsigned int at = mddMidiWritten.load(std::memory_order_relaxed);
	const unsigned int out = mddMidiRead.load(std::memory_order_acquire);

	if (at - out >= MDD_MIDI_ROOM) {
		mddMidiLost.fetch_add(1, std::memory_order_relaxed);
		return;
	}

	mddMidiRing[at % MDD_MIDI_ROOM] = message;
	mddMidiWritten.store(at + 1, std::memory_order_release);
}

extern "C" int mdd_midi_take() {
	const unsigned int out = mddMidiRead.load(std::memory_order_relaxed);
	if (out == mddMidiWritten.load(std::memory_order_acquire)) return MDD_MIDI_EMPTY;

	const int one = mddMidiRing[out % MDD_MIDI_ROOM];
	mddMidiRead.store(out + 1, std::memory_order_release);

	return one;
}

extern "C" int mdd_midi_lost() {
	return (int)mddMidiLost.load(std::memory_order_relaxed);
}

/**
 * Empties the ring and forgets what was lost, which a newly opened port starts from.
 */
static void mdd_midi_fresh() {
	mddMidiWritten.store(0, std::memory_order_relaxed);
	mddMidiRead.store(0, std::memory_order_relaxed);
	mddMidiLost.store(0, std::memory_order_relaxed);
}

#if defined(__APPLE__) || (defined(__linux__) && !defined(__ANDROID__))

static int mddMidiStatus = 0;
static int mddMidiNeeds = 0;
static int mddMidiHas = 0;
static int mddMidiData[2];
static bool mddMidiSystem = false;

/**
 * Forgets any message half read, which a newly opened port starts from.
 */
static void mdd_midi_unparsed() {
	mddMidiStatus = 0;
	mddMidiNeeds = 0;
	mddMidiHas = 0;
	mddMidiSystem = false;
}

/**
 * Reads MIDI bytes into whole channel messages and queues each, packed as Windows packs one:
 * the status in the low byte and each data byte above it. Running status is followed, and
 * system exclusive, the other system messages and the real time bytes are passed over.
 *
 * @param bytes The bytes, in the order they arrived.
 * @param many How many.
 */
static void mdd_midi_parsed(const unsigned char *bytes, size_t many) {
	for (size_t at = 0; at < many; at++) {
		const int one = bytes[at];

		if (one >= 0xF8) continue;

		if (one >= 0xF0) {
			mddMidiSystem = one != 0xF7;
			mddMidiStatus = 0;
			mddMidiHas = 0;
			continue;
		}

		if ((one & 0x80) != 0) {
			const int kind = one & 0xF0;

			mddMidiSystem = false;
			mddMidiStatus = one;
			mddMidiNeeds = kind == 0xC0 || kind == 0xD0 ? 1 : 2;
			mddMidiHas = 0;
			continue;
		}

		if (mddMidiSystem || mddMidiStatus == 0) continue;

		mddMidiData[mddMidiHas] = one;
		mddMidiHas++;

		if (mddMidiHas < mddMidiNeeds) continue;

		mdd_midi_push(mddMidiStatus | (mddMidiData[0] << 8)
			| (mddMidiNeeds == 2 ? mddMidiData[1] << 16 : 0));
		mddMidiHas = 0;
	}
}

#endif

#ifdef _WIN32

#include <windows.h>
#include <mmsystem.h>

static HMIDIIN mddMidiHeld = nullptr;

static void CALLBACK mdd_midi_arrived(HMIDIIN, UINT message, DWORD_PTR, DWORD_PTR one, DWORD_PTR) {
	if (message != MIM_DATA) return;
	mdd_midi_push((int)(one & 0xFFFFFF));
}

extern "C" int mdd_midi_count() {
	return (int)midiInGetNumDevs();
}

extern "C" const char *mdd_midi_name(int index) {
	mddMidiNamed[0] = 0;

	if (index < 0 || index >= (int)midiInGetNumDevs()) return mddMidiNamed;

	MIDIINCAPSA caps;
	if (midiInGetDevCapsA((UINT_PTR)index, &caps, sizeof(caps)) != MMSYSERR_NOERROR) {
		return mddMidiNamed;
	}

	strncpy(mddMidiNamed, caps.szPname, sizeof(mddMidiNamed) - 1);
	mddMidiNamed[sizeof(mddMidiNamed) - 1] = 0;

	return mddMidiNamed;
}

extern "C" void mdd_midi_close() {
	if (mddMidiHeld == nullptr) return;

	midiInStop(mddMidiHeld);
	midiInReset(mddMidiHeld);
	midiInClose(mddMidiHeld);

	mddMidiHeld = nullptr;
}

extern "C" bool mdd_midi_open(int index) {
	mdd_midi_close();

	if (index < 0 || index >= (int)midiInGetNumDevs()) return false;

	if (midiInOpen(&mddMidiHeld, (UINT)index, (DWORD_PTR)mdd_midi_arrived, 0,
			CALLBACK_FUNCTION) != MMSYSERR_NOERROR) {
		mddMidiHeld = nullptr;
		return false;
	}

	mdd_midi_fresh();

	if (midiInStart(mddMidiHeld) != MMSYSERR_NOERROR) {
		mdd_midi_close();
		return false;
	}

	return true;
}

extern "C" bool mdd_midi_holding() {
	return mddMidiHeld != nullptr;
}

#elif defined(__APPLE__)

#include <CoreFoundation/CoreFoundation.h>
#include <CoreMIDI/CoreMIDI.h>

static MIDIClientRef mddMidiClient = 0;
static MIDIPortRef mddMidiPort = 0;
static MIDIEndpointRef mddMidiSource = 0;

/**
 * Takes what CoreMIDI read from the source, on CoreMIDI's own thread.
 */
static void mdd_midi_arrived(const MIDIPacketList *list, void *, void *) {
	if (list == nullptr) return;

	const MIDIPacket *packet = &list->packet[0];

	for (UInt32 at = 0; at < list->numPackets; at++) {
		mdd_midi_parsed(packet->data, packet->length);
		packet = MIDIPacketNext(packet);
	}
}

/**
 * @return Whether there is a client and an input port to connect a source to, making them the
 *     first time.
 */
static bool mdd_midi_ready() {
	if (mddMidiPort != 0) return true;

	if (mddMidiClient == 0
			&& MIDIClientCreate(CFSTR("MD Synth"), nullptr, nullptr, &mddMidiClient) != noErr) {
		mddMidiClient = 0;
		return false;
	}

	if (MIDIInputPortCreate(mddMidiClient, CFSTR("input"), mdd_midi_arrived, nullptr, &mddMidiPort)
			!= noErr) {
		mddMidiPort = 0;
		return false;
	}

	return true;
}

extern "C" int mdd_midi_count() {
	return (int)MIDIGetNumberOfSources();
}

extern "C" const char *mdd_midi_name(int index) {
	mddMidiNamed[0] = 0;

	if (index < 0 || index >= (int)MIDIGetNumberOfSources()) return mddMidiNamed;

	const MIDIEndpointRef source = MIDIGetSource((ItemCount)index);
	CFStringRef named = nullptr;

	if (source == 0 || MIDIObjectGetStringProperty(source, kMIDIPropertyDisplayName, &named) != noErr
			|| named == nullptr) {
		return mddMidiNamed;
	}

	if (!CFStringGetCString(named, mddMidiNamed, sizeof(mddMidiNamed), kCFStringEncodingUTF8)) {
		mddMidiNamed[0] = 0;
	}

	CFRelease(named);
	return mddMidiNamed;
}

extern "C" void mdd_midi_close() {
	if (mddMidiSource == 0) return;

	MIDIPortDisconnectSource(mddMidiPort, mddMidiSource);
	mddMidiSource = 0;
}

extern "C" bool mdd_midi_open(int index) {
	mdd_midi_close();

	if (index < 0 || index >= (int)MIDIGetNumberOfSources() || !mdd_midi_ready()) return false;

	const MIDIEndpointRef source = MIDIGetSource((ItemCount)index);
	if (source == 0) return false;

	mdd_midi_fresh();
	mdd_midi_unparsed();

	if (MIDIPortConnectSource(mddMidiPort, source, nullptr) != noErr) return false;

	mddMidiSource = source;
	return true;
}

extern "C" bool mdd_midi_holding() {
	return mddMidiSource != 0;
}

#elif defined(__linux__) && !defined(__ANDROID__)

#include <dirent.h>
#include <fcntl.h>
#include <poll.h>
#include <unistd.h>

#include <cstdio>
#include <cstdlib>
#include <thread>

/**
 * The most raw MIDI devices listed.
 */
#define MDD_MIDI_DEVICES 64

struct MddMidiDevice {
	int card;
	int device;
};

static MddMidiDevice mddMidiDevices[MDD_MIDI_DEVICES];
static int mddMidiListed = 0;
static int mddMidiFile = -1;
static std::atomic<bool> mddMidiReading(false);
static std::thread mddMidiReader;

static int mdd_midi_ordered(const void *one, const void *two) {
	const MddMidiDevice *left = static_cast<const MddMidiDevice *>(one);
	const MddMidiDevice *right = static_cast<const MddMidiDevice *>(two);

	if (left->card != right->card) return left->card - right->card;
	return left->device - right->device;
}

/**
 * Lists the raw MIDI devices the kernel offers, in card and then device order.
 *
 * @return How many there are.
 */
static int mdd_midi_list() {
	mddMidiListed = 0;

	DIR *folder = opendir("/dev/snd");
	if (folder == nullptr) return 0;

	struct dirent *entry = nullptr;

	while ((entry = readdir(folder)) != nullptr && mddMidiListed < MDD_MIDI_DEVICES) {
		int card = 0;
		int device = 0;

		if (std::sscanf(entry->d_name, "midiC%dD%d", &card, &device) != 2) continue;

		mddMidiDevices[mddMidiListed].card = card;
		mddMidiDevices[mddMidiListed].device = device;
		mddMidiListed++;
	}

	closedir(folder);

	std::qsort(mddMidiDevices, (size_t)mddMidiListed, sizeof(MddMidiDevice), mdd_midi_ordered);
	return mddMidiListed;
}

/**
 * Reads the open device until told to stop, waking a tenth of a second at a time to look.
 */
static void mdd_midi_read() {
	unsigned char held[256];

	while (mddMidiReading.load(std::memory_order_acquire)) {
		struct pollfd waiting;

		waiting.fd = mddMidiFile;
		waiting.events = POLLIN;
		waiting.revents = 0;

		if (poll(&waiting, 1, 100) <= 0) continue;

		if ((waiting.revents & (POLLERR | POLLHUP | POLLNVAL)) != 0) break;

		const ssize_t many = read(mddMidiFile, held, sizeof(held));
		if (many > 0) mdd_midi_parsed(held, (size_t)many);
	}
}

extern "C" int mdd_midi_count() {
	return mdd_midi_list();
}

extern "C" const char *mdd_midi_name(int index) {
	mddMidiNamed[0] = 0;

	if (index < 0 || index >= mdd_midi_list()) return mddMidiNamed;

	const MddMidiDevice &one = mddMidiDevices[index];
	char path[64];

	std::snprintf(path, sizeof(path), "/proc/asound/card%d/midi%d", one.card, one.device);

	FILE *file = std::fopen(path, "r");

	if (file != nullptr) {
		if (std::fgets(mddMidiNamed, sizeof(mddMidiNamed), file) == nullptr) mddMidiNamed[0] = 0;
		std::fclose(file);
	}

	size_t length = std::strlen(mddMidiNamed);
	while (length > 0 && (mddMidiNamed[length - 1] == '\n' || mddMidiNamed[length - 1] == ' ')) {
		mddMidiNamed[--length] = 0;
	}

	if (length == 0) {
		std::snprintf(mddMidiNamed, sizeof(mddMidiNamed), "MIDI %d-%d", one.card, one.device);
	}

	return mddMidiNamed;
}

extern "C" void mdd_midi_close() {
	if (mddMidiFile < 0) return;

	mddMidiReading.store(false, std::memory_order_release);
	if (mddMidiReader.joinable()) mddMidiReader.join();

	close(mddMidiFile);
	mddMidiFile = -1;
}

extern "C" bool mdd_midi_open(int index) {
	mdd_midi_close();

	if (index < 0 || index >= mdd_midi_list()) return false;

	char path[64];
	std::snprintf(path, sizeof(path), "/dev/snd/midiC%dD%d", mddMidiDevices[index].card,
		mddMidiDevices[index].device);

	mddMidiFile = open(path, O_RDONLY | O_NONBLOCK | O_CLOEXEC);
	if (mddMidiFile < 0) return false;

	mdd_midi_fresh();
	mdd_midi_unparsed();

	mddMidiReading.store(true, std::memory_order_release);
	mddMidiReader = std::thread(mdd_midi_read);

	return true;
}

extern "C" bool mdd_midi_holding() {
	return mddMidiFile >= 0;
}

#else

extern "C" int mdd_midi_count() {
	return 0;
}

extern "C" const char *mdd_midi_name(int index) {
	(void)index;
	mddMidiNamed[0] = 0;

	return mddMidiNamed;
}

extern "C" bool mdd_midi_open(int index) {
	(void)index;
	return false;
}

extern "C" void mdd_midi_close() {}

extern "C" bool mdd_midi_holding() {
	return false;
}

#endif
