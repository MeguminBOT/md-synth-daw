package mdd.view;

import mdd.ui.Paint;
import mdd.ui.Tabs;
import mdd.ui.Widget;

@:unreflective
final class Inspector extends Widget {
	public static inline final CHANNEL = 0;
	public static inline final BANK = 1;
	public static inline final SCOPE = 2;

	public final session:Session;

	public final tabs:Tabs;
	public final fm:FmEditor;
	public final psg:PsgEditor;
	public final samples:Samples;
	public final presets:Presets;
	public final scope:Scope;

	public var showing(default, null):Int = CHANNEL;

	public function new(session:Session) {
		super();
		this.session = session;

		tabs = new Tabs(["", "", ""]);
		fm = new FmEditor(session);
		psg = new PsgEditor(session);
		samples = new Samples(session);
		presets = new Presets(session);
		scope = new Scope(session);

		add(tabs);
		add(fm);
		add(psg);
		add(samples);
		add(presets);
		add(scope);

		psg.visible = false;
		samples.visible = false;
		presets.visible = false;
		scope.visible = false;

		tabs.onChoose = function(which:Int):Void show(which);
	}

	public function show(which:Int):Void {
		showing = which;
		follow();
	}

	public function follow():Void {
		final part = session.part;
		final square = part.square() || part.noise();
		final sampled = part.sampled();

		final wantFm = showing == CHANNEL && !square && !sampled;
		final wantPsg = showing == CHANNEL && square;
		final wantSamples = showing == CHANNEL && sampled;
		final wantPresets = showing == BANK;
		final wantScope = showing == SCOPE;

		if (wantPresets) presets.fit();

		if (fm.visible == wantFm && psg.visible == wantPsg && samples.visible == wantSamples
				&& presets.visible == wantPresets && scope.visible == wantScope) {
			return;
		}

		fm.visible = wantFm;
		psg.visible = wantPsg;
		samples.visible = wantSamples;
		presets.visible = wantPresets;
		scope.visible = wantScope;

		relayout();
	}

	public function head():Float {
		final root = root();
		return root == null ? 30 : root.metrics.tab;
	}

	override function layout():Void {
		final tall = head();

		tabs.arrange(x, y, width, tall);
		fm.arrange(x, y + tall, width, height - tall);
		psg.arrange(x, y + tall, width, height - tall);
		samples.arrange(x, y + tall, width, height - tall);
		presets.arrange(x, y + tall, width, height - tall);
		scope.arrange(x, y + tall, width, height - tall);
	}

	function named():Void {
		final root = root();
		if (root == null) return;

		tabs.labels[0] = translate(Locale.PANEL_CHANNEL);
		tabs.labels[1] = translate(Locale.PANEL_BANK);
		tabs.labels[2] = translate(Locale.PANEL_SCOPE);
	}

	override function paint(paint:Paint):Void {
		named();

		tabs.paint(paint);

		if (fm.visible) fm.paint(paint);
		if (psg.visible) psg.paint(paint);
		if (samples.visible) samples.paint(paint);
		if (presets.visible) presets.paint(paint);
		if (scope.visible) scope.paint(paint);
	}
}
