#ifndef MDD_EVENTS_H
#define MDD_EVENTS_H

#ifdef __cplusplus
extern "C" {
#endif

enum {
	MDD_EVENT_NONE = 0,
	MDD_EVENT_QUIT = 1,
	MDD_EVENT_KEY_DOWN = 2,
	MDD_EVENT_KEY_UP = 3,
	MDD_EVENT_MOUSE_MOVE = 4,
	MDD_EVENT_MOUSE_DOWN = 5,
	MDD_EVENT_MOUSE_UP = 6,
	MDD_EVENT_MOUSE_WHEEL = 7,
	MDD_EVENT_TEXT = 8,
	MDD_EVENT_WINDOW_CLOSE = 9,
	MDD_EVENT_WINDOW_RESIZED = 10,
	MDD_EVENT_WINDOW_FOCUS_LOST = 11,
	MDD_EVENT_WINDOW_FOCUS_GAINED = 12,
	MDD_EVENT_WINDOW_SCALE_CHANGED = 13,
	MDD_EVENT_WINDOW_EXPOSED = 14,
	MDD_EVENT_DROP_FILE = 15
};

enum {
	MDD_MOD_NONE = 0,
	MDD_MOD_SHIFT = 1,
	MDD_MOD_CTRL = 2,
	MDD_MOD_ALT = 4,
	MDD_MOD_GUI = 8
};

enum {
	MDD_BUTTON_LEFT = 1,
	MDD_BUTTON_MIDDLE = 2,
	MDD_BUTTON_RIGHT = 3
};

#define MDD_EVENT_TEXT_BYTES 512

typedef struct {
	int type;
	unsigned int windowID;
	int code;
	int value;
	int mods;
	float x;
	float y;
	char text[MDD_EVENT_TEXT_BYTES];
} MddEvent;

int mdd_poll_event(MddEvent *out);
const char *mdd_event_text(const MddEvent *event);

int mdd_mods(void);
float mdd_mouse_x(void);
float mdd_mouse_y(void);

void mdd_clipboard_set(const char *text);
const char *mdd_clipboard_get(void);

#ifdef __cplusplus
}
#endif

#endif
