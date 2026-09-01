package mdd.song;

final class AddNote implements Command {
	final pattern:Int;
	final part:Part;
	final note:Note;

	public function new(pattern:Int, part:Part, note:Note) {
		this.pattern = pattern;
		this.part = part;
		this.note = note;
	}

	public function apply(song:Song):Void {
		final held = song.patternAt(pattern);
		if (held != null) held.lane(part).add(note);
	}

	public function revert(song:Song):Void {
		final held = song.patternAt(pattern);
		if (held != null) held.lane(part).remove(note);
	}

	public function label():String {
		return "add a note";
	}
}
