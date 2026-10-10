/**
 * SDL events, translated into the small set this application cares about.
 *
 * SDL3 renames a good deal of what SDL2 called something else: a display scale change
 * arrives as an event rather than being polled for, which is why it is in the list.
 */
#include "events.h"
#include "window.h"

#include <string.h>

namespace {
	char clipboard[MDD_EVENT_TEXT_BYTES];

	int foldMods(SDL_Keymod state) {
		int mods = MDD_MOD_NONE;
		if ((state & SDL_KMOD_SHIFT) != 0) mods |= MDD_MOD_SHIFT;
		if ((state & SDL_KMOD_CTRL) != 0) mods |= MDD_MOD_CTRL;
		if ((state & SDL_KMOD_ALT) != 0) mods |= MDD_MOD_ALT;
		if ((state & SDL_KMOD_GUI) != 0) mods |= MDD_MOD_GUI;
		return mods;
	}

	/**
	 * Cuts text that was cut at the room it had back to the last whole character, so a long
	 * paste or a long dropped path never ends half way through one and reaches the other side as
	 * text that is not UTF-8.
	 *
	 * @param text Text that was copied in and filled the room.
	 */
	void whole(char *text) {
		const size_t end = strlen(text);
		size_t at = end;

		while (at > 0 && (static_cast<unsigned char>(text[at - 1]) & 0xC0) == 0x80) at--;
		if (at == 0) return;

		const unsigned char lead = static_cast<unsigned char>(text[at - 1]);
		const size_t wants = lead >= 0xF0 ? 4 : (lead >= 0xE0 ? 3 : (lead >= 0xC0 ? 2 : 1));

		if (end - (at - 1) < wants) text[at - 1] = '\0';
	}

	void carry(MddEvent *out, const char *text) {
		if (text == nullptr) {
			out->text[0] = '\0';
			return;
		}

		if (SDL_strlcpy(out->text, text, MDD_EVENT_TEXT_BYTES) >= MDD_EVENT_TEXT_BYTES) whole(out->text);
	}

	/**
	 * How many render pixels one of a window's own coordinates spans: 2 for a window on a Retina
	 * display, and 1 wherever the two are the same, as they always are on Windows. SDL reports the
	 * pointer in the window's coordinates and the interface lays out and hit tests in render
	 * pixels, so every position an event carries is multiplied by it on the way in.
	 *
	 * @param id The window the event belongs to.
	 * @return The window's pixel density, or 1 for a window that is gone.
	 */
	float densityOf(SDL_WindowID id) {
		SDL_Window *window = SDL_GetWindowFromID(id);
		if (window == nullptr) return 1.0f;

		const float density = SDL_GetWindowPixelDensity(window);
		return density > 0.0f ? density : 1.0f;
	}

	void blank(MddEvent *out) {
		out->type = MDD_EVENT_NONE;
		out->windowID = 0;
		out->code = 0;
		out->value = 0;
		out->mods = MDD_MOD_NONE;
		out->x = 0.0f;
		out->y = 0.0f;
		out->text[0] = '\0';
	}
}

extern "C" void mdd_pump_events(void) {
	SDL_PumpEvents();
}

