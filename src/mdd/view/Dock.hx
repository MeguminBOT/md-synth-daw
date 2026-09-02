package mdd.view;

import mdd.ui.Metrics;
import mdd.ui.Paint;
import mdd.ui.control.Tabs;
import mdd.ui.Theme;
import mdd.ui.Widget;

@:unreflective
final class Dock extends Widget {
	public static inline final PATTERNS = 0;
	public static inline final MIXER = 1;
	public static inline final WARNINGS = 2;
	public static inline final TABS = 3;

	public final session:Session;

	public final tabs:Tabs;
	public final patterns:Patterns;
	public final mixer:Mixer;
	public final warnings:Warnings;

	public var said:String = "";
	public var showing(default, null):Int = PATTERNS;

	public function new(session:Session) {
		super();
		this.session = session;

		tabs = new Tabs(["", "", ""]);
		patterns = new Patterns(session);
		mixer = new Mixer(session);
		warnings = new Warnings(session);

		add(tabs);
		add(patterns);
		add(mixer);
		add(warnings);

		mixer.visible = false;
		warnings.visible = false;

		tabs.onChoose = function(which:Int):Void show(which);
	}

	public function show(which:Int):Void {
		if (which == showing) return;

		if (which < 0 || which >= TABS) return;

		showing = which;
		tabs.select(which);
		patterns.visible = which == PATTERNS;
		mixer.visible = which == MIXER;
		warnings.visible = which == WARNINGS;

		relayout();
	}

	public function head():Float {
		final root = root();
		return root == null ? 30 : root.metrics.tab;
	}

	public function foot():Float {
		final root = root();
		return root == null ? 24 : root.metrics.whole(24);
	}

	override function layout():Void {
		final top = head();
		final bottom = foot();
		final tall = height - top - bottom;

		tabs.arrange(x, y, width, top);
		patterns.arrange(x, y + top, width, tall);
		mixer.arrange(x, y + top, width, tall);
		warnings.arrange(x, y + top, width, tall);
	}

	function named():Void {
		final root = root();
		if (root == null) return;

		tabs.labels[0] = translate(Locale.VIEW_PATTERNS);
		tabs.labels[1] = translate(Locale.VIEW_MIXER);
		tabs.labels[2] = translate(Locale.VIEW_WARNINGS);
	}

	override function paint(paint:Paint):Void {
		named();

		final root = root();
		if (root == null || root.metrics.body == null) return;

		final theme = root.theme;
		final metrics = root.metrics;

		tabs.paint(paint);

		if (patterns.visible) patterns.paint(paint);
		if (mixer.visible) mixer.paint(paint);
		if (warnings.visible) warnings.paint(paint);

		final bottom = foot();
		final top = y + height - bottom;

		paint.rect(x, top, width, bottom, theme.sink);

		final font = metrics.small == null ? metrics.body : metrics.small;
		paint.reface(font);

		paint.text(said, x + metrics.inset, top + (bottom - font.height) * 0.5 + font.ascent,
			theme.dim, 0.8);

		final count = warnings.found();

		if (count > 0) {
			paint.textRight(count + " " + translate(count == 1
				? Locale.PANEL_WARNING : Locale.PANEL_WARNINGS),
				x + width - metrics.inset, top + (bottom - font.height) * 0.5 + font.ascent,
				theme.warn, 0.9);
		}
	}
}
