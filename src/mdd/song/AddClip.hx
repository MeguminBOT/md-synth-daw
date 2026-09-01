package mdd.song;

final class AddClip implements Command {
	final track:Int;
	final clip:Clip;

	public function new(track:Int, clip:Clip) {
		this.track = track;
		this.clip = clip;
	}

	public function apply(song:Song):Void {
		if (track >= 0 && track < song.tracks.length) song.tracks[track].add(clip);
	}

	public function revert(song:Song):Void {
		if (track >= 0 && track < song.tracks.length) song.tracks[track].remove(clip);
	}

	public function label():String {
		return "add a clip";
	}
}
