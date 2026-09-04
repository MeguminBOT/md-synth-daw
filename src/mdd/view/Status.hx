package mdd.view;

import mdd.app.Locale;
import mdd.app.Session;
import mdd.ui.Paint;
import mdd.ui.Widget;

@:unreflective
final class Status extends Widget {
	public final session:Session;
	public final warnings:mdd.view.monitor.Warnings;

	public var said:String = "";

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

		final count = warnings.found();
		if (count <= 0) return;

		paint.textRight(count + " " + translate(count == 1
			? Locale.PANEL_WARNING : Locale.PANEL_WARNINGS),
			x + width - metrics.inset, y + (height - font.height) * 0.5 + font.ascent,
			theme.warn, 0.9);
	}
}
