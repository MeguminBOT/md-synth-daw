package mdd.view;

import mdd.ui.Metrics;
import mdd.ui.Paint;
import mdd.ui.Tabs;
import mdd.ui.Theme;
import mdd.ui.Widget;

@:unreflective
final class Dock extends Widget {
	public static inline final MIXER = 0;
	public static inline final WARNINGS = 1;

	public final session:Session;

	public final tabs:Tabs;
	public final mixer:Mixer;
	public final warnings:Warnings;

	public var said:String = "";
	public var showing(default, null):Int = MIXER;

	public function new(session:Session) {
		super();
		this.session = session;

		tabs = new Tabs(["Mixer", "Warnings"]);
		mixer = new Mixer(session);
		warnings = new Warnings(session);

		add(tabs);
		add(mixer);
		add(warnings);

		warnings.visible = false;

		tabs.onChoose = function(which:Int):Void show(which);
	}

	public function show(which:Int):Void {
		if (which == showing) return;

		showing = which;
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
		return root == null ? 20 : root.metrics.whole(20);
	}

	override function layout():Void {
		final top = head();
		final bottom = foot();
		final tall = height - top - bottom;

		tabs.arrange(x, y, width, top);
		mixer.arrange(x, y + top, width, tall);
		warnings.arrange(x, y + top, width, tall);
	}

	override function paint(paint:Paint):Void {
		final root = root();
		if (root == null || root.metrics.body == null) return;

		final theme = root.theme;
		final metrics = root.metrics;

		tabs.paint(paint);

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
			paint.textRight(count + (count == 1 ? " warning" : " warnings"),
				x + width - metrics.inset, top + (bottom - font.height) * 0.5 + font.ascent,
				theme.warn, 0.9);
		}
	}
}
