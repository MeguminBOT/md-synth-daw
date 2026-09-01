package mdd.song;

@:unreflective
final class Lane {
	public var part(default, null):Part;
	public final notes:Array<Note> = [];
	public final automation:Array<Automation> = [];

	public function new(part:Part) {
		this.part = part;
	}

	public function add(note:Note):Note {
		var at = notes.length;
		while (at > 0 && notes[at - 1].at > note.at) at--;

		notes.insert(at, note);
		return note;
	}

	public function remove(note:Note):Bool {
		return notes.remove(note);
	}

	public function sort():Void {
		for (i in 1...notes.length) {
			final note = notes[i];
			var at = i;

			while (at > 0 && after(notes[at - 1], note)) {
				notes[at] = notes[at - 1];
				at--;
			}

			notes[at] = note;
		}
	}

	static inline function after(a:Note, b:Note):Bool {
		return a.at != b.at ? a.at > b.at : a.pitch > b.pitch;
	}

	public function longest():Int {
		var most = 0;
		for (note in notes) if (note.ends() > most) most = note.ends();
		return most;
	}
}
