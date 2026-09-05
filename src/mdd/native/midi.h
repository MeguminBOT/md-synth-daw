#ifndef MDD_MIDI_H
#define MDD_MIDI_H

#ifdef __cplusplus
extern "C" {
#endif

#define MDD_MIDI_EMPTY (-1)

int mdd_midi_count();
const char *mdd_midi_name(int index);

bool mdd_midi_open(int index);
void mdd_midi_close();
bool mdd_midi_holding();

int mdd_midi_take();
int mdd_midi_lost();

#ifdef __cplusplus
}
#endif

#endif
