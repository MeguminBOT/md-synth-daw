package mdd.host;

@:include("window.h")
@:include("events.h")
extern class Sdl {
	public static inline final EVENT_NONE = 0;
	public static inline final EVENT_QUIT = 1;
	public static inline final EVENT_KEY_DOWN = 2;
	public static inline final EVENT_KEY_UP = 3;
	public static inline final EVENT_MOUSE_MOVE = 4;
	public static inline final EVENT_MOUSE_DOWN = 5;
	public static inline final EVENT_MOUSE_UP = 6;
	public static inline final EVENT_MOUSE_WHEEL = 7;
	public static inline final EVENT_TEXT = 8;
	public static inline final EVENT_WINDOW_CLOSE = 9;
	public static inline final EVENT_WINDOW_RESIZED = 10;
	public static inline final EVENT_WINDOW_FOCUS_LOST = 11;
	public static inline final EVENT_WINDOW_FOCUS_GAINED = 12;
	public static inline final EVENT_WINDOW_SCALE_CHANGED = 13;
	public static inline final EVENT_WINDOW_EXPOSED = 14;
	public static inline final EVENT_DROP_FILE = 15;

	public static inline final MOD_NONE = 0;
	public static inline final MOD_SHIFT = 1;
	public static inline final MOD_CTRL = 2;
	public static inline final MOD_ALT = 4;
	public static inline final MOD_GUI = 8;

	public static inline final BUTTON_LEFT = 1;
	public static inline final BUTTON_MIDDLE = 2;
	public static inline final BUTTON_RIGHT = 3;

	@:native("mdd_sdl_init")
	public static function init():Int;

	@:native("mdd_sdl_quit")
	public static function quit():Void;

	@:native("mdd_sdl_error")
	public static function error():cpp.ConstCharStar;

	@:native("mdd_window_create")
	public static function createWindow(title:cpp.ConstCharStar, width:Int, height:Int,
		resizable:Int, highDpi:Int):cpp.Star<Window>;

	@:native("mdd_window_destroy")
	public static function destroyWindow(window:cpp.Star<Window>):Void;

	@:native("mdd_window_id")
	public static function windowID(window:cpp.Star<Window>):Int;

	@:native("mdd_window_set_title")
	public static function setWindowTitle(window:cpp.Star<Window>, title:cpp.ConstCharStar):Void;

	@:native("mdd_window_width")
	public static function windowWidth(window:cpp.Star<Window>):Int;

	@:native("mdd_window_height")
	public static function windowHeight(window:cpp.Star<Window>):Int;

	@:native("mdd_window_pixel_width")
	public static function windowPixelWidth(window:cpp.Star<Window>):Int;

	@:native("mdd_window_pixel_height")
	public static function windowPixelHeight(window:cpp.Star<Window>):Int;

	@:native("mdd_window_set_size")
	public static function setWindowSize(window:cpp.Star<Window>, width:Int, height:Int):Void;

	@:native("mdd_window_set_minimum_size")
	public static function setWindowMinimumSize(window:cpp.Star<Window>, width:Int,
		height:Int):Void;

	@:native("mdd_window_set_fullscreen")
	public static function setWindowFullscreen(window:cpp.Star<Window>, on:Int):Void;

	@:native("mdd_window_show")
	public static function showWindow(window:cpp.Star<Window>):Void;

	@:native("mdd_window_maximise")
	public static function maximiseWindow(window:cpp.Star<Window>):Void;

	@:native("mdd_window_maximised")
	public static function windowMaximised(window:cpp.Star<Window>):Int;

	@:native("mdd_window_display_scale")
	public static function windowDisplayScale(window:cpp.Star<Window>):Single;

	@:native("mdd_display_pixel_density")
	public static function pixelDensity(window:cpp.Star<Window>):Single;

	@:native("mdd_render_output_width")
	public static function outputWidth(renderer:cpp.Star<Canvas>):Int;

	@:native("mdd_render_output_height")
	public static function outputHeight(renderer:cpp.Star<Canvas>):Int;

	@:native("mdd_display_refresh")
	public static function displayRefresh(window:cpp.Star<Window>):Single;

	@:native("mdd_text_input_start")
	public static function startTextInput(window:cpp.Star<Window>):Void;

	@:native("mdd_text_input_stop")
	public static function stopTextInput(window:cpp.Star<Window>):Void;

	@:native("mdd_renderer_create")
	public static function createRenderer(window:cpp.Star<Window>, vsync:Int):cpp.Star<Canvas>;

	@:native("mdd_renderer_destroy")
	public static function destroyRenderer(renderer:cpp.Star<Canvas>):Void;

	@:native("mdd_renderer_name")
	public static function rendererName(renderer:cpp.Star<Canvas>):cpp.ConstCharStar;

	@:native("mdd_renderer_vsync")
	public static function rendererVsync(renderer:cpp.Star<Canvas>):Int;

	@:native("mdd_render_clear")
	public static function renderClear(renderer:cpp.Star<Canvas>, r:Single, g:Single, b:Single,
		a:Single):Void;

	@:native("mdd_render_present")
	public static function renderPresent(renderer:cpp.Star<Canvas>):Void;

	@:native("mdd_set_clip")
	public static function setClip(renderer:cpp.Star<Canvas>, x:Int, y:Int, width:Int,
		height:Int):Void;

	@:native("mdd_clear_clip")
	public static function clearClip(renderer:cpp.Star<Canvas>):Void;

	@:native("mdd_reduce_motion")
	public static function reduceMotion():Int;

	@:native("mdd_sleep")
	public static function sleep(seconds:Float):Void;

	@:native("mdd_window_icon")
	public static function windowIcon(window:cpp.Star<Window>, pixels:cpp.RawConstPointer<cpp.UInt8>,
		width:Int, height:Int):Void;

	@:native("mdd_message")
	public static function message(title:cpp.ConstCharStar, said:cpp.ConstCharStar):Void;

	@:native("mdd_ticks")
	public static function ticks():Float;

	@:native("mdd_poll_event")
	public static function pollEvent(out:cpp.RawPointer<Event>):Int;

	@:native("mdd_event_text")
	public static function eventText(event:cpp.RawConstPointer<Event>):cpp.ConstCharStar;

	@:native("mdd_mods")
	public static function mods():Int;

	@:native("mdd_mouse_x")
	public static function mouseX():Single;

	@:native("mdd_mouse_y")
	public static function mouseY():Single;

	@:native("mdd_clipboard_set")
	public static function setClipboard(text:cpp.ConstCharStar):Void;

	@:native("mdd_clipboard_get")
	public static function clipboard():cpp.ConstCharStar;
}
