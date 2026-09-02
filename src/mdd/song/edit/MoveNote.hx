package mdd.song.edit;

final class MoveNote implements Command {
	final pattern:Int;
	final part:Part;
	final note:Note;
	final at:Int;
	final pitch:Int;
	final instrument:Int;

	var wasAt:Int = 0;
	var wasPitch:Int = 0;
	var wasInstrument:Int = 0;

	public function new(pattern:Int, part:Part, note:Note, at:Int, pitch:Int,
			instrument:Int = -2) {
		this.pattern = pattern;
		this.part = part;
		this.note = note;
		this.at = at;
		this.pitch = pitch;
		this.instrument = instrument;
	}

	public function apply(song:Song):Void {
		wasAt = note.at;
		wasPitch = note.pitch;
		wasInstrument = note.instrument;

		note.at = at;
		note.pitch = pitch;
		if (instrument != -2) note.instrument = instrument;

		resort(song);
	}

	public function revert(song:Song):Void {
		note.at = wasAt;
		note.pitch = wasPitch;
		note.instrument = wasInstrument;

		resort(song);
	}

	function resort(song:Song):Void {
		final held = song.patternAt(pattern);
		if (held != null) held.lane(part).sort();
	}

	public function label():String {
		return "move a note";
	}
}
