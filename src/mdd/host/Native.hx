package mdd.host;

@:keep
@:buildXml('<include name="${MDDBUILD}" />')

/**
	The hook that pulls the native sources into the build.

	It does nothing at run time. Calling `ready` once is what stops the linker dropping
	everything the extern classes bind to.
**/
class Native {
	/**
		Call once at start. It does nothing, deliberately.
	**/
	public static function ready():Void {}
}
