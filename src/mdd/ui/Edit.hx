package mdd.ui;

/**
	The editing commands a control can be sent, whichever key or menu entry sent them.
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
		Copy the selection and lay the copy immediately after it.
	**/
	public static inline final DOUBLE = 4;

	/**
		Private: this is a set of values, not a thing to build.
	**/
	function new() {}
}
