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
		The key, the button or the window field, by event. A move carries a mask of the
		buttons held instead, which is nought where the pointer is moving on its own.
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
		Where it happened, across, in the window's render pixels, the units the interface lays out
		in: a window on a Retina display has twice as many of those as it has window coordinates.
		A wheel turn carries how far it turned here instead.
	**/
	public var x:Single;

	/**
		Where it happened, down, in render pixels, or how far a wheel turned.
	**/
	public var y:Single;

	/**
		Builds an empty event to poll into.
	**/
	public function new();
}
