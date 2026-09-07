package mdd.song.edit;

final class SizeNote implements Command {
	final pattern:Int;
	final part:Part;
	final note:Note;
	final length:Int;

	var was:Int = 0;
	var wasLength:Int = 0;

	public function new(pattern:Int, part:Part, note:Note, length:Int) {
		this.pattern = pattern;
		this.part = part;
		this.note = note;
		this.length = length;
	}

	public function apply(song:Song):Void {
		was = note.length;
		note.length = length < 1 ? 1 : length;

		final held = song.patternAt(pattern);
		if (held == null) return;

		held.lane(part).grow(note.length);
		wasLength = held.fits(song.tempo.ppqn * 4);
	}

	public function revert(song:Song):Void {
		note.length = was;

		final held = song.patternAt(pattern);
		if (held == null) return;

		held.lane(part).grow(note.length);
		held.length = wasLength;
	}

	public function label():String {
		return "resize a note";
	}
}
