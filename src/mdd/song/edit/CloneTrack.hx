package mdd.song.edit;

final class CloneTrack implements Command {
	final at:Int;

	var made:Int = -1;

	public function new(at:Int) {
		this.at = at;
	}

	public function apply(song:Song):Void {
		if (at < 0 || at >= song.tracks.length) return;

		final from = song.tracks[at];
		final held = new Track(from.name);

		held.colour = from.colour;
		held.icon = from.icon;
		held.muted = from.muted;

		for (clip in from.clips) held.add(clip.copy());

		made = at + 1;
		song.tracks.insert(made, held);
	}

	public function revert(song:Song):Void {
		if (made < 0 || made >= song.tracks.length) return;

		song.tracks.splice(made, 1);
		made = -1;
	}

	public function label():String {
		return "clone a track";
	}
}
