package mdd.song;

@:unreflective
final class Lane {
	public static inline final FLOOR = 1536;

	public var part(default, null):Part;
	public final notes:Array<Note> = [];

	var held:Int = 0;
	public final automation:Array<Automation> = [];

	public function new(part:Part) {
		this.part = part;
	}

	public var reach(get, never):Int;

	function get_reach():Int {
		return held < FLOOR ? FLOOR : held;
	}

	public function grow(length:Int):Void {
		if (length > held) held = length;
	}

	public function add(note:Note):Note {
		var at = notes.length;
		while (at > 0 && notes[at - 1].at > note.at) at--;

		notes.insert(at, note);
		grow(note.length);

		return note;
	}

	public function remove(note:Note):Bool {
		return notes.remove(note);
	}

	public function sort():Void {
		held = 0;
		for (note in notes) grow(note.length);

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
