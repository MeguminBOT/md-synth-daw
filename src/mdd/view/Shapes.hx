package mdd.view;

import mdd.app.Locale;

/**
	What each automation curve is called, in the order `Automation` numbers them.
**/
class Shapes {
	/**
		One name per shape.
	**/
	public static final NAMES:Array<Locale> = [Locale.SHAPE_HOLD, Locale.SHAPE_LINEAR,
		Locale.SHAPE_CURVE, Locale.SHAPE_SMOOTH, Locale.SHAPE_STAIRS,
		Locale.SHAPE_SMOOTH_STAIRS, Locale.SHAPE_PULSE, Locale.SHAPE_WAVE,
		Locale.SHAPE_HALF_SINE];
}
