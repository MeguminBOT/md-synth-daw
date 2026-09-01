package mdd.view;

import mdd.ui.Paint;
import mdd.ui.control.Tabs;
import mdd.ui.Widget;

@:unreflective
final class Centre extends Widget {
	public static inline final ROLL = 0;
	public static inline final SCOPE = 1;
	public static inline final SAMPLES = 2;
	public static inline final TRACKER = 3;
	public static inline final PLAYLIST = 4;

	public final session:Session;

	public final tabs:Tabs;
	public final roll:PianoRoll;
	public final scope:Scope;
	public final samples:Samples;
	public final tracker:Tracker;
	public final playlist:Playlist;

	public var showing(default, null):Int = ROLL;

	public function new(session:Session) {
		super();
		this.session = session;

		tabs = new Tabs(["", "", "", "", ""]);
		roll = new PianoRoll(session);
		scope = new Scope(session);
		samples = new Samples(session);
		tracker = new Tracker(session);
		playlist = new Playlist(session);

		add(tabs);
		add(roll);
		add(scope);
		add(samples);
		add(tracker);
		add(playlist);

		scope.visible = false;
		samples.visible = false;
		tracker.visible = false;
		playlist.visible = false;

		tabs.onChoose = function(which:Int):Void show(which);
	}

	public function show(which:Int):Void {
		if (which == showing) return;

		showing = which;
		roll.visible = which == ROLL;
		scope.visible = which == SCOPE;
		samples.visible = which == SAMPLES;
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
		scope.arrange(x, y + tall, width, height - tall);
		samples.arrange(x, y + tall, width, height - tall);
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
		tabs.labels[1] = translate(Locale.VIEW_SCOPE);
		tabs.labels[2] = translate(Locale.VIEW_SAMPLES);
		tabs.labels[3] = translate(Locale.VIEW_TRACKER);
		tabs.labels[4] = translate(Locale.VIEW_PLAYLIST);
	}

	override function paint(paint:Paint):Void {
		named();

		tabs.paint(paint);

		if (roll.visible) roll.paint(paint);
		if (scope.visible) scope.paint(paint);
		if (samples.visible) samples.paint(paint);
		if (tracker.visible) tracker.paint(paint);
		if (playlist.visible) playlist.paint(paint);
	}
}
