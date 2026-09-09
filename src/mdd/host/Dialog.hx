package mdd.host;

@:include("dialog.h")

/**
	The system file dialogs.

	A dialog is opened and then asked for its state on later frames rather than
	blocking, so the interface keeps drawing and the audio keeps playing while one is
	open.
**/
extern class Dialog {
	/**
		State: still open.
	**/
	public static inline final WAITING = 0;

	/**
		State: a path was picked.
	**/
	public static inline final CHOSEN = 1;
	static inline final CANCELLED = 2;

	/**
		State: closed with nothing picked.
	**/
	public static inline final FAILED = 3;

	/**
		Opens a dialog for choosing a file to read.

		@param window The window it belongs to.
		@param label What the dialog is called.
		@param suffix The file suffix to filter by.
		@param where The folder to start in.
		@return The open dialog, to be asked for its state later.
	**/
	@:native("mdd_dialog_open")
	public static function open(window:cpp.Star<Window>, label:cpp.ConstCharStar,
		suffix:cpp.ConstCharStar, where:cpp.ConstCharStar):cpp.Star<Chooser>;

	/**
		Opens a dialog for choosing where to write.

		@param window The window it belongs to.
		@param label What the dialog is called.
		@param suffix The file suffix to filter by.
		@param where The folder to start in.
		@return The open dialog.
	**/
	@:native("mdd_dialog_save")
	public static function save(window:cpp.Star<Window>, label:cpp.ConstCharStar,
		suffix:cpp.ConstCharStar, where:cpp.ConstCharStar):cpp.Star<Chooser>;

	/**
		Opens a dialog for choosing a folder.

		@param window The window it belongs to.
		@param where The folder to start in.
		@return The open dialog.
	**/
	@:native("mdd_dialog_folder")
	public static function folder(window:cpp.Star<Window>,
		where:cpp.ConstCharStar):cpp.Star<Chooser>;

	/**
		@param dialog An open dialog.
		@return `WAITING`, `CHOSEN` or `FAILED`.
	**/
	@:native("mdd_dialog_state")
	public static function state(dialog:cpp.Star<Chooser>):Int;

	/**
		@param dialog A dialog that has been chosen.
		@return The path that was picked.
	**/
	@:native("mdd_dialog_path")
	public static function path(dialog:cpp.Star<Chooser>):cpp.ConstCharStar;

	/**
		Closes a dialog and gives its memory back.

		@param dialog The dialog.
	**/
	@:native("mdd_dialog_close")
	public static function close(dialog:cpp.Star<Chooser>):Void;
}
