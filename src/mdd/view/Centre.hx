package mdd.view;

import mdd.ui.Paint;
import mdd.ui.Tabs;
import mdd.ui.Widget;

@:unreflective
final class Centre extends Widget {
	public static inline final ROLL = 0;
	public static inline final PLAYLIST = 1;

	public final session:Session;

	public final tabs:Tabs;
	public final roll:PianoRoll;
	public final playlist:Playlist;

	public var showing(default, null):Int = ROLL;

	public function new(session:Session) {
		super();
		this.session = session;

		tabs = new Tabs(["Piano roll", "Arrangement"]);
		roll = new PianoRoll(session);
		playlist = new Playlist(session);

		add(tabs);
		add(roll);
		add(playlist);

		playlist.visible = false;

		tabs.onChoose = function(which:Int):Void show(which);
	}

	public function show(which:Int):Void {
		if (which == showing) return;

		showing = which;
		roll.visible = which == ROLL;
		playlist.visible = which == PLAYLIST;

		relayout();
	}

	public function head():Float {
		final root = root();
		return root == null ? 30 : root.metrics.tab;
	}

	override function layout():Void {
		final tall = head();

		tabs.arrange(x, y, width, tall);
		roll.arrange(x, y + tall, width, height - tall);
		playlist.arrange(x, y + tall, width, height - tall);
	}

	public function playhead(tick:Int):Void {
		if (roll.playhead == tick && playlist.playhead == tick) return;

		roll.playhead = tick;
		playlist.playhead = tick;

		if (session.transport.playing) {
			if (roll.visible) roll.invalidate();
			if (playlist.visible) playlist.invalidate();
		}
	}

	override function paint(paint:Paint):Void {
		tabs.paint(paint);
		if (roll.visible) roll.paint(paint);
		if (playlist.visible) playlist.paint(paint);
	}
}
