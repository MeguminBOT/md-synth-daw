package mdd.song.edit;

final class ColourPattern implements Command {
	final which:Int;
	final colour:Int;

	var was:Int = -1;

	public function new(which:Int, colour:Int) {
		this.which = which;
		this.colour = colour;
	}

	public function apply(song:Song):Void {
		final pattern = song.patternAt(which);
		if (pattern == null) return;

		was = pattern.colour;
		pattern.colour = colour;
	}

	public function revert(song:Song):Void {
		final pattern = song.patternAt(which);
		if (pattern != null) pattern.colour = was;
	}

	public function label():String {
		return "colour a pattern";
	}
}
