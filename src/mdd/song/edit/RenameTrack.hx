package mdd.song.edit;

final class RenameTrack implements Command {
	final at:Int;
	final name:String;

	var was:String = "";

	public function new(at:Int, name:String) {
		this.at = at;
		this.name = name;
	}

	public function apply(song:Song):Void {
		if (at < 0 || at >= song.tracks.length) return;

		was = song.tracks[at].name;
		song.tracks[at].name = name;
	}

	public function revert(song:Song):Void {
		if (at < 0 || at >= song.tracks.length) return;

		song.tracks[at].name = was;
	}

	public function label():String {
		return "rename a track";
	}
}
