package mdd.song.edit;

import mdd.check.Chording;

/**
	Takes the notes a channel will never sound out of the way.

	Every part of this console plays one note at a time, so a chord imported onto one of
	them is a note that sounds and a note or two that do not. This either drops those or
	puts them in a pattern of their own, where they can be given a channel that is free.

	A part whose notes have no key is left alone, because there is nothing to be right
	about: a drum part or an atonal run has no note more in key than another, and the
	guess would be worse than the chord.

	One step on the undo stack. `apply` does it and `revert` puts the song back exactly
	as it was, which is why every note it takes out is kept here beside the lane it came
	from.
**/
final class ThinChords implements Command {
	final moves:Bool;

	final from:Array<Lane> = [];
	final taken:Array<Note> = [];

	var made:Array<Pattern> = [];
	var done:Bool = false;

	/**
		Records what to do. Nothing changes until `apply` is called.

		@param moves Whether the notes go into a pattern of their own rather than being
			dropped.
	**/
	public function new(moves:Bool) {
		this.moves = moves;
	}

	/**
		@param song The piece to read.
		@return How many notes no channel will sound. Nought means there is nothing to
			offer and nothing to ask about.
	**/
	public static function counted(song:Song):Int {
		var many = 0;

		for (pattern in song.patterns) {
			for (index in 0...Part.COUNT) {
				final lane = pattern.lane(index);
				final key = Chording.keyed(lane.notes);

				if (key.kind == Scale.CHROMATIC) continue;

				many += Chording.silenced(lane.notes, key).length;
			}
		}

		return many;
	}

	/**
		Does it, keeping whatever `revert` will need to put back.

		@param song The song to act on.
	**/
	public function apply(song:Song):Void {
		if (done) {
			redoes(song);
			return;
		}

		for (pattern in song.patterns) {
			var spare:Null<Pattern> = null;

			for (index in 0...Part.COUNT) {
				final lane = pattern.lane(index);
				final key = Chording.keyed(lane.notes);

				if (key.kind == Scale.CHROMATIC) continue;

				final gone = Chording.silenced(lane.notes, key);
				if (gone.length == 0) continue;

				for (note in gone) {
					lane.remove(note);

					this.from.push(lane);
					this.taken.push(note);

					if (!moves) continue;

					if (spare == null) {
						spare = new Pattern(pattern.name + " chords", pattern.length,
							pattern.colour);

						spare.part = pattern.part;
						made.push(spare);
					}

					spare.lane(index).add(note);
				}
			}
		}

		for (pattern in made) song.patterns.push(pattern);

		done = true;
	}

	/**
		Does it again, after a revert, without working any of it out a second time.

		@param song The song to act on.
	**/
	function redoes(song:Song):Void {
		for (index in 0...taken.length) from[index].remove(taken[index]);
		for (pattern in made) song.patterns.push(pattern);
	}

	/**
		Puts the song back as it was.

		@param song The song to act on.
	**/
	public function revert(song:Song):Void {
		for (pattern in made) song.patterns.remove(pattern);
		for (index in 0...taken.length) from[index].add(taken[index]);
	}

	/**
		@return What the undo entry is called, in lower case.
	**/
	public function label():String {
		return moves ? "move what cannot sound" : "remove what cannot sound";
	}
}
