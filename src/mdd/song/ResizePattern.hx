package mdd.song;

final class ResizePattern implements Command {
	final which:Int;
	final length:Int;

	var was:Int = 0;

	public function new(which:Int, length:Int) {
		this.which = which;
		this.length = length < 1 ? 1 : length;
	}

	public function apply(song:Song):Void {
		final pattern = song.patternAt(which);
		if (pattern == null) return;

		was = pattern.length;
		pattern.length = length;
	}

	public function revert(song:Song):Void {
		final pattern = song.patternAt(which);
		if (pattern != null) pattern.length = was;
	}

	public function label():String {
		return "resize a pattern";
	}
}
