package mdd.song.edit;

final class IconTrack implements Command {
	final at:Int;
	final icon:Int;

	var was:Int = -1;

	public function new(at:Int, icon:Int) {
		this.at = at;
		this.icon = icon;
	}

	public function apply(song:Song):Void {
		if (at < 0 || at >= song.tracks.length) return;

		was = song.tracks[at].icon;
		song.tracks[at].icon = icon;
	}

	public function revert(song:Song):Void {
		if (at < 0 || at >= song.tracks.length) return;

		song.tracks[at].icon = was;
	}

	public function label():String {
		return "give a track an icon";
	}
}
