package mdd.ui;

/**
	Something with a value inside a span: a scroll bar, a slider, a knob.

	The value is a read only property rather than a variable, because an interface
	cannot expose a variable to an `@:unreflective` implementer on hxcpp: reading a
	plain public variable through the interface answers null, while reading the same
	field on the concrete type answers the value, and nothing warns. A property
	dispatches as an ordinary method, so the implementer provides a non-inline getter.
**/
interface Range {
	/**
		Where it sits now.
	**/
	public var value(get, never):Int;

	/**
		Moves it, clamped to the span.

		@param next Where to move it to.
	**/
	public function set(next:Int):Void;

	/**
		@return How far it can move.
	**/
	public function span():Int;

	/**
		@return How much of the whole is visible, 0 to 1, which is what sizes a scroll bar thumb.
	**/
	public function share():Float;
}
