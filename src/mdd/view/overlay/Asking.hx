package mdd.view.overlay;

import mdd.ui.Font;
import mdd.ui.Input;
import mdd.ui.Key;
import mdd.ui.Kind;
import mdd.ui.Metrics;
import mdd.ui.Motion;
import mdd.ui.Paint;
import mdd.ui.Pointer;
import mdd.ui.Theme;
import mdd.ui.Widget;

@:unreflective

/**
	The sheet that asks a question and takes one of up to three answers.

	Every question of this shape is the same sheet: a line saying what has happened, a
	paragraph saying what it means, and the answers side by side at the bottom. What the
	answers do is the caller's, which is why nothing here knows what is being asked.

	**The last answer is the one that does nothing**, because Escape gives it and so does
	closing the sheet any other way. Enter gives the first, so the answers read from the
	one most readers want to the one that changes nothing.
**/
final class Asking extends Widget {
	/**
		How many answers it holds.
	**/
	public static inline final MOST = 3;

	static inline final WIDE = 460;

	/**
		What has happened, on the first line.
	**/
	public var asking(default, null):String = "";

	/**
		What the answers are, in order, from the one most readers want to the one that
		changes nothing.
	**/
	public var answers(default, null):Array<String> = [];

	/**
		Called with which answer was given. It is called once, after the sheet has been
		closed, so an answer that raises a sheet of its own is not lowered by this one
		going.
	**/
	public var onAnswer:Null<Int -> Void> = null;

	/**
		Called when the sheet closes, whichever answer was given.
	**/
	public var onShut:Null<Void -> Void> = null;

	/**
		How far it has risen into place.
	**/
	public final rise:Motion;

	/**
		How far it has faded in.
	**/
	public final fade:Motion;

	var said:String = "";
	var lines:Array<String> = [];
	var linesWide:Float = -1;

	var hoverAt:Int = -1;
	var downAt:Int = -1;

	/**
		Builds the sheet with nothing in it.
	**/
	public function new() {
		super();

		modal = true;
		focusable = true;
		opaque = true;

		rise = new Motion(this, 0, true);
		fade = new Motion(this, 0, false);
	}

	/**
		Asks, and starts the fade.

		@param asking What has happened, on the first line.
		@param said What it means, wrapped to the sheet.
		@param answers What the answers are, at most `MOST` of them, the last being the
			one that changes nothing.
	**/
	public function ask(asking:String, said:String, answers:Array<String>):Void {
		this.asking = asking;
		this.said = said;
		this.answers = answers.length > MOST ? answers.slice(0, MOST) : answers;

		lines = [];
		linesWide = -1;

		hoverAt = -1;
		downAt = -1;

		final root = root();
		if (root == null) return;

		rise.hold(0);
		fade.hold(0);

		root.start(rise, 1, Motion.ENTER);
		root.start(fade, 1, Motion.ENTER);
	}

	/**
		Wraps what is said to the room there is for it, once, because it changes only
		when the question or the width does and it is wanted on every frame.

		@param metrics What to measure in.
		@param face The face it is written in.
	**/
	function words(metrics:Metrics, face:Font):Void {
		final room = width - metrics.inset * 2;
		if (room == linesWide) return;

		linesWide = room;
		lines = face.wrapped(said, room);
	}

	function buttonTall():Float {
		final root = root();
		return root == null ? 32 : root.metrics.whole(32);
	}

	/**
		@param metrics What to measure in.
		@return How wide one answer is drawn. They share the width of the sheet evenly,
			which is what the update notice does and what keeps three long answers in
			one language from reading as a ragged row in another.
	**/
	function buttonWide(metrics:Metrics):Float {
		final many = answers.length < 1 ? 1 : answers.length;
		return (width - metrics.inset * 2 - metrics.gap * (many - 1)) / many;
	}

	override function measure(availableWidth:Float, availableHeight:Float):Void {
		final root = root();
		final metrics = root == null ? null : root.metrics;

		if (metrics == null || metrics.body == null) {
			wantWidth = WIDE;
			wantHeight = 190;
			return;
		}

		final font = metrics.body;
		final small = metrics.small == null ? font : metrics.small;

		wantWidth = metrics.whole(WIDE);
		if (wantWidth > availableWidth) wantWidth = availableWidth;

		width = wantWidth;
		words(metrics, small);

		wantHeight = metrics.inset * 2 + font.height + metrics.gap
			+ lines.length * small.height + metrics.gap * 2 + buttonTall();
	}

