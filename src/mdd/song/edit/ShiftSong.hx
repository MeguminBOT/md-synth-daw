package mdd.song.edit;

/**
	Moves the whole song along in time.

	One step on the undo stack. `apply` does it and `revert` puts the song back
	exactly as it was, which is why anything it overwrites is kept here.
**/
final class ShiftSong implements Command {
	final by:Int;

	var went:Int = 0;

	final lengths:Array<Int> = [];

	final notes:Array<Note> = [];
	final wereNotes:Array<Int> = [];
	final points:Array<Point> = [];
	final werePoints:Array<Int> = [];
	final marks:Array<Int> = [];
	final wereMarks:Array<Int> = [];

	/**
		Records what to do. Nothing changes until `apply` is called.

		@param by How far to move it, in ticks.
	**/
	public function new(by:Int) {
		this.by = by;
	}

	/**
		Does it, keeping whatever `revert` will need to put back.

		@param song The song to act on.
	**/
	public function apply(song:Song):Void {
		lengths.resize(0);
		for (pattern in song.patterns) lengths.push(pattern.length);

		remembers(song);
		went = song.shift(by);
	}

	/**
		Puts the song back as it was.

		@param song The song to act on.
	**/
	public function revert(song:Song):Void {
		if (went == 0) return;

		song.shift(-went);

		for (index in 0...notes.length) notes[index].at = wereNotes[index];
		for (index in 0...points.length) points[index].at = werePoints[index];

		for (index in 0...marks.length) song.tempo.at[marks[index]] = wereMarks[index];
		if (marks.length > 0) song.tempo.resolve(song.tempo.ppqn);

		for (index in 0...lengths.length) {
			if (index < song.patterns.length) song.patterns[index].length = lengths[index];
		}

		forgets();
		went = 0;
	}

	function forgets():Void {
		notes.resize(0);
		wereNotes.resize(0);
		points.resize(0);
		werePoints.resize(0);
		marks.resize(0);
		wereMarks.resize(0);
	}

	function remembers(song:Song):Void {
		forgets();

		if (by >= 0) return;

		final floor = -by;

		for (pattern in song.patterns) {
			for (index in 0...Part.COUNT) {
				final lane = pattern.lane(index);

				for (note in lane.notes) {
					if (note.at >= floor) continue;

					notes.push(note);
					wereNotes.push(note.at);
				}

				for (line in lane.automation) {
					for (point in line.points) {
						if (point.at >= floor) continue;

						points.push(point);
						werePoints.push(point.at);
					}
				}
			}
		}

		for (index in 0...song.tempo.at.length) {
			final held = song.tempo.at[index];
			if (held <= 0 || held >= floor) continue;

			marks.push(index);
			wereMarks.push(held);
		}
	}

	/**
		@return What the undo entry is called, in lower case.
	**/
	public function label():String {
		return by < 0 ? "nudge the song earlier" : "nudge the song later";
	}
}
