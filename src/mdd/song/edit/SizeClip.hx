package mdd.song.edit;

/**
	Changes how long a clip is.

	One step on the undo stack. `apply` does it and `revert` puts the song back
	exactly as it was, which is why anything it overwrites is kept here.
**/
final class SizeClip implements Command {
	final track:Int;
	final clip:Clip;
	final length:Int;

	var was:Int = 0;

	/**
		Records what to do. Nothing changes until `apply` is called.

		@param track Which track, by index.
		@param clip The clip.
		@param length The new length, in ticks.
	**/
	public function new(track:Int, clip:Clip, length:Int) {
		this.track = track;
		this.clip = clip;
		this.length = length;
	}

	/**
		Does it, keeping whatever `revert` will need to put back.

		@param song The song to act on.
	**/
	public function apply(song:Song):Void {
		was = clip.length;
		clip.length = length < 1 ? 1 : length;
	}

	/**
		Puts the song back as it was.

		@param song The song to act on.
	**/
	public function revert(song:Song):Void {
		clip.length = was;
	}

	/**
		@return What the undo entry is called, in lower case.
	**/
	public function label():String {
		return "resize a clip";
	}
}
