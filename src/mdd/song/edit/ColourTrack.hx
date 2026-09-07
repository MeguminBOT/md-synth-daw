package mdd.song.edit;

final class ColourTrack implements Command {
	final at:Int;
	final colour:Int;

	var was:Int = -1;

	public function new(at:Int, colour:Int) {
		this.at = at;
		this.colour = colour;
	}

	public function apply(song:Song):Void {
		if (at < 0 || at >= song.tracks.length) return;

		was = song.tracks[at].colour;
		song.tracks[at].colour = colour;
	}

	public function revert(song:Song):Void {
		if (at < 0 || at >= song.tracks.length) return;

		song.tracks[at].colour = was;
	}

	public function label():String {
		return "colour a track";
	}
}
