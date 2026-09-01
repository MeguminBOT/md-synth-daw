package mdd.view;

import mdd.ui.Paint;
import mdd.ui.Tabs;
import mdd.ui.Widget;

@:unreflective
final class Inspector extends Widget {
	public static inline final CHANNEL = 0;
	public static inline final SCOPE = 1;

	public final session:Session;

	public final tabs:Tabs;
	public final fm:FmEditor;
	public final psg:PsgEditor;
	public final scope:Scope;

	public var showing(default, null):Int = CHANNEL;

	public function new(session:Session) {
		super();
		this.session = session;

		tabs = new Tabs(["Channel", "Scope"]);
		fm = new FmEditor(session);
		psg = new PsgEditor(session);
		scope = new Scope(session);

		add(tabs);
		add(fm);
		add(psg);
		add(scope);

		psg.visible = false;
		scope.visible = false;

		tabs.onChoose = function(which:Int):Void show(which);
	}

	public function show(which:Int):Void {
		showing = which;
		follow();
	}

	public function follow():Void {
		final square = session.part.square() || session.part.noise();

		final wantFm = showing == CHANNEL && !square;
		final wantPsg = showing == CHANNEL && square;
		final wantScope = showing == SCOPE;

		if (fm.visible == wantFm && psg.visible == wantPsg && scope.visible == wantScope) return;

		fm.visible = wantFm;
		psg.visible = wantPsg;
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
		scope.arrange(x, y + tall, width, height - tall);
	}

	override function paint(paint:Paint):Void {
		tabs.paint(paint);

		if (fm.visible) fm.paint(paint);
		if (psg.visible) psg.paint(paint);
		if (scope.visible) scope.paint(paint);
	}
}
