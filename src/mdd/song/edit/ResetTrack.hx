package mdd.song.edit;

/**
	Clears a track back to an empty one under a given name.

	One step on the undo stack. `apply` does it and `revert` puts the song back
	exactly as it was, which is why anything it overwrites is kept here.
**/
final class ResetTrack implements Command {
	final at:Int;
	final name:String;

	var was:String = "";
	var wasColour:Int = -1;
	var wasIcon:Int = -1;
	var wasMuted:Bool = false;

	final held:Array<Clip> = [];

	/**
		Records what to do. Nothing changes until `apply` is called.

		@param at Which one, by index.
		@param name The new name.
	**/
	public function new(at:Int, name:String) {
		this.at = at;
		this.name = name;
	}

	/**
		Does it, keeping whatever `revert` will need to put back.

		@param song The song to act on.
	**/
	public function apply(song:Song):Void {
		if (at < 0 || at >= song.tracks.length) return;

		final track = song.tracks[at];

		was = track.name;
		wasColour = track.colour;
		wasIcon = track.icon;
		wasMuted = track.muted;

		held.resize(0);
		for (clip in track.clips) held.push(clip);

		track.name = name;
		track.colour = -1;
		track.icon = -1;
		track.muted = false;
		track.clips.resize(0);
	}

	/**
		Puts the song back as it was.

		@param song The song to act on.
	**/
	public function revert(song:Song):Void {
		if (at < 0 || at >= song.tracks.length) return;

		final track = song.tracks[at];

		track.name = was;
		track.colour = wasColour;
		track.icon = wasIcon;
		track.muted = wasMuted;

		track.clips.resize(0);
		for (clip in held) track.clips.push(clip);
	}

	/**
		@return What the undo entry is called, in lower case.
	**/
	public function label():String {
		return "reset a track";
	}
}
