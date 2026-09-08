package mdd.song.edit;

final class MuteTrack implements Command {
	final at:Int;
	final muted:Bool;

	var was:Bool = false;

	public function new(at:Int, muted:Bool) {
		this.at = at;
		this.muted = muted;
	}

	public function apply(song:Song):Void {
		if (at < 0 || at >= song.tracks.length) return;

		was = song.tracks[at].muted;
		song.tracks[at].muted = muted;
	}

	public function revert(song:Song):Void {
		if (at < 0 || at >= song.tracks.length) return;

		song.tracks[at].muted = was;
	}

	public function label():String {
		return muted ? "mute a track" : "unmute a track";
	}
}
