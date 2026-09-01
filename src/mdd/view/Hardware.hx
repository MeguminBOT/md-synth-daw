package mdd.view;

import mdd.check.Budget;
import mdd.song.Part;
import mdd.ui.Metrics;
import mdd.ui.Paint;
import mdd.ui.Theme;
import mdd.ui.Widget;

@:unreflective
final class Hardware extends Widget {
	public static inline final ROWS = 4;

	public final session:Session;

	public var budget:Null<Budget> = null;

	public function new(session:Session) {
		super();
		this.session = session;
		opaque = true;
	}

	public function step():Float {
		final root = root();
		return root == null ? 24 : root.metrics.whole(24);
	}

	public function tall():Float {
		final root = root();
		final inset = root == null ? 8.0 : root.metrics.inset;

		return step() * (1 + Math.ceil(ROWS / 2)) + inset * 2;
	}

	function used(row:Int):Int {
		if (budget == null) return 0;

		return switch (row) {
			case 0: sounding(0, 6);
			case 1: budget.operators;
			case 2: sounding(6, 10);
			case _: budget.sampleBytes;
		}
	}

	function most(row:Int):Int {
		final profile = budget == null ? null : budget.profile;

		return switch (row) {
			case 0: 6;
			case 1: 24;
			case 2: 4;
			case _: profile == null ? 65536 : profile.sampleBytes;
		}
	}

	function sounding(from:Int, to:Int):Int {
		if (budget == null) return 0;

		var many = 0;
		for (index in from...to) if (budget.busy[index] > 0) many++;

		return many;
	}

	function named(row:Int):String {
		return switch (row) {
			case 0: translate(Locale.HARDWARE_FM);
			case 1: translate(Locale.HARDWARE_OPERATORS);
			case 2: translate(Locale.HARDWARE_SQUARE);
			case _: translate(Locale.HARDWARE_SAMPLE);
		}
	}

	function shown(row:Int):String {
		final held = used(row);
		final ceiling = most(row);

		if (row != ROWS - 1) return held + " / " + ceiling;

		return Math.round(held / 1024) + " / " + Math.round(ceiling / 1024) + " kb";
	}

	override function paint(paint:Paint):Void {
		final root = root();
		if (root == null || root.metrics.body == null) return;

		final theme = root.theme;
		final metrics = root.metrics;
		final font = metrics.small == null ? metrics.body : metrics.small;
		final row = step();

		paint.rect(x, y, width, height, theme.panel);
		paint.reface(font);

		paint.text(translate(Locale.HARDWARE), x + metrics.inset,
			y + metrics.inset + font.ascent, theme.dim, 0.7);

		final wide = (width - metrics.inset * 3) * 0.5;
		final barTall = metrics.whole(4);

		for (at in 0...ROWS) {
			final left = x + metrics.inset + (at % 2 == 0 ? 0 : wide + metrics.inset);
			final top = y + metrics.inset + row * (1 + Math.floor(at / 2));

			paint.text(named(at), left, top + font.ascent, theme.dim, 0.65);
			paint.textRight(shown(at), left + wide, top + font.ascent, theme.ink, 0.65);

			final ceiling = most(at);
			final part = ceiling <= 0 ? 0.0 : used(at) / ceiling;
			final full = part > 1 ? 1.0 : part;
			final line = top + font.height + metrics.whole(2);

			paint.roundedRect(left, line, wide, barTall, barTall * 0.5, theme.sink);
			if (full > 0) {
				paint.roundedRect(left, line, wide * full, barTall, barTall * 0.5,
					full >= 1 ? theme.over : theme.accent);
			}
		}
	}
}
