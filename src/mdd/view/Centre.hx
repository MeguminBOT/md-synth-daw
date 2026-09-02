package mdd.view;

import mdd.ui.Paint;
import mdd.ui.control.Tabs;
import mdd.ui.Widget;

@:unreflective
final class Centre extends Widget {
	public static inline final PLAYLIST = 0;
	public static inline final ROLL = 1;
	public static inline final TRACKER = 2;
	public static inline final SCOPE = 3;
	public static inline final REGISTERS = 4;

	public final session:Session;

	public final tabs:Tabs;
	public final tools:Tools;
	public final roll:PianoRoll;
	public final scope:Scope;
	public final tracker:Tracker;
	public final playlist:Playlist;
	public final registers:Registers;

	public var showing(default, null):Int = PLAYLIST;

	public function new(session:Session) {
		super();
		this.session = session;

		tabs = new Tabs(["", "", "", "", ""]);
		tools = new Tools(session);
		roll = new PianoRoll(session);
		scope = new Scope(session);
		tracker = new Tracker(session);
		playlist = new Playlist(session);
		registers = new Registers(session);

		add(tabs);
		add(tools);
		add(roll);
		add(scope);
		add(tracker);
		add(playlist);
		add(registers);

		scope.visible = false;
		tracker.visible = false;
		roll.visible = false;
		registers.visible = false;

		tabs.onChoose = function(which:Int):Void show(which);
	}

	public function show(which:Int):Void {
		if (which == showing) return;

		showing = which;
		tabs.select(which);
		playlist.visible = which == PLAYLIST;
		roll.visible = which == ROLL;
		scope.visible = which == SCOPE;
		tracker.visible = which == TRACKER;
		registers.visible = which == REGISTERS;

		relayout();
	}

	public function head():Float {
		final root = root();
		return root == null ? 30 : root.metrics.tab;
	}

	override function layout():Void {
		final tall = head();

		tools.room = width * 0.45;

		final room = tools.wide();

		tabs.arrange(x, y, width - room, tall);
		tools.arrange(x + width - room, y, room, tall);
		roll.arrange(x, y + tall, width, height - tall);
		scope.arrange(x, y + tall, width, height - tall);
		tracker.arrange(x, y + tall, width, height - tall);
		playlist.arrange(x, y + tall, width, height - tall);
		registers.arrange(x, y + tall, width, height - tall);
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

		tabs.labels[0] = translate(Locale.VIEW_PLAYLIST);
		tabs.labels[1] = translate(Locale.VIEW_ROLL);
		tabs.labels[2] = translate(Locale.VIEW_TRACKER);
		tabs.labels[3] = translate(Locale.VIEW_SCOPE);
		tabs.labels[4] = translate(Locale.VIEW_REGISTERS);
	}

	override function paint(paint:Paint):Void {
		named();

		tabs.paint(paint);
		tools.paint(paint);

		if (roll.visible) roll.paint(paint);
		if (scope.visible) scope.paint(paint);
		if (tracker.visible) tracker.paint(paint);
		if (playlist.visible) playlist.paint(paint);
		if (registers.visible) registers.paint(paint);
	}
}
