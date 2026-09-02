package mdd.song.edit;

final class AddTrack implements Command {
	final upto:Int;

	var added:Int = 0;

	public function new(upto:Int) {
		this.upto = upto;
	}

	public function apply(song:Song):Void {
		added = 0;

		while (song.tracks.length <= upto) {
			song.track(new Track("track " + (song.tracks.length + 1)));
			added++;
		}
	}

	public function revert(song:Song):Void {
		var left = added;

		while (left > 0 && song.tracks.length > 0) {
			song.tracks.pop();
			left--;
		}

		added = 0;
	}

	public function label():String {
		return "add a track";
	}
}
