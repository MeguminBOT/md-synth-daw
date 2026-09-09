package mdd.view;

import mdd.app.Locale;
import mdd.app.Session;
import mdd.ui.Paint;
import mdd.ui.Widget;

@:unreflective

/**
	The bar along the bottom: what just happened, what the machine is costing, and how
	many warnings there are.
**/
final class Status extends Widget {
	/**
		The session to read.
	**/
	public final session:Session;

	/**
		The warnings panel, so the count can be shown and clicked through to.
	**/
	public final warnings:mdd.view.monitor.Warnings;

	/**
		The line about what just happened.
	**/
	public var said:String = "";

	/**
		What this process is costing the machine.
	**/
	public var usage:String = "";

	/**
		Builds the status bar.

		@param session The session to read.
		@param warnings The warnings panel to count and reach.
	**/
	public function new(session:Session, warnings:mdd.view.monitor.Warnings) {
		super();

		this.session = session;
		this.warnings = warnings;
	}

	override function paint(paint:Paint):Void {
		final root = root();
		if (root == null || root.metrics.body == null) return;

		final theme = root.theme;
		final metrics = root.metrics;
		final font = metrics.small == null ? metrics.body : metrics.small;

		paint.rect(x, y, width, height, theme.sink);
		paint.reface(font);

		paint.text(said, x + metrics.inset, y + (height - font.height) * 0.5 + font.ascent,
			theme.dim, 0.8);

		final line = y + (height - font.height) * 0.5 + font.ascent;
		var right = x + width - metrics.inset;

		final count = warnings.found();

		if (count > 0) {
			final much = count + " " + translate(count == 1
				? Locale.PANEL_WARNING : Locale.PANEL_WARNINGS);

			paint.textRight(much, right, line, theme.warn, 0.9);
			right -= paint.measure(much) + metrics.inset * 2;
		}

		if (usage == "") return;

		final small = metrics.small == null ? font : metrics.small;

		paint.reface(small);
		paint.textRight(usage, right, line, theme.dim, 0.55);
	}
}
