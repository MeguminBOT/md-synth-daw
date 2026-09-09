#ifndef MDD_MIDI_H
#define MDD_MIDI_H

#ifdef __cplusplus
extern "C" {
#endif

/**
 * What mdd_midi_take answers when nothing is waiting.
 */
#define MDD_MIDI_EMPTY (-1)

/**
 * @return How many input ports the machine has.
 */
int mdd_midi_count();

/**
 * @param index Which port.
 * @return What it is called.
 */
const char *mdd_midi_name(int index);

/**
 * Opens a port, closing whichever was open before.
 *
 * @param index Which port.
 * @return False where it would not open.
 */
bool mdd_midi_open(int index);

/**
 * Closes the open port.
 */
void mdd_midi_close();

/**
 * @return Whether a port is open.
 */
bool mdd_midi_holding();

/**
 * Takes the oldest message waiting. Messages arrive on the driver's own thread and
 * are queued, so this may be called from anywhere.
 *
 * @return The message packed into one value, or MDD_MIDI_EMPTY.
 */
int mdd_midi_take();

/**
 * @return How many messages were dropped because nothing took them in time.
 */
int mdd_midi_lost();

#ifdef __cplusplus
}
#endif

#endif
