package mdd.song.edit;

/**
	Recolours a track.

	One step on the undo stack. `apply` does it and `revert` puts the song back
	exactly as it was, which is why anything it overwrites is kept here.
**/
final class ColourTrack implements Command {
	final at:Int;
	final colour:Int;

	var was:Int = -1;

	/**
		Records what to do. Nothing changes until `apply` is called.

		@param at Which one, by index.
		@param colour The colour, packed as the theme packs one.
	**/
	public function new(at:Int, colour:Int) {
		this.at = at;
		this.colour = colour;
	}

	/**
		Does it, keeping whatever `revert` will need to put back.

		@param song The song to act on.
	**/
	public function apply(song:Song):Void {
		if (at < 0 || at >= song.tracks.length) return;

		was = song.tracks[at].colour;
		song.tracks[at].colour = colour;
	}

	/**
		Puts the song back as it was.

		@param song The song to act on.
	**/
	public function revert(song:Song):Void {
		if (at < 0 || at >= song.tracks.length) return;

		song.tracks[at].colour = was;
	}

	/**
		@return What the undo entry is called, in lower case.
	**/
	public function label():String {
		return "colour a track";
	}
}
