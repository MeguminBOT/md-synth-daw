package mdd.song.edit;

/**
	Grows the song to a number of tracks, appending the ones it lacks.

	One step on the undo stack. `apply` does it and `revert` puts the song back
	exactly as it was, which is why anything it overwrites is kept here.
**/
final class AddTrack implements Command {
	final upto:Int;

	var added:Int = 0;

	/**
		Records what to do. Nothing changes until `apply` is called.

		@param upto How many tracks the song should end up with.
	**/
	public function new(upto:Int) {
		this.upto = upto;
	}

	/**
		Does it, keeping whatever `revert` will need to put back.

		@param song The song to act on.
	**/
	public function apply(song:Song):Void {
		added = 0;

		while (song.tracks.length <= upto) {
			song.track(new Track("track " + (song.tracks.length + 1)));
			added++;
		}
	}

	/**
		Puts the song back as it was.

		@param song The song to act on.
	**/
	public function revert(song:Song):Void {
		var left = added;

		while (left > 0 && song.tracks.length > 0) {
			song.tracks.pop();
			left--;
		}

		added = 0;
	}

	/**
		@return What the undo entry is called, in lower case.
	**/
	public function label():String {
		return "add a track";
	}
}
