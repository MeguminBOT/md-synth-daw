package mdd.ui;

interface Range {
	public var value(get, never):Int;

	public function set(next:Int):Void;
	public function span():Int;
	public function share():Float;
}
