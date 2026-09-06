package mdd.song.edit;

final class MovePattern implements Command {
	final at:Int;
	final part:Int;

	var was:Int = -1;
	var belonged:Int = -1;

	final moved:Array<Note> = [];
	final lines:Array<Automation> = [];

	public function new(at:Int, part:Int) {
		this.at = at;
		this.part = part;
	}

	public function apply(song:Song):Void {
		final pattern = song.patterns[at];
		if (pattern == null) return;

		belonged = pattern.part;
		was = pattern.part < 0 ? held(pattern) : pattern.part;

		moves(pattern, was, part);

		pattern.part = part;
	}

	public function revert(song:Song):Void {
		final pattern = song.patterns[at];
		if (pattern == null || was < 0) return;

		if (was != part) {
			final one = pattern.lanes[was];
			final two = pattern.lanes[part];

			for (note in moved) {
				two.notes.remove(note);
				one.notes.push(note);
			}

			for (line in lines) {
				two.automation.remove(line);
				one.automation.push(line);
			}

			one.sort();
			two.sort();
		}

		moved.resize(0);
		lines.resize(0);

		pattern.part = belonged;
	}

	static function held(pattern:Pattern):Int {
		for (index in 0...Part.COUNT) if (pattern.lanes[index].notes.length > 0) return index;
		return 0;
	}

	function moves(pattern:Pattern, from:Int, to:Int):Void {
		moved.resize(0);
		lines.resize(0);

		if (from == to || from < 0 || to < 0) return;

		final one = pattern.lanes[from];
		final two = pattern.lanes[to];

		for (note in one.notes) {
			moved.push(note);
			two.notes.push(note);
		}

		one.notes.resize(0);

		for (line in one.automation) {
			lines.push(line);
			two.automation.push(line);
		}

		one.automation.resize(0);

		one.sort();
		two.sort();
	}

	public function label():String {
		return "move the pattern to another channel";
	}
}
