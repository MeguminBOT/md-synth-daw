package mdd.host;

@:include("audio.h")
@:native("MddDevice")

/**
	An open audio device, owned by the native side. Nothing here reads into it.
**/
extern class Device {}
