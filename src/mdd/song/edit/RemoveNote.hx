package mdd.song.edit;

final class RemoveNote implements Command {
	final pattern:Int;
	final part:Part;
	final note:Note;

	var wasLength:Int = 0;

	public function new(pattern:Int, part:Part, note:Note) {
		this.pattern = pattern;
		this.part = part;
		this.note = note;
	}

	public function apply(song:Song):Void {
		final held = song.patternAt(pattern);
		if (held == null) return;

		held.lane(part).remove(note);
		wasLength = held.fits(song.tempo.ppqn * 4);
	}

	public function revert(song:Song):Void {
		final held = song.patternAt(pattern);
		if (held == null) return;

		held.lane(part).add(note);
		held.length = wasLength;
	}

	public function label():String {
		return "remove a note";
	}
}
