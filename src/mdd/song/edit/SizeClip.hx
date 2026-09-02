package mdd.song.edit;

final class SizeClip implements Command {
	final track:Int;
	final clip:Clip;
	final length:Int;

	var was:Int = 0;

	public function new(track:Int, clip:Clip, length:Int) {
		this.track = track;
		this.clip = clip;
		this.length = length;
	}

	public function apply(song:Song):Void {
		was = clip.length;
		clip.length = length < 1 ? 1 : length;
	}

	public function revert(song:Song):Void {
		clip.length = was;
	}

	public function label():String {
		return "resize a clip";
	}
}
