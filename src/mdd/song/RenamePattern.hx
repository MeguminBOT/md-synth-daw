package mdd.song;

final class RenamePattern implements Command {
	final which:Int;
	final name:String;

	var was:String = "";

	public function new(which:Int, name:String) {
		this.which = which;
		this.name = name;
	}

	public function apply(song:Song):Void {
		final pattern = song.patternAt(which);
		if (pattern == null) return;

		was = pattern.name;
		pattern.name = name;
	}

	public function revert(song:Song):Void {
		final pattern = song.patternAt(which);
		if (pattern != null) pattern.name = was;
	}

	public function label():String {
		return "rename a pattern";
	}
}
