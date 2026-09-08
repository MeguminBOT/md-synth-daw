package mdd.song.edit;

final class InsertTrack implements Command {
	final at:Int;
	final name:String;

	var made:Int = -1;

	public function new(at:Int, name:String) {
		this.at = at;
		this.name = name;
	}

	public function apply(song:Song):Void {
		if (at < 0 || at > song.tracks.length) return;

		made = at;
		song.tracks.insert(made, new Track(name));
	}

	public function revert(song:Song):Void {
		if (made < 0 || made >= song.tracks.length) return;

		song.tracks.splice(made, 1);
		made = -1;
	}

	public function label():String {
		return "insert a track";
	}
}
