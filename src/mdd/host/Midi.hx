package mdd.host;

@:include("midi.h")
extern class Midi {
	public static inline final EMPTY = -1;

	@:native("mdd_midi_count")
	public static function count():Int;

	@:native("mdd_midi_name")
	public static function named(index:Int):cpp.ConstCharStar;

	@:native("mdd_midi_open")
	public static function open(index:Int):Bool;

	@:native("mdd_midi_close")
	public static function close():Void;

	@:native("mdd_midi_holding")
	public static function holding():Bool;

	@:native("mdd_midi_take")
	public static function take():Int;

	@:native("mdd_midi_lost")
	public static function lost():Int;
}
