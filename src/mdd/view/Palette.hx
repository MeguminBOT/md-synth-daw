package mdd.view;

import haxe.ds.Vector;
import mdd.app.Locale;
import mdd.ui.Theme;

/**
	The eleven colours a track or a pattern can be given, and what each is called.

	They are the part colours, so an arrangement coloured by hand still reads against
	the rack and the roll.
**/
@:unreflective
final class Palette {
	/**
		The colours, in part order.
	**/
	public static final COLOURS:Vector<Int> = Vector.fromArrayCopy([
		Theme.FM1, Theme.FM2, Theme.FM3, Theme.FM4, Theme.FM5, Theme.FM6,
		Theme.PSG1, Theme.PSG2, Theme.PSG3, Theme.NOISE, Theme.DAC
	]);

	/**
		What each of them is called.
	**/
	public static final NAMES:Vector<Locale> = Vector.fromArrayCopy([
		Locale.COLOUR_RED, Locale.COLOUR_ORANGE, Locale.COLOUR_YELLOW, Locale.COLOUR_LIME,
		Locale.COLOUR_GREEN, Locale.COLOUR_TEAL, Locale.COLOUR_BLUE, Locale.COLOUR_INDIGO,
		Locale.COLOUR_VIOLET, Locale.COLOUR_GREY, Locale.COLOUR_PINK
	]);
}
