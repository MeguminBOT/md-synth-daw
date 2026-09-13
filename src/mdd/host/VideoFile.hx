package mdd.host;

@:include("video.h")
@:native("MddVideo")

/**
	A WebM file being written, owned by the native side until `Video.close` frees it.
**/
extern class VideoFile {}
