package mdd.view.overlay;

import mdd.app.Locale;
import mdd.app.Session;
import mdd.app.Update;
import mdd.ui.Input;
import mdd.ui.Kind;
import mdd.ui.Metrics;
import mdd.ui.Motion;
import mdd.ui.Paint;
import mdd.ui.Pointer;
import mdd.ui.Theme;
import mdd.ui.Widget;

@:unreflective

/**
	The update notice: which version is running, which is offered, and three answers.

	Nothing is downloaded until the reader chooses to, which is what the notice says as
	well as what the updater does.
**/
final class Notice extends Widget {
	static inline final TAKE = 0;

	/**
		Button: leave it for now.
	**/
	public static inline final LATER = 1;
	static inline final NEVER = 2;

	/**
		How many buttons there are.
	**/
	public static inline final BUTTONS = 3;

	static final LABELS:Array<Locale> = [Locale.UPDATE_TAKE, Locale.UPDATE_LATER,
		Locale.UPDATE_NEVER];

	/**
		The session to read.
	**/
	public var session:Session;

	/**
		The updater, which is where the versions and the notes come from.
	**/
	public var update:Null<Update> = null;

	/**
		How far it has risen into place.
	**/
	public final rise:Motion;

	/**
		How far it has faded in.
	**/
	public final fade:Motion;

	/**
		Called to take the update.
	**/
	public var onTake:Null<Void -> Void> = null;

	/**
		Called to stop looking for updates.
	**/
	public var onNever:Null<Void -> Void> = null;

	var hoverAt:Int = -1;

	/**
		Builds the notice.

		@param session The session to read.
	**/
	public function new(session:Session) {
		super();
		modal = true;
		this.session = session;

		focusable = true;
		opaque = true;

		rise = new Motion(this, 0, true);
		fade = new Motion(this, 0, false);
	}

	/**
		Starts the fade and the rise.
	**/
	public function arrive():Void {
		final root = root();
		if (root == null) return;

		rise.hold(0);
		fade.hold(0);

		root.start(rise, 1, Motion.ENTER);
		root.start(fade, 1, Motion.ENTER);
	}

	override function measure(availableWidth:Float, availableHeight:Float):Void {
		final root = root();
		final metrics = root == null ? null : root.metrics;

		wantWidth = metrics == null ? 440 : metrics.whole(440);
		wantHeight = metrics == null ? 190 : metrics.whole(190);
	}

	function buttonTall():Float {
		final root = root();
		return root == null ? 32 : root.metrics.whole(32);
	}

	/**
		@param px A point, across.
		@param py A point, down.
		@return Which button is there, or -1.
	**/
	public function buttonAt(px:Float, py:Float):Int {
		final root = root();
		if (root == null) return -1;

		final metrics = root.metrics;
		final tall = buttonTall();
		final top = y + height - metrics.inset - tall;

		if (py < top || py >= top + tall) return -1;

		final wide = (width - metrics.inset * 2 - metrics.gap * 2) / BUTTONS;

		for (which in 0...BUTTONS) {
			final left = x + metrics.inset + which * (wide + metrics.gap);
			if (px >= left && px < left + wide) return which;
		}

		return -1;
	}

	override function took(event:Input):Bool {
		switch (event.kind) {
			case Kind.PointerDown:
				final which = buttonAt(event.x, event.y);
				if (which < 0) return true;

				press(which);
				return true;

			case Kind.PointerMove:
				final which = buttonAt(event.x, event.y);
				if (which == hoverAt) return true;

				hoverAt = which;
				invalidate();
				return true;

			case _:
		}

		return true;
	}

	/**
		Presses a button and closes the notice.

		@param which Which button.
	**/
	public function press(which:Int):Void {
		final root = root();

		switch (which) {
			case TAKE:
				if (onTake != null) onTake();

			case NEVER:
				if (update != null) update.refuse();
				if (onNever != null) onNever();
				session.says(Locale.SAID_UPDATE_NEVER_AGAIN);

			case _:
				if (update != null) update.refuse();
				session.says(Locale.SAID_UPDATE_LATER);
		}

		if (root != null) root.lower();
		session.changed();
	}

	override function hovered(on:Bool):Void {
		if (!on) hoverAt = -1;
		super.hovered(on);
	}

	override function paint(paint:Paint):Void {
		final root = root();
		if (root == null || root.metrics.body == null || update == null) return;

		final theme = root.theme;
		final metrics = root.metrics;
		final alpha = fade.value;

		if (alpha <= 0.004) return;

		final lift = (1 - rise.value) * metrics.sizeOf(8);
		paint.pushTransform(0, lift);

		paint.roundedRect(x, y, width, height, metrics.radiusPanel, theme.raise1, alpha);
		paint.outline(x, y, width, height, theme.frame, metrics.whole(1), alpha,
			metrics.radiusPanel);

		final font = metrics.body;
		final small = metrics.small == null ? font : metrics.small;

		paint.reface(font);
		paint.text(translate(Locale.UPDATE_FOUND), x + metrics.inset,
			y + metrics.inset + font.ascent, theme.ink, alpha);

		paint.reface(small);

		var line = y + metrics.inset + font.height + metrics.gap + small.ascent;

		paint.text(translate(Locale.UPDATE_RUNNING) + " " + update.running + "     "
			+ translate(Locale.UPDATE_OFFERED) + " " + update.offered,
			x + metrics.inset, line, theme.dim, alpha * 0.9);

		if (update.notes != "") {
			line += small.height + metrics.unit;
			paint.text(update.notes, x + metrics.inset, line, theme.dim, alpha * 0.75);
		}

		line += small.height + metrics.gap;
		paint.text(translate(Locale.UPDATE_CONSENT), x + metrics.inset, line, theme.dim,
			alpha * 0.75);

		final tall = buttonTall();
		final top = y + height - metrics.inset - tall;
		final wide = (width - metrics.inset * 2 - metrics.gap * 2) / BUTTONS;

		for (which in 0...BUTTONS) {
			final left = x + metrics.inset + which * (wide + metrics.gap);

			paint.roundedRect(left, top, wide, tall, metrics.radiusRow,
				which == TAKE ? theme.accent : theme.raise2, which == TAKE ? 0.85 : 1);

			if (which == hoverAt) {
				paint.roundedRect(left, top, wide, tall, metrics.radiusRow, theme.accent,
					Theme.HOVER);
			}

			paint.textCentred(translate(LABELS[which]), left + wide * 0.5,
				top + (tall - small.height) * 0.5 + small.ascent,
				which == TAKE ? theme.ink : theme.dim, alpha);
		}

		paint.popTransform();
	}
}
