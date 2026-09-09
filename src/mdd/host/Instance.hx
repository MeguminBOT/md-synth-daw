package mdd.host;

@:include("instance.h")

/**
	One instance at a time: a named lock the second copy finds already taken, so
	opening a project hands it to the copy already running.
**/
extern class Instance {
	/**
		Takes the lock, or finds it already held.

		@param name The name to claim.
		@return Nonzero where this process took it.
	**/
	@:native("mdd_instance_claim")
	public static function claim(name:cpp.ConstCharStar):Int;

	/**
		@return Nonzero where this process holds it.
	**/
	@:native("mdd_instance_held")
	public static function held():Int;

	/**
		Gives the lock back.
	**/
	@:native("mdd_instance_release")
	public static function release():Void;
}
