package mdd.song;

final class AddPattern implements Command {
	final pattern:Pattern;

	public function new(pattern:Pattern) {
		this.pattern = pattern;
	}

	public function apply(song:Song):Void {
		song.patterns.push(pattern);
	}

	public function revert(song:Song):Void {
		song.patterns.remove(pattern);
	}

	public function label():String {
		return "add a pattern";
	}
}
