package mdd.view;

import mdd.app.Locale;
import mdd.app.Session;
import mdd.view.Tools;
import mdd.ui.Paint;
import mdd.ui.control.Tabs;
import mdd.ui.Widget;
import mdd.view.editor.PianoRoll;
import mdd.view.editor.Playlist;
import mdd.view.editor.Tracker;
import mdd.view.monitor.Registers;
import mdd.view.monitor.Scope;

@:unreflective

/**
	The working area: the tabs across the top, the tools beside them, and whichever
	editor is showing under both.

	Every editor is built at start and kept, so switching tabs is instant and nothing
	loses where it was scrolled to.
**/
final class Centre extends Widget {
	/**
		Tab: the arrangement.
	**/
	public static inline final PLAYLIST = 0;

	/**
		Tab: the piano roll.
	**/
	public static inline final ROLL = 1;

	/**
		Tab: the same pattern as hexadecimal rows.
	**/
	public static inline final TRACKER = 2;

	/**
		Tab: the waveform and the spectrum.
	**/
	public static inline final SCOPE = 3;
	static inline final REGISTERS = 4;

	/**
		Tab: the automation editor.
	**/
	public static inline final AUTOMATION = 5;

	/**
		Tab: what the hardware will not do.
	**/
	public static inline final WARNINGS = 6;

	/**
		How many tabs there are.
	**/
	public static inline final TABS = 7;

	/**
		The session every editor reads.
	**/
	public final session:Session;

	/**
		The tab strip.
	**/
	public final tabs:Tabs;

	/**
		The tool buttons beside it.
	**/
	public final tools:Tools;

	/**
		The piano roll.
	**/
	public final roll:PianoRoll;

	/**
		The scope.
	**/
	public final scope:Scope;

	/**
		The tracker.
	**/
	public final tracker:Tracker;

	/**
		The playlist.
	**/
	public final playlist:Playlist;

	/**
		The register timeline.
	**/
	public final registers:Registers;

	/**
		The automation editor.
	**/
	public final automation:mdd.view.editor.AutomationEditor;

	/**
		The warnings list.
	**/
	public final warnings:mdd.view.monitor.Warnings;

	/**
		Which tab is showing.
	**/
	public var showing(default, null):Int = PLAYLIST;

	/**
		Builds the working area and every editor in it.

		@param session The session to read.
	**/
	public function new(session:Session) {
		super();
		this.session = session;

		tabs = new Tabs(["", "", "", "", "", "", ""]);
		tools = new Tools(session);
		tools.allowed = ALLOWS[PLAYLIST];
		roll = new PianoRoll(session);
		scope = new Scope(session);
		tracker = new Tracker(session);
		playlist = new Playlist(session);
		registers = new Registers(session);
		automation = new mdd.view.editor.AutomationEditor(session);
		warnings = new mdd.view.monitor.Warnings(session);

		add(tabs);
		add(tools);
		add(roll);
		add(scope);
		add(tracker);
		add(playlist);
		add(registers);
		add(automation);
		add(warnings);

		scope.visible = false;
		tracker.visible = false;
		roll.visible = false;
		registers.visible = false;
		automation.visible = false;
		warnings.visible = false;

		tabs.onChoose = function(which:Int):Void show(which);
	}

	static final ALLOWS:Array<Int> = [
		(1 << Session.SELECT) | (1 << Session.DRAW) | (1 << Session.ERASE)
			| (1 << Session.SLICE) | (1 << Session.PAN) | (1 << Tools.SNAP),
		Tools.EVERY,
		1 << Tools.SNAP,
		0,
		0,
		(1 << Session.SELECT) | (1 << Session.DRAW) | (1 << Session.ERASE)
			| (1 << Session.PAN) | (1 << Tools.SNAP),
		0
	];

	/**
		Shows one tab and hides the rest.

		@param which Which tab.
	**/
	public function show(which:Int):Void {
		if (which < 0 || which >= TABS || which == showing) return;

		showing = which;
		tools.allowed = ALLOWS[which];
		tabs.select(which);
		playlist.visible = which == PLAYLIST;
		roll.visible = which == ROLL;
		scope.visible = which == SCOPE;
		tracker.visible = which == TRACKER;
		registers.visible = which == REGISTERS;
		automation.visible = which == AUTOMATION;
		warnings.visible = which == WARNINGS;

		relayout();
	}

	/**
		@return How tall the tab strip is, so an editor knows where it starts.
	**/
	public function head():Float {
		final root = root();
		return root == null ? 30 : root.metrics.tab;
	}

	override function layout():Void {
		final tall = head();

		tools.room = width * 0.45;

		final room = tools.wide();

		tools.visible = room > 0;

		tabs.arrange(x, y, width - room, tall);
		tools.arrange(x + width - room, y, room, tall);
		roll.arrange(x, y + tall, width, height - tall);
		scope.arrange(x, y + tall, width, height - tall);
		tracker.arrange(x, y + tall, width, height - tall);
		playlist.arrange(x, y + tall, width, height - tall);
		registers.arrange(x, y + tall, width, height - tall);
		automation.arrange(x, y + tall, width, height - tall);
		warnings.arrange(x, y + tall, width, height - tall);
	}

	/**
		Scrolls whichever editor is showing to keep the playhead in view.

		@param tick Where the playhead is.
	**/
	public function playhead(tick:Int):Void {
		if (roll.playhead == tick && playlist.playhead == tick
			&& automation.playhead == tick) return;

		roll.playhead = tick;
		playlist.playhead = tick;
		automation.playhead = tick;

		if (!session.transport.playing) return;

		if (roll.visible) roll.invalidate();
		if (playlist.visible) playlist.invalidate();
		if (automation.visible) automation.invalidate();

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
		tabs.labels[5] = translate(Locale.VIEW_AUTOMATION);
		tabs.labels[6] = translate(Locale.VIEW_WARNINGS);
	}

	override function paint(paint:Paint):Void {
		named();

		tabs.paint(paint);
		if (tools.visible) tools.paint(paint);

		if (roll.visible) roll.paint(paint);
		if (scope.visible) scope.paint(paint);
		if (tracker.visible) tracker.paint(paint);
		if (playlist.visible) playlist.paint(paint);
		if (registers.visible) registers.paint(paint);
		if (automation.visible) automation.paint(paint);
		if (warnings.visible) warnings.paint(paint);
	}
}
