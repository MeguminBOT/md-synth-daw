package mdd.host;

@:include("usage.h")
extern class Usage {
	@:native("mdd_usage_start")
	public static function start():Void;

	@:native("mdd_usage_stop")
	public static function stop():Void;

	@:native("mdd_usage_cpu")
	public static function cpu():Float;

	@:native("mdd_usage_ram")
	public static function ram():Float;

	@:native("mdd_usage_gpu")
	public static function gpu():Float;
}
