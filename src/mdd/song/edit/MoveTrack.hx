package mdd.song.edit;

final class MoveTrack implements Command {
	final at:Int;
	final onto:Int;

	public function new(at:Int, onto:Int) {
		this.at = at;
		this.onto = onto;
	}

	public function apply(song:Song):Void {
		carries(song, at, onto);
	}

	public function revert(song:Song):Void {
		carries(song, onto, at);
	}

	static function carries(song:Song, from:Int, to:Int):Void {
		final tracks = song.tracks;

		if (from == to) return;
		if (from < 0 || from >= tracks.length) return;
		if (to < 0 || to >= tracks.length) return;

		final held = tracks[from];

		tracks.splice(from, 1);
		tracks.insert(to, held);
	}

	public function label():String {
		return "move a track";
	}
}
