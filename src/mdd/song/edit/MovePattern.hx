package mdd.song.edit;

/**
	Moves a pattern onto another part.

	One step on the undo stack. `apply` does it and `revert` puts the song back
	exactly as it was, which is why anything it overwrites is kept here.
**/
final class MovePattern implements Command {
	final at:Int;
	final part:Int;

	var was:Int = -1;
	var belonged:Int = -1;

	final moved:Array<Note> = [];
	final lines:Array<Automation> = [];

	/**
		Records what to do. Nothing changes until `apply` is called.

		@param at Which one, by index.
		@param part Which part of the pattern.
	**/
	public function new(at:Int, part:Int) {
		this.at = at;
		this.part = part;
	}

	/**
		Does it, keeping whatever `revert` will need to put back.

		@param song The song to act on.
	**/
	public function apply(song:Song):Void {
		final pattern = song.patterns[at];
		if (pattern == null) return;

		belonged = pattern.part;
		was = pattern.part < 0 ? held(pattern) : pattern.part;

		moves(pattern, was, part);

		pattern.part = part;
	}

	/**
		Puts the song back as it was.

		@param song The song to act on.
	**/
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

	/**
		@return What the undo entry is called, in lower case.
	**/
	public function label():String {
		return "move the pattern to another channel";
	}
}
