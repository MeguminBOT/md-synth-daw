package mdd.view.monitor;

import haxe.ds.Vector;
import mdd.app.Locale;

/**
	The shapes a window function takes: what a scope weighs a spectrum's samples by, so a tone
	between two bars stays in them rather than leaking across the rest, and what it smooths a
	waveform with.

	They change only what is drawn. Nothing here reaches the sound or an export's audio.
**/
@:unreflective
final class Windowing {
	/**
		No shape: every sample weighs the same, and a waveform is drawn as it is.
	**/
	public static inline final NONE = 0;

	/**
		A raised cosine reaching nought at both ends.
	**/
	public static inline final HANN = 1;

	/**
		A raised cosine stopping short of nought, which keeps the nearest bars apart better.
	**/
	public static inline final HAMMING = 2;

	/**
		Three cosines, which leaks least of the four and spreads a tone widest.
	**/
	public static inline final BLACKMAN = 3;

	/**
		A bell whose width is four tenths of the window's half width.
	**/
	public static inline final GAUSSIAN = 4;

	/**
		How many shapes there are.
	**/
	public static inline final KINDS = 5;

	/**
		The most samples a smoothed waveform's kernel spans, which bounds what smoothing costs a
		frame.
	**/
	public static inline final WIDEST = 63;

	/**
		What each shape is called, in order.
	**/
	public static final NAMES:Array<Locale> = [Locale.WINDOWING_NONE, Locale.WINDOWING_HANN,
		Locale.WINDOWING_HAMMING, Locale.WINDOWING_BLACKMAN, Locale.WINDOWING_GAUSSIAN];

	/**
		@param kind One of the shapes.
		@param at Where in the window, from nought at the first sample to one at the last.
		@return The weight there, one at the middle of every shape.
	**/
	public static function weight(kind:Int, at:Float):Float {
		final turn = 2 * Math.PI * at;

		return switch (kind) {
			case HANN: 0.5 - 0.5 * Math.cos(turn);
			case HAMMING: 0.54 - 0.46 * Math.cos(turn);
			case BLACKMAN: 0.42 - 0.5 * Math.cos(turn) + 0.08 * Math.cos(turn * 2);
			case GAUSSIAN:
				final away = (at - 0.5) / 0.2;
				Math.exp(-0.5 * away * away);
			case _: 1;
		}
	}

	/**
		Writes a shape's weights over a window.

		@param kind One of the shapes.
		@param into Where the weights go, from its start.
		@param count How many samples the window holds.
		@return The weights added up, which a sum weighed by them is divided by.
	**/
	public static function fills(kind:Int, into:Vector<Float>, count:Int):Float {
		var total = 0.0;
		final last = count > 1 ? count - 1 : 1;

		for (index in 0...count) {
			final held = weight(kind, index / last);

			into[index] = held;
			total += held;
		}

		return total;
	}

	/**
		@param width How many samples a smoothing kernel is asked to span.
		@return The width it actually spans: odd, so it has a middle, and between three and
			`WIDEST`.
	**/
	public static inline function spanned(width:Int):Int {
		final held = width < 3 ? 3 : (width > WIDEST ? WIDEST : width);
		return (held & 1) == 0 ? held + 1 : held;
	}
}
