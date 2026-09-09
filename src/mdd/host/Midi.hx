package mdd.host;

@:include("midi.h")

/**
	MIDI input: opening a port and taking the messages that arrive on it.

	Input only. Nothing here sends.
**/
extern class Midi {
	/**
		What `take` answers when nothing is waiting.
	**/
	public static inline final EMPTY = -1;

	/**
		@return How many input ports the machine has.
	**/
	@:native("mdd_midi_count")
	public static function count():Int;

	/**
		@param index Which port.
		@return What it is called.
	**/
	@:native("mdd_midi_name")
	public static function named(index:Int):cpp.ConstCharStar;

	/**
		Opens a port, closing whichever was open before.

		@param index Which port.
		@return False where it would not open.
	**/
	@:native("mdd_midi_open")
	public static function open(index:Int):Bool;

	/**
		Closes the open port.
	**/
	@:native("mdd_midi_close")
	public static function close():Void;

	/**
		@return Whether a port is open.
	**/
	@:native("mdd_midi_holding")
	public static function holding():Bool;

	/**
		Takes the oldest message waiting.

		@return The message packed into one value, or `EMPTY` where none is waiting.
	**/
	@:native("mdd_midi_take")
	public static function take():Int;

	/**
		@return How many messages were dropped because nothing took them in time.
	**/
	@:native("mdd_midi_lost")
	public static function lost():Int;
}
