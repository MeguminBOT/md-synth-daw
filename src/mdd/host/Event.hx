package mdd.host;

@:include("events.h")
@:structAccess
@:native("MddEvent")

/**
	One event, filled in by `Sdl.pollEvent`.

	It is a plain structure the native side writes into rather than something
	allocated per event, so polling costs nothing.
**/
extern class Event {
	/**
		Which event this is, one of the `EVENT_` values on `Sdl`.
	**/
	public var type:Int;

	/**
		Which window it belongs to.
	**/
	public var windowID:Int;

	/**
		The key, the button or the window field, by event.
	**/
	public var code:Int;

	/**
		A second number the event carries.
	**/
	public var value:Int;

	/**
		Which modifier keys were held.
	**/
	public var mods:Int;

	/**
		Where it happened, across.
	**/
	public var x:Single;

	/**
		Where it happened, down.
	**/
	public var y:Single;

	/**
		Builds an empty event to poll into.
	**/
	public function new();
}
