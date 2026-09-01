package mdd.ui;

@:unreflective
final class Tooltip extends Widget {
	public static inline final CLEAR = 6.0;

	public var subject(default, null):Null<Widget> = null;

	public final fade:Motion;

	public function new() {
		super();
		fade = new Motion(this, 0, false);
	}

	public function describe(subject:Null<Widget>):Void {
		this.subject = subject;
		relayout();
	}

	override function accepts(px:Float, py:Float):Bool {
		return false;
	}

	override function measure(availableWidth:Float, availableHeight:Float):Void {
		final root = root();
		final want = subject;

		if (root == null || root.metrics.body == null || want == null || want.tip == "") {
			wantWidth = 0;
			wantHeight = 0;
			return;
		}

		final metrics = root.metrics;
		final font = metrics.body;
		final small = metrics.small == null ? font : metrics.small;

		var wide = font.measure(want.tip);
		if (want.chord != "") wide += metrics.whole(28) + font.measure(want.chord);

		var tall = font.height;

		if (want.detail != "") {
			final under = small.measure(want.detail);
			if (under > wide) wide = under;
			tall += small.height + metrics.unit;
		}

		wantWidth = wide + metrics.inset * 2;
		wantHeight = tall + metrics.gap * 2;
	}

	override function paint(paint:Paint):Void {
		final root = root();
		final want = subject;

		if (root == null || root.metrics.body == null || want == null || want.tip == "") return;

		final alpha = fade.value;
		if (alpha <= 0.004) return;

		final theme = root.theme;
		final metrics = root.metrics;
		final font = metrics.body;
		final small = metrics.small == null ? font : metrics.small;

		paint.roundedRect(x, y, width, height, metrics.radiusSmall, theme.raise2, alpha);
		paint.outline(x, y, width, height, theme.frame, metrics.whole(1), alpha);

		paint.reface(font);
		final line = y + metrics.gap + font.ascent;
		paint.text(want.tip, x + metrics.inset, line, theme.ink, alpha);

		if (want.chord != "") {
			paint.textRight(want.chord, x + width - metrics.inset, line, theme.dim, alpha * 0.8);
		}

		if (want.detail != "") {
			paint.reface(small);
			paint.text(want.detail, x + metrics.inset, line + metrics.unit + small.height,
				theme.dim, alpha * 0.8);
		}
	}
}
