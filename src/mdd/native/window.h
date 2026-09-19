#ifndef MDD_WINDOW_H
#define MDD_WINDOW_H

#include <SDL3/SDL.h>

#ifdef __cplusplus
extern "C" {
#endif

/**
 * Starts SDL.
 *
 * @return Nonzero where it started.
 */
int mdd_sdl_init(void);

/**
 * Shuts SDL down.
 */
void mdd_sdl_quit(void);

/**
 * @return What SDL said went wrong last.
 */
const char *mdd_sdl_error(void);

/**
 * Opens a window, hidden, so nothing is shown before the first frame is drawn.
 *
 * @param title What to call it.
 * @param width How wide, in points.
 * @param height How tall.
 * @param resizable Nonzero to let it be resized.
 * @param highDpi Nonzero to draw at the display real pixel density.
 * @return The window, or NULL.
 */
SDL_Window *mdd_window_create(const char *title, int width, int height, int resizable,
	int highDpi);

/**
 * Closes a window.
 *
 * @param window The window.
 */
void mdd_window_destroy(SDL_Window *window);

/**
 * @param window The window.
 * @return The identifier events carry to say which window they belong to.
 */
unsigned int mdd_window_id(SDL_Window *window);

/**
 * Renames the window.
 *
 * @param window The window.
 * @param title The new name.
 */
void mdd_window_set_title(SDL_Window *window, const char *title);

/**
 * @param window The window.
 * @return How wide it is, in points.
 */
int mdd_window_width(SDL_Window *window);

/**
 * @param window The window.
 * @return How tall it is, in points.
 */
int mdd_window_height(SDL_Window *window);

/**
 * @param window The window.
 * @return How wide it is in real pixels, which differs on a scaled display.
 */
int mdd_window_pixel_width(SDL_Window *window);

/**
 * @param window The window.
 * @return How tall it is in real pixels.
 */
int mdd_window_pixel_height(SDL_Window *window);

/**
 * Resizes the window.
 *
 * @param window The window.
 * @param width How wide.
 * @param height How tall.
 */
void mdd_window_set_size(SDL_Window *window, int width, int height);

/**
 * Sets the smallest it may be dragged to.
 *
 * @param window The window.
 * @param width How wide.
 * @param height How tall.
 */
void mdd_window_set_minimum_size(SDL_Window *window, int width, int height);

/**
 * Puts the window full screen, or takes it back.
 *
 * @param window The window.
 * @param on Nonzero for full screen.
 */
void mdd_window_set_fullscreen(SDL_Window *window, int on);

/**
 * Shows a window that was created hidden.
 *
 * @param window The window.
 */
void mdd_window_show(SDL_Window *window);

/**
 * Maximises the window.
 *
 * @param window The window.
 */
void mdd_window_maximise(SDL_Window *window);

/**
 * Brings the window in front of the others, restoring it first where it was minimised.
 *
 * @param window The window.
 */
void mdd_window_raise(SDL_Window *window);

/**
 * @param window The window.
 * @return Nonzero where it is maximised.
 */
int mdd_window_maximised(SDL_Window *window);

/**
 * @param window The window.
 * @return The scale the desktop asks it to draw at.
 */
float mdd_window_display_scale(SDL_Window *window);

/**
 * @param window The window.
 * @return How many real pixels there are to a point.
 */
float mdd_display_pixel_density(SDL_Window *window);

/**
 * @param window The window.
 * @return How often the display it is on refreshes, in hertz.
 */
float mdd_display_refresh(SDL_Window *window);

/**
 * Begins taking typed text, which a field being edited needs.
 *
 * @param window The window.
 */
void mdd_text_input_start(SDL_Window *window);

/**
 * Stops taking it.
 *
 * @param window The window.
 */
void mdd_text_input_stop(SDL_Window *window);

/**
 * @return How many backends SDL was built with.
 */
int mdd_render_drivers();

/**
 * @param index Which backend.
 * @return Its name.
 */
const char *mdd_render_driver(int index);

/**
 * Makes a renderer for a window. SDL3 takes two arguments where SDL2 took three,
 * and vsync is set afterwards rather than at creation.
 *
 * @param window The window.
 * @param vsync Nonzero to wait for the display.
 * @param driver Which backend to ask for, or NULL for whichever SDL picks.
 * @return The renderer, or NULL.
 */
SDL_Renderer *mdd_renderer_create(SDL_Window *window, int vsync, const char *driver);

/**
 * Destroys a renderer.
 *
 * @param renderer The renderer.
 */
void mdd_renderer_destroy(SDL_Renderer *renderer);

/**
 * @param renderer The renderer.
 * @return Which backend it actually took.
 */
const char *mdd_renderer_name(SDL_Renderer *renderer);

/**
 * @param renderer The renderer.
 * @return Whether it is waiting for the display.
 */
int mdd_renderer_vsync(SDL_Renderer *renderer);

/**
 * Fills the target with a colour.
 *
 * @param renderer The renderer.
 * @param r Red, 0 to 1.
 * @param g Green.
 * @param b Blue.
 * @param a Alpha.
 */
void mdd_render_clear(SDL_Renderer *renderer, float r, float g, float b, float a);

/**
 * Shows what was drawn. A flip model swap chain rotates buffers, so presenting a
 * frame that was not drawn puts a frame from two presents ago on the screen, and
 * alternating the two reads as heavy flicker. An idle frame must skip this rather
 * than present nothing.
 *
 * On the vulkan backend it then waits for the device to finish the frame, because
 * SDL copies the next frame's vertices over buffers a submitted frame may not have
 * read yet.
 *
 * @param renderer The renderer.
 */
void mdd_render_present(SDL_Renderer *renderer);

/**
 * @param renderer The renderer.
 * @return How wide the output is, in pixels.
 */
int mdd_render_output_width(SDL_Renderer *renderer);

/**
 * @param renderer The renderer.
 * @return How tall it is.
 */
int mdd_render_output_height(SDL_Renderer *renderer);

/**
 * Limits drawing to a rectangle.
 *
 * @param renderer The renderer.
 * @param x Across.
 * @param y Down.
 * @param width How wide.
 * @param height How tall.
 */
void mdd_set_clip(SDL_Renderer *renderer, int x, int y, int width, int height);

/**
 * Takes that limit off.
 *
 * @param renderer The renderer.
 */
void mdd_clear_clip(SDL_Renderer *renderer);

/**
 * @return Nonzero where the desktop asks for reduced motion.
 */
int mdd_reduce_motion(void);

/**
 * Puts up a system message box. It blocks until it is dismissed.
 *
 * @param title The box title.
 * @param said What it says.
 */
void mdd_message(const char *title, const char *said);

/**
 * The same box, marked as a fault rather than as something ordinary. It blocks
 * until it is dismissed.
 *
 * @param title The box title.
 * @param said What it says.
 */
void mdd_fault(const char *title, const char *said);

/**
 * Gives the window an icon from raw pixels.
 *
 * @param window The window.
 * @param pixels The icon.
 * @param width How wide it is.
 * @param height How tall.
 */
void mdd_window_icon(SDL_Window *window, const unsigned char *pixels, int width,
	int height);

/**
 * Sleeps, having asked the operating system for a fine enough scheduler tick
 * first. Without that, a stall quantises to 15.6 ms on Windows.
 *
 * @param seconds How long to sleep.
 */
void mdd_sleep(double seconds);

/**
 * @return Seconds since SDL started, at full precision. A timestamp rounded to whole milliseconds
 * 	is useless for a frame, which is 16.688 of them.
 */
double mdd_ticks(void);

/** Cursor: the ordinary arrow. */
#define MDD_CURSOR_ARROW 0

/** Cursor: an I-beam, over text that can be typed in. */
#define MDD_CURSOR_TEXT 1

/** Cursor: a double arrow across, over an edge that resizes sideways. */
#define MDD_CURSOR_ACROSS 2

/** Cursor: a double arrow down, over an edge that resizes up and down. */
#define MDD_CURSOR_DOWN 3

/** Cursor: a pointing hand, over something that answers a click. */
#define MDD_CURSOR_HAND 4

/** Cursor: the four pointed arrow, over something being dragged about. */
#define MDD_CURSOR_MOVE 5

/** How many cursor shapes there are. */
#define MDD_CURSORS 6

/**
 * Puts a cursor shape on the window. The shapes are made the first time each is asked for
 * and kept, and asking for the one already showing does nothing.
 *
 * @param shape Which shape, one of MDD_CURSOR_*.
 */
void mdd_cursor_set(int shape);

/**
 * Frees every cursor shape that was made. Called as the window goes.
 */
void mdd_cursor_free(void);

#ifdef __cplusplus
}
#endif

#endif
