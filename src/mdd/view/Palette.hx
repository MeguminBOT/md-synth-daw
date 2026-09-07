package mdd.view;

import haxe.ds.Vector;
import mdd.app.Locale;
import mdd.ui.Theme;

@:unreflective
final class Palette {
	public static final COLOURS:Vector<Int> = Vector.fromArrayCopy([
		Theme.FM1, Theme.FM2, Theme.FM3, Theme.FM4, Theme.FM5, Theme.FM6,
		Theme.PSG1, Theme.PSG2, Theme.PSG3, Theme.NOISE, Theme.DAC
	]);

	public static final NAMES:Vector<Locale> = Vector.fromArrayCopy([
		Locale.COLOUR_RED, Locale.COLOUR_ORANGE, Locale.COLOUR_YELLOW, Locale.COLOUR_LIME,
		Locale.COLOUR_GREEN, Locale.COLOUR_TEAL, Locale.COLOUR_BLUE, Locale.COLOUR_INDIGO,
		Locale.COLOUR_VIOLET, Locale.COLOUR_GREY, Locale.COLOUR_PINK
	]);
}
