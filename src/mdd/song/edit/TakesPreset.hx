package mdd.song.edit;

import mdd.song.Part;

/**
	Loads a preset into a part as a copy of it, so the preset itself stays as it was written.

	A channel is edited as it is played with, and the preset it came from is what it goes back to:
	choosing the same preset again puts every field back, and one parameter can be put back on its
	own. The copy carries which preset it came from, and the piece carries that preset, so both
	still work on a machine that has none of the reader's own presets.

	A converter part is loaded as it always was, by pointing at the preset itself, because a kit is
	the presets in one bank and a copy of a hit would not be in it.

	One step on the undo stack. `apply` does it and `revert` puts the song back exactly as it was,
	which is why anything it overwrites is kept here.
**/
final class TakesPreset implements Command {
	final part:Part;
	final which:Int;

	var was:Int = -1;
	var made:Int = -1;
	var kept:Null<Instrument> = null;

	final held:Array<Note> = [];
	final marks:Array<Int> = [];

	/**
		Records what to do. Nothing changes until `apply` is called.

		@param part Which part loads it.
		@param which The preset, by index into the song.
	**/
	public function new(part:Part, which:Int) {
		this.part = part;
		this.which = which;
	}

	/**
		Does it, keeping whatever `revert` will need to put back.

		@param song The song to act on.
	**/
	public function apply(song:Song):Void {
		final index = part.index();
		final source = song.instrumentAt(which);

		was = song.rack[index];
		made = -1;
		kept = null;

		if (source == null) return;

		if (part.sampled()) {
			pointed(song, which);
			return;
		}

		final playing = song.instrumentAt(was);

		if (playing != null && playing.from == source.id && was != which) {
			kept = playing.copy();
			playing.takes(source);

			return;
		}

		final copy = source.copy();
		copy.from = source.id;

		song.instrument(copy);
		made = song.instruments.length - 1;

		song.bank(0).remove(made);
		pointed(song, made);
	}

	/**
		Puts the song back as it was.

		@param song The song to act on.
	**/
	public function revert(song:Song):Void {
		final playing = song.instrumentAt(was);
		final holding = kept;

		if (holding != null && playing != null) playing.takes(holding);

		song.rack[part.index()] = was;

		for (index in 0...held.length) held[index].instrument = marks[index];

		held.resize(0);
		marks.resize(0);
	}

	/**
		@return What the undo entry is called, in lower case.
	**/
	public function label():String {
		return "load a preset into " + part.name();
	}

	/**
		Points the part, and every note already written for it, at one instrument.

		@param song The song.
		@param at The instrument, by index.
	**/
	function pointed(song:Song, at:Int):Void {
		song.rack[part.index()] = at;

		held.resize(0);
		marks.resize(0);

		for (pattern in song.patterns) {
			for (note in pattern.lane(part).notes) {
				if (note.instrument == at) continue;

				held.push(note);
				marks.push(note.instrument);
				note.instrument = at;
			}
		}
	}
}
