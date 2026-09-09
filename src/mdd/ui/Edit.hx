package mdd.ui;

/**
	The four editing commands a control can be sent, whichever key or menu entry sent
	them.
**/
@:unreflective
final class Edit {
	/**
		Select everything.
	**/
	public static inline final ALL = 0;

	/**
		Copy the selection.
	**/
	public static inline final COPY = 1;

	/**
		Cut it.
	**/
	public static inline final CUT = 2;

	/**
		Paste over it.
	**/
	public static inline final PASTE = 3;

	/**
		Private: this is a set of values, not a thing to build.
	**/
	function new() {}
}
