package mdd.host;

@:include("events.h")
@:structAccess
@:native("MddEvent")
extern class Event {
	public var type:Int;
	public var windowID:Int;
	public var code:Int;
	public var value:Int;
	public var mods:Int;
	public var x:Single;
	public var y:Single;

	public function new();
}
