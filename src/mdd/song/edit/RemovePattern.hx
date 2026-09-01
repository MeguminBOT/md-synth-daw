package mdd.song.edit;

final class RemovePattern implements Command {
	final at:Int;

	var pattern:Null<Pattern> = null;
	var clips:Array<Clip> = [];
	var tracks:Array<Track> = [];
	var places:Array<Int> = [];

	public function new(at:Int) {
		this.at = at;
	}

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

	public function revert(song:Song):Void {
		if (pattern == null) return;

		song.patterns.insert(at, pattern);

		for (track in song.tracks) {
			for (clip in track.clips) {
				if (clip.pattern >= at) clip.pattern++;
			}
		}

		for (index in 0...clips.length) {
			tracks[index].clips.insert(places[index], clips[index]);
		}

		clips = [];
		tracks = [];
		places = [];
	}

	public function label():String {
		return "remove a pattern";
	}
}