	/**
		@param px A point, across.
		@param py A point, down.
		@return Which answer is there, or -1.
	**/
	public function answerAt(px:Float, py:Float):Int {
		final root = root();
		if (root == null || answers.length == 0) return -1;

		final metrics = root.metrics;
		final tall = buttonTall();
		final top = y + height - metrics.inset - tall;

		if (py < top || py >= top + tall) return -1;

		final wide = buttonWide(metrics);

		for (which in 0...answers.length) {
			final left = x + metrics.inset + which * (wide + metrics.gap);
			if (px >= left && px < left + wide) return which;
		}

		return -1;
	}

	override function took(event:Input):Bool {
		switch (event.kind) {
			case Kind.PointerDown:
				if (event.button != Pointer.Left) return true;

				downAt = answerAt(event.x, event.y);
				invalidate();
				return true;

			case Kind.PointerUp:
				final which = answerAt(event.x, event.y);
				final was = downAt;

				downAt = -1;
				invalidate();

				if (which >= 0 && which == was) gives(which);
				return true;

			case Kind.PointerMove:
				final which = answerAt(event.x, event.y);
				if (which == hoverAt) return true;

				hoverAt = which;
				invalidate();
				return true;

			case Kind.KeyDown:
				if (event.code == Key.Return) {
					gives(0);
					return true;
				}

			case _:
		}

		return true;
	}

	override function hovered(on:Bool):Void {
		if (!on) hoverAt = -1;
		super.hovered(on);
	}

	/**
		Treats being taken off the screen as the last answer.

		Escape never reaches a sheet: the root lowers it and the key is gone, so without
		this the one key everybody reaches for to make something go away would answer
		nothing and the question would be lost with it.
	**/
	override public function lowered():Void {
		final what = onAnswer;
		if (what == null) return;

		onAnswer = null;
		what(answers.length - 1);
	}

	/**
		Gives an answer and closes the sheet.

		The handler is taken before it is called, so a second press on the way out
		answers nothing twice.

		@param which Which answer.
	**/
	public function gives(which:Int):Void {
		if (which < 0 || which >= answers.length) return;

		final what = onAnswer;
		onAnswer = null;

		if (onShut != null) onShut();
		if (what != null) what(which);
	}

	override function paint(paint:Paint):Void {
		final root = root();
		if (root == null || root.metrics.body == null) return;

		final theme = root.theme;
		final metrics = root.metrics;
		final alpha = fade.value;

		if (alpha <= 0.004) return;

		final font = metrics.body;
		final small = metrics.small == null ? font : metrics.small;

		words(metrics, small);

		final lift = (1 - rise.value) * metrics.sizeOf(8);
		paint.pushTransform(0, lift);

		paint.roundedRect(x, y, width, height, metrics.radiusPanel, theme.raise1, alpha);
		paint.outline(x, y, width, height, theme.frame, metrics.whole(1), alpha,
			metrics.radiusPanel);

		paint.reface(font);
		paint.text(asking, x + metrics.inset, y + metrics.inset + font.ascent, theme.ink,
			alpha);

		paint.reface(small);

		var line = y + metrics.inset + font.height + metrics.gap + small.ascent;

		for (which in 0...lines.length) {
			paint.text(lines[which], x + metrics.inset, line, theme.dim, alpha * 0.85);
			line += small.height;
		}

		buttoned(paint, theme, metrics, font, alpha);
		paint.popTransform();
	}

	/**
		Draws the answers in a row, the first one accented because Enter gives it.

		@param paint What to draw with.
		@param theme The colours.
		@param metrics The measurements.
		@param font The face the answers are written in.
		@param alpha How far the sheet has faded in.
	**/
	function buttoned(paint:Paint, theme:Theme, metrics:Metrics, font:Font,
			alpha:Float):Void {
		final tall = buttonTall();
		final top = y + height - metrics.inset - tall;
		final wide = buttonWide(metrics);

		paint.reface(font);

		for (which in 0...answers.length) {
			final left = x + metrics.inset + which * (wide + metrics.gap);
			final first = which == 0;

			paint.roundedRect(left, top, wide, tall, metrics.radiusRow,
				first ? theme.accent : theme.raise2, (first ? 0.85 : 1) * alpha);

			if (which == downAt) {
				paint.roundedRect(left, top, wide, tall, metrics.radiusRow, theme.accent,
					Theme.PRESS * alpha);
			} else if (which == hoverAt) {
				paint.roundedRect(left, top, wide, tall, metrics.radiusRow, theme.accent,
					Theme.HOVER * alpha);
			}

			paint.pushClip(left, top, wide, tall);
			paint.textCentred(answers[which], left + wide * 0.5,
				top + (tall - font.height) * 0.5 + font.ascent,
				first ? theme.ink : theme.dim, alpha);
			paint.popClip();
		}
	}
}
