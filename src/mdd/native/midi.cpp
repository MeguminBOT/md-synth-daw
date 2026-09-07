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

	mddMidiWritten.store(0, std::memory_order_relaxed);
	mddMidiRead.store(0, std::memory_order_relaxed);
	mddMidiLost.store(0, std::memory_order_relaxed);

	if (midiInStart(mddMidiHeld) != MMSYSERR_NOERROR) {
		mdd_midi_close();
		return false;
	}

	return true;
}

extern "C" bool mdd_midi_holding() {
	return mddMidiHeld != nullptr;
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
