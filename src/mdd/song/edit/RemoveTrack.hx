package mdd.song.edit;

final class RemoveTrack implements Command {
	final at:Int;

	var held:Null<Track> = null;

	public function new(at:Int) {
		this.at = at;
	}

	public function apply(song:Song):Void {
		if (at < 0 || at >= song.tracks.length) return;

		held = song.tracks[at];
		song.tracks.splice(at, 1);
	}

	public function revert(song:Song):Void {
		final track = held;
		if (track == null || at < 0 || at > song.tracks.length) return;

		song.tracks.insert(at, track);
		held = null;
	}

	public function label():String {
		return "remove a track";
	}
}
