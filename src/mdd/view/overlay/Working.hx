package mdd.view.overlay;

import mdd.app.Locale;
import mdd.app.Task;
import mdd.ui.Input;
import mdd.ui.Kind;
import mdd.ui.Metrics;
import mdd.ui.Motion;
import mdd.ui.Paint;
import mdd.ui.Theme;
import mdd.ui.Widget;

@:unreflective

/**
	The progress bar: what is running, how far through it is, and a way to stop it.

	It lives in the band rather than the sheet layer, which is the one slot nothing
	else can claim: raising any other overlay would otherwise lower it, and a progress
	bar that can be lowered by something else is a window that looks frozen.

	A task that does not know how far through it is sweeps instead of filling.
**/
final class Working extends Widget {
	/**
		How long one sweep takes, in seconds, for a task that cannot say how far through it
		is.
	**/
	public static inline final SWEEP = 1.1;

	/**
		What is running.
	**/
	public var task:Null<Task> = null;

	/**
		How far it has risen into place.
	**/
	public final rise:Motion;

	/**
		How far it has faded in.
	**/
	public final fade:Motion;

	/**
		What to do when it is stopped, or null where it cannot be.
	**/
	public var onCancel:Null<Void -> Void> = null;

	var over:Bool = false;
	var swept:Float = 0;

	/**
		Builds a progress bar with nothing running.
	**/
	public function new() {
		super();

		focusable = true;
		opaque = true;
		sealed = true;

		rise = new Motion(this, 0, true);
		fade = new Motion(this, 0, false);
	}

	/**
		Takes a task and starts the fade. With no root to animate against it is put
		straight up, so a caller that draws one frame and then works sees it.

		@param task What is running.
	**/
	public function arrive(task:Task):Void {
		final root = root();

		this.task = task;
		swept = 0;
		over = false;

		if (root == null) {
			rise.hold(1);
			fade.hold(1);
			return;
		}

		rise.hold(0);
		fade.hold(0);

		root.start(rise, 1, Motion.ENTER);
		root.start(fade, 1, Motion.ENTER);
	}

	/**
		Moves the sweep on. Call once a frame.

		@param since How long since the last call.
		@return Whether the task is one that sweeps rather than fills.
	**/
	public function advance(since:Float):Bool {
		if (task == null) return false;

		swept += since;
		while (swept >= SWEEP) swept -= SWEEP;

		return task.reach() < 0;
	}

	override function measure(availableWidth:Float, availableHeight:Float):Void {
		final root = root();
		final metrics = root == null ? null : root.metrics;

		wantWidth = metrics == null ? 400 : metrics.whole(400);
		wantHeight = metrics == null ? 148 : metrics.whole(cancels() ? 148 : 108);
	}

	inline function cancels():Bool {
		return task != null && task.cancellable;
	}

	function buttonTall():Float {
		final root = root();
		return root == null ? 32 : root.metrics.whole(32);
	}

	function buttonWide():Float {
		final root = root();
		return root == null ? 120 : root.metrics.whole(120);
	}

	/**
		@param px A point, across.
		@param py A point, down.
		@return Whether the point is on the stop button.
	**/
	public function onButton(px:Float, py:Float):Bool {
		if (!cancels()) return false;

		final root = root();
		if (root == null) return false;

		final metrics = root.metrics;
		final tall = buttonTall();
		final wide = buttonWide();
		final left = x + width - metrics.inset - wide;
		final top = y + height - metrics.inset - tall;

		return px >= left && px < left + wide && py >= top && py < top + tall;
	}

	override function took(event:Input):Bool {
		switch (event.kind) {
			case Kind.PointerDown:
				if (!onButton(event.x, event.y)) return true;

				stops();
				return true;

			case Kind.PointerMove:
				final on = onButton(event.x, event.y);
				if (on == over) return true;

				over = on;
				invalidate();
				return true;

			case _:
		}

		return true;
	}

	/**
		Asks the task to stop.
	**/
	public function stops():Void {
		if (task == null || !task.cancellable) return;

		task.cancels();
		if (onCancel != null) onCancel();

		invalidate();
	}

	/**
		@return How tall the bar itself is.
	**/
	public function barTall():Float {
		final root = root();
		return root == null ? 8 : root.metrics.whole(8);
	}

	override function paint(paint:Paint):Void {
		final root = root();
		if (root == null || root.metrics.body == null || task == null) return;

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
		paint.text(translate(task.label), x + metrics.inset,
			y + metrics.inset + font.ascent, theme.ink, alpha);

		final reach = task.reach();

		if (reach >= 0) {
			paint.reface(small);
			paint.textRight(Math.round(reach * 100) + "%", x + width - metrics.inset,
				y + metrics.inset + font.ascent, theme.dim, alpha * 0.9);
		}

		final bar = y + metrics.inset + font.height + metrics.gap;
		final tall = barTall();
		final wide = width - metrics.inset * 2;

		paint.roundedRect(x + metrics.inset, bar, wide, tall, tall * 0.5, theme.sink, alpha);

		if (reach >= 0) {
			final much = wide * reach;

			if (much > 0) {
				paint.roundedRect(x + metrics.inset, bar, much < tall ? tall : much, tall,
					tall * 0.5, theme.accent, alpha);
			}
		} else {
			final run = wide * 0.28;
			final over = (swept / SWEEP) * (wide + run) - run;
			final from = over < 0 ? 0 : over;
			final until = over + run > wide ? wide : over + run;

			if (until > from) {
				paint.roundedRect(x + metrics.inset + from, bar, until - from, tall,
					tall * 0.5, theme.accent, alpha);
			}
		}

		paint.reface(small);

		if (task.detail != "") {
			paint.pushClip(x + metrics.inset, bar + tall, wide, small.height * 2);
			paint.text(task.detail, x + metrics.inset,
				bar + tall + metrics.gap + small.ascent, theme.dim, alpha * 0.85);
			paint.popClip();
		}

		if (!cancels()) {
			paint.popTransform();
			return;
		}

		final deep = buttonTall();
		final room = buttonWide();
		final left = x + width - metrics.inset - room;
		final top = y + height - metrics.inset - deep;

		paint.roundedRect(left, top, room, deep, metrics.radiusRow, theme.raise2, alpha);

		if (over) {
			paint.roundedRect(left, top, room, deep, metrics.radiusRow, theme.accent,
				alpha * Theme.HOVER);
		}

		paint.textCentred(translate(task.stopped() ? Locale.WORKING_STOPPING
			: Locale.WORKING_CANCEL), left + room * 0.5,
			top + (deep - small.height) * 0.5 + small.ascent, theme.dim, alpha);

		paint.popTransform();
	}
}
