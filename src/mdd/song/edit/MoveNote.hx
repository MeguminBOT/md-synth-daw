package mdd.song.edit;

/**
	Moves a note in time and pitch, and can change its instrument.

	One step on the undo stack. `apply` does it and `revert` puts the song back
	exactly as it was, which is why anything it overwrites is kept here.
**/
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
	var wasLength:Int = 0;

	/**
		Records what to do. Nothing changes until `apply` is called.

		@param pattern Which pattern, by index.
		@param part Which part of the pattern.
		@param note The note.
		@param at Which one, by index.
		@param pitch The MIDI note number to move it to.
		@param instrument The instrument to give it, or -2 to leave it alone.
	**/
	public function new(pattern:Int, part:Part, note:Note, at:Int, pitch:Int,
			instrument:Int = -2) {
		this.pattern = pattern;
		this.part = part;
		this.note = note;
		this.at = at;
		this.pitch = pitch;
		this.instrument = instrument;
	}

	/**
		Does it, keeping whatever `revert` will need to put back.

		@param song The song to act on.
	**/
	public function apply(song:Song):Void {
		wasAt = note.at;
		wasPitch = note.pitch;
		wasInstrument = note.instrument;

		note.at = at;
		note.pitch = pitch;
		if (instrument != -2) note.instrument = instrument;

		final held = song.patternAt(pattern);
		if (held == null) return;

		held.lane(part).sort();
		wasLength = held.fits(song.tempo.ppqn * 4);
	}

	/**
		Puts the song back as it was.

		@param song The song to act on.
	**/
	public function revert(song:Song):Void {
		note.at = wasAt;
		note.pitch = wasPitch;
		note.instrument = wasInstrument;

		final held = song.patternAt(pattern);
		if (held == null) return;

		held.lane(part).sort();
		held.length = wasLength;
	}

	/**
		@return What the undo entry is called, in lower case.
	**/
	public function label():String {
		return "move a note";
	}
}
