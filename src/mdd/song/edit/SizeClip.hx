package mdd.song.edit;

/**
	Changes where a clip starts and how long it is.

	A start that moves takes how far into its pattern the clip begins along with it, so the music
	under the clip stays where it was and only how much of it shows changes. One step on the undo
	stack. `apply` does it and `revert` puts the song back exactly as it was, which is why anything
	it overwrites is kept here.
**/
final class SizeClip implements Command {
	final track:Int;
	final clip:Clip;
	final at:Int;
	final length:Int;

	var wasAt:Int = 0;
	var wasLong:Int = 0;
	var wasOffset:Int = 0;

	/**
		Records what to do. Nothing changes until `apply` is called.

		@param track Which track, by index.
		@param clip The clip.
		@param at Where it should start, in ticks, which is where it starts already for a clip
			resized from its end.
		@param length The new length, in ticks.
	**/
	public function new(track:Int, clip:Clip, at:Int, length:Int) {
		this.track = track;
		this.clip = clip;
		this.at = at;
		this.length = length;
	}

	/**
		Does it, keeping whatever `revert` will need to put back.

		@param song The song to act on.
	**/
	public function apply(song:Song):Void {
		wasAt = clip.at;
		wasLong = clip.length;
		wasOffset = clip.offset;

		clip.offset += at - clip.at;
		clip.at = at;
		clip.length = length < 1 ? 1 : length;
	}

	/**
		Puts the song back as it was.

		@param song The song to act on.
	**/
	public function revert(song:Song):Void {
		clip.at = wasAt;
		clip.length = wasLong;
		clip.offset = wasOffset;
	}

	/**
		@return What the undo entry is called, in lower case.
	**/
	public function label():String {
		return "resize a clip";
	}
}
