package mdd.host;

@:include("discord.h")

/**
	Discord presence, speaking the local IPC socket directly.

	There is no vendored library because neither candidate could be one: the old client
	is archived, and the newer one is a closed binary whose licence binds
	redistribution. The protocol underneath both is a socket, an eight byte header and
	a JSON payload, which is less to carry than either dependency. Presence is a one
	way announcement and nothing else here needs Discord at all.
**/
extern class Discord {
	static inline final HANDSHAKE = 0;

	/**
		Opcode: an ordinary frame carrying JSON.
	**/
	public static inline final FRAME = 1;
	static inline final CLOSED = 2;
	static inline final PING = 3;
	static inline final PONG = 4;

	/**
		Connects to the local client, where one is running.

		@param application The application identifier to announce as.
		@return False where no client answered.
	**/
	@:native("mdd_discord_open")
	public static function open(application:cpp.ConstCharStar):Bool;

	/**
		Closes the connection.
	**/
	@:native("mdd_discord_shut")
	public static function shut():Void;

	/**
		@return Whether the socket is open.
	**/
	@:native("mdd_discord_live")
	public static function live():Bool;

	/**
		@return Whether the client has finished the handshake, so presence can be sent.
	**/
	@:native("mdd_discord_ready")
	public static function ready():Bool;

	/**
		Reads whatever the client has sent. Call once a frame.

		@return How many frames were read.
	**/
	@:native("mdd_discord_poll")
	public static function poll():Int;

	/**
		Sends one frame.

		@param opcode Which kind of frame.
		@param json Its payload.
		@return False where the socket would not take it.
	**/
	@:native("mdd_discord_write")
	public static function write(opcode:Int, json:cpp.ConstCharStar):Bool;

	/**
		@return Who the client is signed in as, or an empty string before the handshake.
	**/
	@:native("mdd_discord_user")
	public static function user():cpp.ConstCharStar;

	/**
		@return What went wrong last, or an empty string where nothing did.
	**/
	@:native("mdd_discord_fault")
	public static function fault():cpp.ConstCharStar;

	/**
		@return This process identifier, which presence has to carry.
	**/
	@:native("mdd_discord_pid")
	public static function pid():Int;

	/**
		@return Which socket the client was found on, for a report.
	**/
	@:native("mdd_discord_socket")
	public static function socket():Int;

	/**
		@return How many frames have been sent.
	**/
	@:native("mdd_discord_sent")
	public static function sent():Int;

	/**
		@return How many have been read.
	**/
	@:native("mdd_discord_took")
	public static function took():Int;
}
