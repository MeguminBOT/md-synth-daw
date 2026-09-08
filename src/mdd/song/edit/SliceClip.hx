package mdd.song.edit;

final class SliceClip implements Command {
	final track:Int;
	final clip:Clip;
	final at:Int;

	var rest:Null<Clip> = null;
	var was:Int = 0;

	public function new(track:Int, clip:Clip, at:Int) {
		this.track = track;
		this.clip = clip;
		this.at = at;
	}

	public static function splits(clip:Clip, at:Int):Bool {
		return !clip.drawn() && at > clip.at && at < clip.ends();
	}

	public function apply(song:Song):Void {
		if (track < 0 || track >= song.tracks.length) return;
		if (!splits(clip, at)) return;

		was = clip.length;

		var made = rest;

		if (made == null) {
			made = new Clip(clip.pattern, at, was - (at - clip.at), clip.transpose,
				clip.offset + (at - clip.at));
			rest = made;
		}

		clip.length = at - clip.at;
		song.tracks[track].add(made);
	}

	public function revert(song:Song):Void {
		final made = rest;
		if (made == null) return;

		if (track >= 0 && track < song.tracks.length) song.tracks[track].remove(made);
		clip.length = was;
	}

	public function label():String {
		return "slice a clip";
	}
}
