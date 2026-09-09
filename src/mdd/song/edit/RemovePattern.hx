package mdd.song.edit;

/**
	Removes a pattern and every clip that played it.

	One step on the undo stack. `apply` does it and `revert` puts the song back
	exactly as it was, which is why anything it overwrites is kept here.
**/
final class RemovePattern implements Command {
	final at:Int;

	var pattern:Null<Pattern> = null;
	var clips:Array<Clip> = [];
	var tracks:Array<Track> = [];
	var places:Array<Int> = [];

	/**
		Records what to do. Nothing changes until `apply` is called.

		@param at Which one, by index.
	**/
	public function new(at:Int) {
		this.at = at;
	}

	/**
		Does it, keeping whatever `revert` will need to put back.

		@param song The song to act on.
	**/
	public function apply(song:Song):Void {
		if (at < 0 || at >= song.patterns.length) return;

		pattern = song.patterns[at];
		clips = [];
		tracks = [];
		places = [];

		for (track in song.tracks) {
			var index = 0;

			while (index < track.clips.length) {
				final clip = track.clips[index];

				if (clip.pattern == at) {
					clips.push(clip);
					tracks.push(track);
					places.push(index);
					track.clips.remove(clip);
					continue;
				}

				if (clip.pattern > at) clip.pattern--;
				index++;
			}
		}

		song.patterns.remove(pattern);
	}

	/**
		Puts the song back as it was.

		@param song The song to act on.
	**/
	public function revert(song:Song):Void {
		if (pattern == null) return;

		song.patterns.insert(at, pattern);

		for (track in song.tracks) {
			for (clip in track.clips) {
				if (clip.pattern >= at) clip.pattern++;
			}
		}

		var index = clips.length;

		while (index-- > 0) {
			tracks[index].clips.insert(places[index], clips[index]);
		}

		clips = [];
		tracks = [];
		places = [];
	}

	/**
		@return What the undo entry is called, in lower case.
	**/
	public function label():String {
		return "remove a pattern";
	}
}
