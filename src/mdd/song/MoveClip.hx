package mdd.song;

final class MoveClip implements Command {
	final track:Int;
	final clip:Clip;
	final at:Int;
	final transpose:Int;

	var wasAt:Int = 0;
	var wasTranspose:Int = 0;

	public function new(track:Int, clip:Clip, at:Int, transpose:Int) {
		this.track = track;
		this.clip = clip;
		this.at = at;
		this.transpose = transpose;
	}

	public function apply(song:Song):Void {
		wasAt = clip.at;
		wasTranspose = clip.transpose;

		clip.at = at < 0 ? 0 : at;
		clip.transpose = transpose;
	}

	public function revert(song:Song):Void {
		clip.at = wasAt;
		clip.transpose = wasTranspose;
	}

	public function label():String {
		return "move a clip";
	}
}
