package mdd.host;

@:include("dialog.h")
@:native("MddDialog")

/**
	A file dialog that is still open. It is asked for its state rather than blocking.
**/
extern class Chooser {}
