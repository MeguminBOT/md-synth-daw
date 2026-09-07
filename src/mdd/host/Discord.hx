package mdd.host;

@:include("discord.h")
extern class Discord {
	static inline final HANDSHAKE = 0;
	public static inline final FRAME = 1;
	static inline final CLOSED = 2;
	static inline final PING = 3;
	static inline final PONG = 4;

	@:native("mdd_discord_open")
	public static function open(application:cpp.ConstCharStar):Bool;

	@:native("mdd_discord_shut")
	public static function shut():Void;

	@:native("mdd_discord_live")
	public static function live():Bool;

	@:native("mdd_discord_ready")
	public static function ready():Bool;

	@:native("mdd_discord_poll")
	public static function poll():Int;

	@:native("mdd_discord_write")
	public static function write(opcode:Int, json:cpp.ConstCharStar):Bool;

	@:native("mdd_discord_user")
	public static function user():cpp.ConstCharStar;

	@:native("mdd_discord_fault")
	public static function fault():cpp.ConstCharStar;

	@:native("mdd_discord_pid")
	public static function pid():Int;

	@:native("mdd_discord_socket")
	public static function socket():Int;

	@:native("mdd_discord_sent")
	public static function sent():Int;

	@:native("mdd_discord_took")
	public static function took():Int;
}
