package mdd.song.edit;

/**
	Gives a track an icon.

	One step on the undo stack. `apply` does it and `revert` puts the song back
	exactly as it was, which is why anything it overwrites is kept here.
**/
final class IconTrack implements Command {
	final at:Int;
	final icon:Int;

	var was:Int = -1;

	/**
		Records what to do. Nothing changes until `apply` is called.

		@param at Which one, by index.
		@param icon Which icon, by index.
	**/
	public function new(at:Int, icon:Int) {
		this.at = at;
		this.icon = icon;
	}

	/**
		Does it, keeping whatever `revert` will need to put back.

		@param song The song to act on.
	**/
	public function apply(song:Song):Void {
		if (at < 0 || at >= song.tracks.length) return;

		was = song.tracks[at].icon;
		song.tracks[at].icon = icon;
	}

	/**
		Puts the song back as it was.

		@param song The song to act on.
	**/
	public function revert(song:Song):Void {
		if (at < 0 || at >= song.tracks.length) return;

		song.tracks[at].icon = was;
	}

	/**
		@return What the undo entry is called, in lower case.
	**/
	public function label():String {
		return "give a track an icon";
	}
}
