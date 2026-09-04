package mdd.view.monitor;

import haxe.ds.Vector;
import mdd.app.Locale;
import mdd.app.Session;
import mdd.check.Budget;
import mdd.ui.Metrics;
import mdd.ui.Paint;
import mdd.ui.Theme;
import mdd.ui.Widget;

@:unreflective
final class Hardware extends Widget {
	public static inline final ROWS = 4;
	public static inline final AUDIBLE = 0.02;

	public final session:Session;

	public var budget:Null<Budget> = null;
	public var levels:Null<Vector<Float>> = null;

	public function new(session:Session) {
		super();
		this.session = session;
		opaque = true;
	}

	public function step():Float {
		final root = root();
		return root == null ? 26 : root.metrics.whole(26);
	}

	public function head():Float {
		final root = root();
		return root == null ? 24 : root.metrics.whole(24);
	}

	public function tall():Float {
		final root = root();
		final inset = root == null ? 8.0 : root.metrics.inset;

		return head() + step() * Math.ceil(ROWS / 2) + inset;
	}

	public function live():Bool {
		return levels != null && session.transport.playing;
	}

	function loud(from:Int, to:Int):Int {
		final held = levels;
		if (held == null) return 0;

		var many = 0;
		for (index in from...to) if (held[index] > AUDIBLE) many++;

		return many;
	}

	function operators():Int {
		final held = levels;
		if (held == null) return 0;

		var many = 0;

		for (index in 0...6) {
			if (held[index] <= AUDIBLE) continue;

			final instrument = session.song.instrumentAt(session.song.rack[index]);
			final patch = instrument == null ? null : instrument.patch;

			if (patch == null) {
				many += 4;
				continue;
			}

			for (slot in 0...4) if (patch.totalLevel[slot] < 127) many++;
		}

		return many;
	}

	function used(row:Int):Int {
		if (budget == null) return 0;

		if (live()) {
			return switch (row) {
				case 0: loud(0, 6);
				case 1: operators();
				case 2: loud(6, 10);
				case _: budget.sampleBytes;
			}
		}

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
		final hair = metrics.whole(1);

		paint.rect(x, y, width, height, theme.panel);
		paint.rect(x, y, width, head(), theme.bar);
		paint.rect(x, y, width, hair, theme.frame);
		paint.rect(x, y + head() - hair, width, hair, theme.frame, 0.6);

		paint.reface(font);

		paint.text(translate(Locale.HARDWARE), x + metrics.inset,
			y + (head() - font.height) * 0.5 + font.ascent, theme.dim, 0.8);

		paint.textRight(translate(live() ? Locale.HARDWARE_NOW : Locale.HARDWARE_SONG),
			x + width - metrics.inset, y + (head() - font.height) * 0.5 + font.ascent,
			live() ? theme.accent : theme.dim, 0.8);

		final wide = (width - metrics.inset * 3) * 0.5;
		final barTall = metrics.whole(4);

		for (at in 0...ROWS) {
			final left = x + metrics.inset + (at % 2 == 0 ? 0 : wide + metrics.inset);
			final top = y + head() + row * Math.floor(at / 2);

			paint.text(named(at), left, top + font.ascent, theme.dim, 0.7);
			paint.textRight(shown(at), left + wide, top + font.ascent, theme.ink, 0.8);

			final ceiling = most(at);
			final part = ceiling <= 0 ? 0.0 : used(at) / ceiling;
			final full = part > 1 ? 1.0 : part;
			final line = top + font.height + metrics.whole(2);

			paint.roundedRect(left, line, wide, barTall, barTall * 0.5, theme.sink);
			if (full > 0) {
				final ink = part > 1 ? theme.over : theme.accent;

				paint.roundedGradient(left, line, wide * full, barTall, barTall * 0.5,
					ink.lift(0.20), ink.sink(0.16));
			}
		}
	}
}
