package mdd.host;

@:include("instance.h")
extern class Instance {
	@:native("mdd_instance_claim")
	public static function claim(name:cpp.ConstCharStar):Int;

	@:native("mdd_instance_held")
	public static function held():Int;

	@:native("mdd_instance_release")
	public static function release():Void;
}
