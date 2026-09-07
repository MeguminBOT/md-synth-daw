package mdd.view;

import mdd.app.Locale;
import mdd.song.Scale;

class Scales {
	public static final NAMES:Array<Locale> = [Locale.SCALE_CHROMATIC, Locale.SCALE_MAJOR,
		Locale.SCALE_MINOR, Locale.SCALE_HARMONIC, Locale.SCALE_DORIAN,
		Locale.SCALE_MIXOLYDIAN, Locale.SCALE_PENTATONIC, Locale.SCALE_MINOR_PENTATONIC,
		Locale.SCALE_BLUES];

	public static function named(kind:Int):Locale {
		return kind < 0 || kind >= Scale.KINDS ? NAMES[0] : NAMES[kind];
	}
}
