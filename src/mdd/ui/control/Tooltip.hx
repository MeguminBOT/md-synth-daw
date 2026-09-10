package mdd.ui.control;

@:unreflective

/**
	The one tooltip, which every widget borrows rather than owning one.

	It carries three lines: what the thing is, a detail, and the chord that reaches it.
	The detail is what makes a parameter tooltip worth having here, because it is where
	the register address and the derived value go.
**/
final class Tooltip extends Widget {
	/**
		How far from the pointer it sits, so it never covers what it is about.
	**/
	public static inline final CLEAR = 6.0;

	/**
		How far under the pointer it sits, which has to clear the cursor itself or
		the arrow stands on the first line of it.
	**/
	public static inline final BELOW = 21.0;

	/**
		What it is describing, or null.
	**/
	public var subject(default, null):Null<Widget> = null;

	/**
		How far it has faded in.
	**/
	public final fade:Motion;

	/**
		Builds a tooltip that is not showing.
	**/
	public function new() {
		super();
		fade = new Motion(this, 0, false);
	}

	/**
		Takes its three lines from a widget and sizes itself to them.

		@param subject The widget it is about, or null to clear it.
	**/
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
		if (want.shortcut != "") wide += metrics.whole(28) + font.measure(want.shortcut);

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
		paint.outline(x, y, width, height, theme.frame, metrics.whole(1), alpha,
			metrics.radiusSmall);

		paint.reface(font);
		final line = y + metrics.gap + font.ascent;
		paint.text(want.tip, x + metrics.inset, line, theme.ink, alpha);

		if (want.shortcut != "") {
			paint.textRight(want.shortcut, x + width - metrics.inset, line, theme.dim, alpha * 0.8);
		}

		if (want.detail != "") {
			paint.reface(small);
			paint.text(want.detail, x + metrics.inset, line + metrics.unit + small.height,
				theme.dim, alpha * 0.8);
		}
	}
}