extern "C" int mdd_poll_event(MddEvent *out) {
	if (out == nullptr) return 0;

	SDL_Event event;
	while (SDL_PollEvent(&event)) {
		blank(out);

		switch (event.type) {
			case SDL_EVENT_QUIT:
				out->type = MDD_EVENT_QUIT;
				return 1;

			case SDL_EVENT_KEY_DOWN:
			case SDL_EVENT_KEY_UP:
				out->type = event.type == SDL_EVENT_KEY_DOWN ? MDD_EVENT_KEY_DOWN : MDD_EVENT_KEY_UP;
				out->windowID = event.key.windowID;
				out->code = static_cast<int>(event.key.scancode);
				out->value = event.key.repeat ? 1 : 0;
				out->mods = foldMods(event.key.mod);
				return 1;

			case SDL_EVENT_MOUSE_MOTION:
				out->type = MDD_EVENT_MOUSE_MOVE;
				out->windowID = event.motion.windowID;
				out->code = static_cast<int>(event.motion.state);
				out->mods = foldMods(SDL_GetModState());
				out->x = event.motion.x * densityOf(event.motion.windowID);
				out->y = event.motion.y * densityOf(event.motion.windowID);
				return 1;

			case SDL_EVENT_MOUSE_BUTTON_DOWN:
			case SDL_EVENT_MOUSE_BUTTON_UP:
				out->type = event.type == SDL_EVENT_MOUSE_BUTTON_DOWN
					? MDD_EVENT_MOUSE_DOWN : MDD_EVENT_MOUSE_UP;
				out->windowID = event.button.windowID;
				out->code = event.button.button;
				out->value = event.button.clicks;
				out->mods = foldMods(SDL_GetModState());
				out->x = event.button.x * densityOf(event.button.windowID);
				out->y = event.button.y * densityOf(event.button.windowID);
				return 1;

			case SDL_EVENT_MOUSE_WHEEL:
				out->type = MDD_EVENT_MOUSE_WHEEL;
				out->windowID = event.wheel.windowID;
				out->mods = foldMods(SDL_GetModState());
				out->x = event.wheel.direction == SDL_MOUSEWHEEL_FLIPPED ? -event.wheel.x : event.wheel.x;
				out->y = event.wheel.direction == SDL_MOUSEWHEEL_FLIPPED ? -event.wheel.y : event.wheel.y;
				return 1;

			case SDL_EVENT_TEXT_INPUT:
				out->type = MDD_EVENT_TEXT;
				out->windowID = event.text.windowID;
				out->mods = foldMods(SDL_GetModState());
				carry(out, event.text.text);
				return 1;

			case SDL_EVENT_WINDOW_CLOSE_REQUESTED:
				out->type = MDD_EVENT_WINDOW_CLOSE;
				out->windowID = event.window.windowID;
				return 1;

			case SDL_EVENT_WINDOW_PIXEL_SIZE_CHANGED:
			case SDL_EVENT_WINDOW_RESIZED:
				out->type = MDD_EVENT_WINDOW_RESIZED;
				out->windowID = event.window.windowID;
				out->code = event.window.data1;
				out->value = event.window.data2;
				return 1;

			case SDL_EVENT_WINDOW_FOCUS_LOST:
				out->type = MDD_EVENT_WINDOW_FOCUS_LOST;
				out->windowID = event.window.windowID;
				return 1;

			case SDL_EVENT_WINDOW_FOCUS_GAINED:
				out->type = MDD_EVENT_WINDOW_FOCUS_GAINED;
				out->windowID = event.window.windowID;
				return 1;

			case SDL_EVENT_WINDOW_DISPLAY_SCALE_CHANGED:
				out->type = MDD_EVENT_WINDOW_SCALE_CHANGED;
				out->windowID = event.window.windowID;
				return 1;

			case SDL_EVENT_WINDOW_EXPOSED:
				out->type = MDD_EVENT_WINDOW_EXPOSED;
				out->windowID = event.window.windowID;
				return 1;

			case SDL_EVENT_DROP_FILE:
				out->type = MDD_EVENT_DROP_FILE;
				out->windowID = event.drop.windowID;
				out->x = event.drop.x * densityOf(event.drop.windowID);
				out->y = event.drop.y * densityOf(event.drop.windowID);
				carry(out, event.drop.data);
				return 1;

			default:
				break;
		}
	}

	blank(out);
	return 0;
}

extern "C" const char *mdd_event_text(const MddEvent *event) {
	return event == nullptr ? "" : event->text;
}

extern "C" int mdd_mods(void) {
	return foldMods(SDL_GetModState());
}

extern "C" void mdd_clipboard_set(const char *text) {
	if (text != nullptr) SDL_SetClipboardText(text);
}

extern "C" const char *mdd_clipboard_get(void) {
	char *held = SDL_GetClipboardText();
	if (held == nullptr) {
		clipboard[0] = '\0';
		return clipboard;
	}

	if (SDL_strlcpy(clipboard, held, MDD_EVENT_TEXT_BYTES) >= MDD_EVENT_TEXT_BYTES) whole(clipboard);
	SDL_free(held);
	return clipboard;
}

extern "C" int mdd_open_url(const char *url) {
	if (url == nullptr || url[0] == '\0') return 0;
	return SDL_OpenURL(url) ? 1 : 0;
}
