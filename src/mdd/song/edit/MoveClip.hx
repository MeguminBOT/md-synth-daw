package mdd.song.edit;

final class MoveClip implements Command {
	final track:Int;
	final onto:Int;
	final clip:Clip;
	final at:Int;
	final transpose:Int;

	var wasAt:Int = 0;
	var wasTranspose:Int = 0;

	public function new(track:Int, clip:Clip, at:Int, transpose:Int, onto:Int = -1) {
		this.track = track;
		this.onto = onto < 0 ? track : onto;
		this.clip = clip;
		this.at = at;
		this.transpose = transpose;
	}

	public function apply(song:Song):Void {
		wasAt = clip.at;
		wasTranspose = clip.transpose;

		clip.at = at < 0 ? 0 : at;
		clip.transpose = transpose;

		carries(song, track, onto);
	}

	public function revert(song:Song):Void {
		clip.at = wasAt;
		clip.transpose = wasTranspose;

		carries(song, onto, track);
	}

	function carries(song:Song, from:Int, to:Int):Void {
		if (from == to) return;
		if (from < 0 || from >= song.tracks.length) return;
		if (to < 0 || to >= song.tracks.length) return;

		song.tracks[from].remove(clip);
		song.tracks[to].add(clip);
	}

	public function label():String {
		return "move a clip";
	}
}
