package mdd.song.edit;

final class MovePattern implements Command {
	final at:Int;
	final part:Int;

	var was:Int = -1;

	public function new(at:Int, part:Int) {
		this.at = at;
		this.part = part;
	}

	public function apply(song:Song):Void {
		final pattern = song.patterns[at];
		if (pattern == null) return;

		was = pattern.part < 0 ? held(pattern) : pattern.part;
		moves(pattern, was, part);

		pattern.part = part;
	}

	public function revert(song:Song):Void {
		final pattern = song.patterns[at];
		if (pattern == null || was < 0) return;

		moves(pattern, part, was);
		pattern.part = was;
	}

	static function held(pattern:Pattern):Int {
		for (index in 0...Part.COUNT) if (pattern.lanes[index].notes.length > 0) return index;
		return 0;
	}

	static function moves(pattern:Pattern, from:Int, to:Int):Void {
		if (from == to || from < 0 || to < 0) return;

		final one = pattern.lanes[from];
		final two = pattern.lanes[to];

		for (note in one.notes) two.notes.push(note);
		one.notes.resize(0);

		for (line in one.automation) two.automation.push(line);
		one.automation.resize(0);
	}

	public function label():String {
		return "move the pattern to another channel";
	}
}
