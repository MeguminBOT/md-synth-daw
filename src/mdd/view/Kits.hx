package mdd.view;

import mdd.song.Part;
import mdd.song.Song;

@:unreflective
final class Kits {
	public static function named(song:Song, part:Part, which:Int):String {
		final instrument = song.instrumentAt(which);
		if (instrument == null) return "";
		if (!part.sampled()) return instrument.name;

		final at = song.bankOf(which);
		return at < 0 ? instrument.name : song.banks[at].name;
	}
}
