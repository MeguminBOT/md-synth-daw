package mdd.host;

@:include("instance.h")

/**
	One instance at a time: a named lock the second copy finds already taken, and a channel that
	copy hands what it was opened with over, so opening a project hands it to the copy already
	running.
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
		Gives the lock back, and stops listening for a second copy.
	**/
	@:native("mdd_instance_release")
	public static function release():Void;

	/**
		Starts listening for a second copy handing over what it was opened with. Only the copy
		holding the lock listens.

		@param name The name the lock was claimed under.
		@return Nonzero where it is listening.
	**/
	@:native("mdd_instance_listen")
	public static function listen(name:cpp.ConstCharStar):Int;

	/**
		Hands text to the copy holding the lock and lets it come to the front. Blocks, retrying,
		while that copy has the lock but is not listening yet.

		@param name The name the lock was claimed under.
		@param text What to hand over, which may be empty.
		@param wait The most milliseconds to keep retrying.
		@return Nonzero where the other copy took all of it.
	**/
	@:native("mdd_instance_hand")
	public static function hand(name:cpp.ConstCharStar, text:cpp.ConstCharStar, wait:Int):Int;

	/**
		Takes one handover a second copy made, without waiting for one to arrive. Cheap enough to
		call once a frame.

		@return How many bytes arrived, which may be nought, or -1 where nothing was handed over.
	**/
	@:native("mdd_instance_take")
	public static function take():Int;

	/**
		@return The text the last `take` read. Valid until the next one.
	**/
	@:native("mdd_instance_taken")
	public static function taken():cpp.ConstCharStar;

	/**
		@return How many arguments the process was started with, its own name included, where the
			platform keeps them as something other than UTF-8, or -1 where `Sys.args` is right.
	**/
	@:native("mdd_instance_arguments")
	public static function arguments():Int;

	/**
		@param index Which argument, nought being the program itself.
		@return It in UTF-8, or an empty string out of range. Valid until the next call.
	**/
	@:native("mdd_instance_argument")
	public static function argument(index:Int):cpp.ConstCharStar;
}
