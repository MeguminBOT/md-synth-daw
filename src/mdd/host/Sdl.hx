package mdd.host;

@:include("window.h")
@:include("events.h")

/**
	SDL3, called directly rather than through a game framework.

	The reason for calling it straight is four behaviours found underneath a framework
	that nothing in the calling code said were true: a frame limiter that delivered 43
	updates a second when asked for 60, a timestamp rounded to whole milliseconds where
	a frame is 16.688 of them, never asking the operating system for a finer scheduler
	tick, and pausing the audio device on window deactivate.

	SDL3 renames a good deal of what SDL2 called something else, so reading SDL2
	answers and adapting them is slower than reading the SDL3 header.
**/
extern class Sdl {
	static inline final EVENT_NONE = 0;

	/**
		Event: the application was asked to close.
	**/
	public static inline final EVENT_QUIT = 1;

	/**
		Event: a key went down.
	**/
	public static inline final EVENT_KEY_DOWN = 2;

	/**
		Event: a key came up.
	**/
	public static inline final EVENT_KEY_UP = 3;

	/**
		Event: the pointer moved.
	**/
	public static inline final EVENT_MOUSE_MOVE = 4;

	/**
		Event: a pointer button went down.
	**/
	public static inline final EVENT_MOUSE_DOWN = 5;

	/**
		Event: a pointer button came up.
	**/
	public static inline final EVENT_MOUSE_UP = 6;

	/**
		Event: the wheel turned.
	**/
	public static inline final EVENT_MOUSE_WHEEL = 7;

	/**
		Event: text was typed.
	**/
	public static inline final EVENT_TEXT = 8;

	/**
		Event: the window was closed.
	**/
	public static inline final EVENT_WINDOW_CLOSE = 9;

	/**
		Event: the window was resized.
	**/
	public static inline final EVENT_WINDOW_RESIZED = 10;
	static inline final EVENT_WINDOW_FOCUS_LOST = 11;
	static inline final EVENT_WINDOW_FOCUS_GAINED = 12;

	/**
		Event: the display scale changed. SDL3 delivers this rather than being polled for it.
	**/
	public static inline final EVENT_WINDOW_SCALE_CHANGED = 13;

	/**
		Event: the window needs redrawing.
	**/
	public static inline final EVENT_WINDOW_EXPOSED = 14;

	/**
		Event: a file was dropped on the window. Its path is read back with `eventText`.
	**/
	public static inline final EVENT_DROP_FILE = 15;

	static inline final MOD_NONE = 0;
	static inline final MOD_SHIFT = 1;
	static inline final MOD_CTRL = 2;
	static inline final MOD_ALT = 4;
	static inline final MOD_GUI = 8;

	static inline final BUTTON_LEFT = 1;
	static inline final BUTTON_MIDDLE = 2;
	static inline final BUTTON_RIGHT = 3;

	/**
		Starts SDL. Nonzero where it started.
	**/
	@:native("mdd_sdl_init")
	public static function init():Int;

	/**
		Shuts SDL down.
	**/
	@:native("mdd_sdl_quit")
	public static function quit():Void;

	/**
		What SDL said went wrong last.
	**/
	@:native("mdd_sdl_error")
	public static function error():cpp.ConstCharStar;

	/**
		Opens a window and answers with it, or null where none opened.
	**/
	@:native("mdd_window_create")
	public static function createWindow(title:cpp.ConstCharStar, width:Int, height:Int,
		resizable:Int, highDpi:Int):cpp.Star<Window>;

	/**
		Closes a window.
	**/
	@:native("mdd_window_destroy")
	public static function destroyWindow(window:cpp.Star<Window>):Void;

	/**
		The identifier events carry to say which window they belong to.
	**/
	@:native("mdd_window_id")
	public static function windowID(window:cpp.Star<Window>):Int;

	/**
		Renames the window.
	**/
	@:native("mdd_window_set_title")
	static function setWindowTitle(window:cpp.Star<Window>, title:cpp.ConstCharStar):Void;

	/**
		How wide the window is, in points.
	**/
	@:native("mdd_window_width")
	public static function windowWidth(window:cpp.Star<Window>):Int;

	/**
		How tall it is, in points.
	**/
	@:native("mdd_window_height")
	public static function windowHeight(window:cpp.Star<Window>):Int;

	/**
		How wide it is in real pixels, which differs on a scaled display.
	**/
	@:native("mdd_window_pixel_width")
	static function windowPixelWidth(window:cpp.Star<Window>):Int;

	/**
		How tall it is in real pixels.
	**/
	@:native("mdd_window_pixel_height")
	static function windowPixelHeight(window:cpp.Star<Window>):Int;

	/**
		Resizes the window.
	**/
	@:native("mdd_window_set_size")
	static function setWindowSize(window:cpp.Star<Window>, width:Int, height:Int):Void;

	/**
		Sets the smallest the window may be dragged to.
	**/
	@:native("mdd_window_set_minimum_size")
	public static function setWindowMinimumSize(window:cpp.Star<Window>, width:Int,
		height:Int):Void;

	/**
		Puts the window full screen, or takes it back.
	**/
	@:native("mdd_window_set_fullscreen")
	static function setWindowFullscreen(window:cpp.Star<Window>, on:Int):Void;

	/**
		Shows a window that was created hidden.
	**/
	@:native("mdd_window_show")
	public static function showWindow(window:cpp.Star<Window>):Void;

	/**
		Maximises the window.
	**/
	@:native("mdd_window_maximise")
	public static function maximiseWindow(window:cpp.Star<Window>):Void;

	/**
		Brings the window in front of the others, restoring it first where it was minimised.
	**/
	@:native("mdd_window_raise")
	public static function raiseWindow(window:cpp.Star<Window>):Void;

	/**
		Whether it is maximised.
	**/
	@:native("mdd_window_maximised")
	public static function windowMaximised(window:cpp.Star<Window>):Int;

	/**
		The scale the desktop asks the window to draw at, which is 2 on a doubled display.
	**/
	@:native("mdd_window_display_scale")
	public static function windowDisplayScale(window:cpp.Star<Window>):Single;

	/**
		How many real pixels there are to a point.
	**/
	@:native("mdd_display_pixel_density")
	public static function pixelDensity(window:cpp.Star<Window>):Single;

	/**
		How wide the renderer output is, in pixels.
	**/
	@:native("mdd_render_output_width")
	public static function outputWidth(renderer:cpp.Star<Canvas>):Int;

	/**
		How tall it is.
	**/
	@:native("mdd_render_output_height")
	public static function outputHeight(renderer:cpp.Star<Canvas>):Int;

	/**
		How often the display refreshes, in hertz.
	**/
	@:native("mdd_display_refresh")
	public static function displayRefresh(window:cpp.Star<Window>):Single;

	/**
		Begins taking typed text, which is what a field being edited needs.
	**/
	@:native("mdd_text_input_start")
	public static function startTextInput(window:cpp.Star<Window>):Void;

	/**
		Stops taking it.
	**/
	@:native("mdd_text_input_stop")
	public static function stopTextInput(window:cpp.Star<Window>):Void;

	/**
		Makes a renderer for a window, by backend name. SDL3 takes the name and the vsync setting separately, unlike SDL2.
	**/
	@:native("mdd_renderer_create")
	public static function createRenderer(window:cpp.Star<Window>, vsync:Int,
		driver:cpp.ConstCharStar):cpp.Star<Canvas>;

	/**
		Destroys a renderer.
	**/
	@:native("mdd_renderer_destroy")
	public static function destroyRenderer(renderer:cpp.Star<Canvas>):Void;

	/**
		How many backends SDL was built with.
	**/
	@:native("mdd_render_drivers")
	public static function renderDrivers():Int;

	/**
		The name of one of them.
	**/
	@:native("mdd_render_driver")
	public static function renderDriver(index:Int):cpp.ConstCharStar;

	/**
		Which backend a renderer actually took.
	**/
	@:native("mdd_renderer_name")
	public static function rendererName(renderer:cpp.Star<Canvas>):cpp.ConstCharStar;

	/**
		Turns vsync on or off, which SDL3 does after creation rather than at it.
	**/
	@:native("mdd_renderer_vsync")
	public static function rendererVsync(renderer:cpp.Star<Canvas>):Int;

	/**
		Fills the target with a colour.
	**/
	@:native("mdd_render_clear")
	public static function renderClear(renderer:cpp.Star<Canvas>, r:Single, g:Single, b:Single,
		a:Single):Void;

	/**
		Shows what was drawn. Presenting a frame that was not drawn shows the buffer contents from two presents ago, so an idle frame must skip this rather than present nothing.
	**/
	@:native("mdd_render_present")
	public static function renderPresent(renderer:cpp.Star<Canvas>):Void;

	/**
		Limits drawing to a rectangle.
	**/
	@:native("mdd_set_clip")
	public static function setClip(renderer:cpp.Star<Canvas>, x:Int, y:Int, width:Int,
		height:Int):Void;

	/**
		Takes that limit off.
	**/
	@:native("mdd_clear_clip")
	public static function clearClip(renderer:cpp.Star<Canvas>):Void;

	/**
		Whether the desktop asks for reduced motion.
	**/
	@:native("mdd_reduce_motion")
	public static function reduceMotion():Int;

	/**
		Sleeps, asking the operating system for a fine enough scheduler tick first.
	**/
	@:native("mdd_sleep")
	public static function sleep(seconds:Float):Void;

	/**
		Gives the window an icon from raw pixels.
	**/
	@:native("mdd_window_icon")
	public static function windowIcon(window:cpp.Star<Window>, pixels:cpp.RawConstPointer<cpp.UInt8>,
		width:Int, height:Int):Void;

	/**
		Puts up a system message box.
	**/
	@:native("mdd_message")
	public static function message(title:cpp.ConstCharStar, said:cpp.ConstCharStar):Void;

	/**
		The same box, marked as a fault rather than as something ordinary.
	**/
	@:native("mdd_fault")
	public static function fault(title:cpp.ConstCharStar, said:cpp.ConstCharStar):Void;

	/**
		Puts up a system message box with up to four answers, the first what the return key gives
		and the last what escape gives. An empty answer is left out. It works before there is a
		window.

		@param title The box title.
		@param said What it says.
		@param first The first answer.
		@param second The second, or an empty string.
		@param third The third, or an empty string.
		@param fourth The fourth, or an empty string.
		@param fault Nonzero to mark it as a fault.
		@return Which answer was chosen, from nought, or -1 where the box could not be shown.
	**/
	@:native("mdd_ask")
	public static function ask(title:cpp.ConstCharStar, said:cpp.ConstCharStar,
		first:cpp.ConstCharStar, second:cpp.ConstCharStar, third:cpp.ConstCharStar,
		fourth:cpp.ConstCharStar, fault:Int):Int;

	/**
		Seconds since SDL started, at full precision rather than rounded to milliseconds.
	**/
	@:native("mdd_ticks")
	public static function ticks():Float;

	/**
		Takes the next event, or answers nought where none is waiting.
	**/
	@:native("mdd_poll_event")
	public static function pollEvent(out:cpp.RawPointer<Event>):Int;

	/**
		The text a typing event carried.
	**/
	@:native("mdd_event_text")
	public static function eventText(event:cpp.RawConstPointer<Event>):cpp.ConstCharStar;

	/**
		Which modifier keys are held now.
	**/
	@:native("mdd_mods")
	public static function mods():Int;

	/**
		Where the pointer is, across.
	**/
	@:native("mdd_mouse_x")
	static function mouseX():Single;

	/**
		Where the pointer is, down.
	**/
	@:native("mdd_mouse_y")
	static function mouseY():Single;

	/**
		Puts text on the clipboard.
	**/
	@:native("mdd_clipboard_set")
	public static function setClipboard(text:cpp.ConstCharStar):Void;

	/**
		Takes text off it.
	**/
	@:native("mdd_clipboard_get")
	public static function clipboard():cpp.ConstCharStar;

	/**
		Hands a location to the desktop to open: a folder opens in the file manager and a
		web address in the browser.

		@param url A URL. On Windows a plain path is taken as well.
		@return Nonzero where the desktop took it.
	**/
	@:native("mdd_open_url")
	public static function openUrl(url:cpp.ConstCharStar):Int;

	/**
		Cursor: the ordinary arrow.
	**/
	public static inline final CURSOR_ARROW = 0;

	/**
		Cursor: an I-beam, over text that can be typed in.
	**/
	public static inline final CURSOR_TEXT = 1;

	/**
		Cursor: a double arrow across, over an edge that resizes sideways.
	**/
	public static inline final CURSOR_ACROSS = 2;

	/**
		Cursor: a double arrow down, over an edge that resizes up and down.
	**/
	public static inline final CURSOR_DOWN = 3;

	/**
		Cursor: a pointing hand, over something that answers a click.
	**/
	public static inline final CURSOR_HAND = 4;

	/**
		Cursor: the four pointed arrow, over something being dragged about.
	**/
	public static inline final CURSOR_MOVE = 5;

	/**
		Puts a cursor shape on the window.

		The shapes are made the first time each is asked for and kept, and asking
		for the one already showing does nothing, so this is cheap to call every
		time the pointer moves.

		@param shape Which shape, one of the CURSOR_ values.
	**/
	@:native("mdd_cursor_set")
	public static function cursor(shape:Int):Void;

	/**
		Frees every cursor shape that was made.
	**/
	@:native("mdd_cursor_free")
	public static function freeCursors():Void;

	/**
		Moves the pointer to a point in a window. The move arrives back as an ordinary motion
		event at that point.

		@param window The window.
		@param x Where, across, in points.
		@param y Where, down, in points.
	**/
	@:native("mdd_pointer_warp")
	public static function warp(window:cpp.Star<Window>, x:Float, y:Float):Void;
}
