package mdd.song.edit;

final class ShiftSong implements Command {
	final by:Int;

	public function new(by:Int) {
		this.by = by;
	}

	public function apply(song:Song):Void {
		song.shift(by);
	}

	public function revert(song:Song):Void {
		song.shift(-by);
	}

	public function label():String {
		return by < 0 ? "nudge the song earlier" : "nudge the song later";
	}
}
