package mdd.view;

import mdd.app.Locale;
import mdd.app.Session;
import mdd.ui.Paint;
import mdd.ui.control.Tabs;
import mdd.ui.Widget;
import mdd.view.editor.FmEditor;
import mdd.view.editor.Presets;
import mdd.view.editor.PsgEditor;
import mdd.view.editor.Samples;

@:unreflective

/**
	The panel down the right: the editor for whichever kind of part is chosen, or the
	preset browser.

	Which editor it shows follows the chosen part rather than being picked, so choosing
	a square channel puts the square editor up without anybody asking for it.
**/
final class Inspector extends Widget {
	/**
		Tab: the editor for the chosen part.
	**/
	public static inline final CHANNEL = 0;

	/**
		Tab: the preset browser.
	**/
	public static inline final PRESETS = 1;

	/**
		How many tabs there are.
	**/
	public static inline final TABS = 2;

	/**
		The session to read.
	**/
	public final session:Session;

	/**
		The tab strip.
	**/
	public final tabs:Tabs;

	/**
		The FM operator editor.
	**/
	public final fm:FmEditor;

	/**
		The square editor.
	**/
	public final psg:PsgEditor;

	/**
		The sample editor.
	**/
	public final samples:Samples;

	/**
		The preset browser.
	**/
	public final presets:Presets;

	/**
		Which tab is showing.
	**/
	public var showing(default, null):Int = CHANNEL;

	/**
		Builds the inspector and every editor in it.

		@param session The session to read.
	**/
	public function new(session:Session) {
		super();
		this.session = session;

		tabs = new Tabs(["", ""]);
		fm = new FmEditor(session);
		psg = new PsgEditor(session);
		samples = new Samples(session);
		presets = new Presets(session);

		add(tabs);
		add(fm);
		add(psg);
		add(samples);
		add(presets);

		psg.visible = false;
		samples.visible = false;
		presets.visible = false;

		tabs.onChoose = function(which:Int):Void show(which);
	}

	/**
		Shows one tab.

		@param which Which tab.
	**/
	public function show(which:Int):Void {
		if (which < 0 || which >= TABS) return;

		showing = which;
		tabs.select(which);
		follow();
	}

	/**
		Shows the editor that goes with the chosen part.
	**/
	public function follow():Void {
		final part = session.part;
		final square = part.square() || part.noise();
		final sampled = part.sampled();

		final wantFm = showing == CHANNEL && !square && !sampled;
		final wantPsg = showing == CHANNEL && square;
		final wantSamples = showing == CHANNEL && sampled;
		final wantPresets = showing == PRESETS;

		if (wantPresets) presets.fit();

		if (fm.visible == wantFm && psg.visible == wantPsg && samples.visible == wantSamples
				&& presets.visible == wantPresets) {
			return;
		}

		fm.visible = wantFm;
		psg.visible = wantPsg;
		samples.visible = wantSamples;
		presets.visible = wantPresets;

		relayout();
	}

	/**
		@return How tall the tab strip is.
	**/
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
	}

	function named():Void {
		final root = root();
		if (root == null) return;

		tabs.labels[0] = translate(Locale.PANEL_SYNTH);
		tabs.labels[1] = translate(Locale.PANEL_PRESETS);
	}

	override function paint(paint:Paint):Void {
		named();

		tabs.paint(paint);

		if (fm.visible) fm.paint(paint);
		if (psg.visible) psg.paint(paint);
		if (samples.visible) samples.paint(paint);
		if (presets.visible) presets.paint(paint);
	}
}
