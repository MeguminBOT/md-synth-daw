package mdd.view;

import mdd.ui.Paint;
import mdd.ui.Tabs;
import mdd.ui.Widget;

@:unreflective
final class Centre extends Widget {
	public static inline final ROLL = 0;
	public static inline final TRACKER = 1;
	public static inline final PLAYLIST = 2;

	public final session:Session;

	public final tabs:Tabs;
	public final roll:PianoRoll;
	public final tracker:Tracker;
	public final playlist:Playlist;

	public var showing(default, null):Int = ROLL;

	public function new(session:Session) {
		super();
		this.session = session;

		tabs = new Tabs(["", "", ""]);
		roll = new PianoRoll(session);
		tracker = new Tracker(session);
		playlist = new Playlist(session);

		add(tabs);
		add(roll);
		add(tracker);
		add(playlist);

		tracker.visible = false;
		playlist.visible = false;

		tabs.onChoose = function(which:Int):Void show(which);
	}

	public function show(which:Int):Void {
		if (which == showing) return;

		showing = which;
		roll.visible = which == ROLL;
		tracker.visible = which == TRACKER;
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
		tracker.arrange(x, y + tall, width, height - tall);
		playlist.arrange(x, y + tall, width, height - tall);
	}

	public function playhead(tick:Int):Void {
		if (roll.playhead == tick && playlist.playhead == tick) return;

		roll.playhead = tick;
		playlist.playhead = tick;

		if (!session.transport.playing) return;

		if (roll.visible) roll.invalidate();
		if (playlist.visible) playlist.invalidate();

		if (!tracker.visible) return;

		final step = tracker.step();
		final row = Std.int(tick / (step < 1 ? 1 : step));

		if (row == tracker.row) return;

		tracker.follow(row);
	}

	function named():Void {
		final root = root();
		if (root == null) return;

			tabs.labels[0] = translate(Locale.VIEW_ROLL);
			tabs.labels[1] = translate(Locale.VIEW_TRACKER);
			tabs.labels[2] = translate(Locale.VIEW_ARRANGEMENT);
	}

	override function paint(paint:Paint):Void {
		named();

		tabs.paint(paint);

		if (roll.visible) roll.paint(paint);
		if (tracker.visible) tracker.paint(paint);
		if (playlist.visible) playlist.paint(paint);
	}
}
