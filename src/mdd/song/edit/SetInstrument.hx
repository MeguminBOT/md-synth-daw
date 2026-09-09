package mdd.song.edit;

import mdd.song.Part;

/**
	Changes which instrument a part plays.

	One step on the undo stack. `apply` does it and `revert` puts the song back
	exactly as it was, which is why anything it overwrites is kept here.
**/
final class SetInstrument implements Command {
	final part:Part;
	final which:Int;

	var was:Int = -1;
	final held:Array<Note> = [];
	final marks:Array<Int> = [];

	/**
		Records what to do. Nothing changes until `apply` is called.

		@param part Which part of the pattern.
		@param which Which one, by index.
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

		was = song.rack[index];
		song.rack[index] = which;

		held.resize(0);
		marks.resize(0);

		for (pattern in song.patterns) {
			for (note in pattern.lane(part).notes) {
				if (note.instrument == which) continue;

				held.push(note);
				marks.push(note.instrument);
				note.instrument = which;
			}
		}
	}

	/**
		Puts the song back as it was.

		@param song The song to act on.
	**/
	public function revert(song:Song):Void {
		song.rack[part.index()] = was;

		for (index in 0...held.length) held[index].instrument = marks[index];

		held.resize(0);
		marks.resize(0);
	}

	/**
		@return What the undo entry is called, in lower case.
	**/
	public function label():String {
		return "load a patch into " + part.name();
	}
}
