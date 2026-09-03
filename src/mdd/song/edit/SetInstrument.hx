package mdd.song.edit;

import mdd.song.Part;

final class SetInstrument implements Command {
	final part:Part;
	final which:Int;

	var was:Int = -1;
	final held:Array<Note> = [];
	final marks:Array<Int> = [];

	public function new(part:Part, which:Int) {
		this.part = part;
		this.which = which;
	}

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

	public function revert(song:Song):Void {
		song.rack[part.index()] = was;

		for (index in 0...held.length) held[index].instrument = marks[index];

		held.resize(0);
		marks.resize(0);
	}

	public function label():String {
		return "load a patch into " + part.name();
	}
}
