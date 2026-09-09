package mdd.view;

import mdd.song.Part;
import mdd.song.Song;

/**
	What an instrument is called in the rack.

	A sample instrument is shown by the bank it came from rather than by its own name,
	because a drum kit reads better as one thing than as fourteen.
**/
@:unreflective
final class Kits {
	/**
		@param song The piece.
		@param part Which part it plays on.
		@param which The instrument, by index.
		@return What to call it, which is the bank name for a sample instrument and the instrument
			name for anything else.
	**/
	public static function named(song:Song, part:Part, which:Int):String {
		final instrument = song.instrumentAt(which);
		if (instrument == null) return "";
		if (!part.sampled()) return instrument.name;

		final at = song.bankOf(which);
		return at < 0 ? instrument.name : song.banks[at].name;
	}
}
