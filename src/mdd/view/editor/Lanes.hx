package mdd.view.editor;

import haxe.ds.Vector;
import mdd.app.Locale;
import mdd.app.Session;
import mdd.song.Automation;
import mdd.song.Part;
import mdd.song.Point;
import mdd.song.edit.AddPoint;
import mdd.song.edit.MovePoint;
import mdd.song.edit.RemovePoint;
import mdd.song.edit.ShapePoint;
import mdd.ui.Input;
import mdd.ui.Key;
import mdd.ui.Kind;
import mdd.ui.Metrics;
import mdd.ui.Paint;
import mdd.ui.Pointer;
import mdd.ui.Theme;
import mdd.ui.Widget;
import mdd.view.Parameter;

@:unreflective
final class Lanes extends Widget {
	public static inline final LEAST_ROW = 40;
	public static inline final MOST_ROW = 220;
	public static inline final ROW = 74;

	public static inline final REACH = 5;
	public static inline final TRACE = 512;

	public final session:Session;

	public final targets:Array<Int> = [];

	public var perTick:Float = 0.25;
	public var offsetX:Float = 0;
	public var left:Float = 0;
	public var rowTall:Float = 0;

	public var onOffer:Null<(Lanes, Int, Float, Float) -> Void> = null;
	public var onShape:Null<(Lanes, Int, Point, Float, Float) -> Void> = null;

	public var holding:Null<mdd.song.Clip> = null;
	public var playhead:Int = -1;
	public var chosen(default, null):Null<Point> = null;
	public var chosenAt(default, null):Int = -1;

	var hoverRow:Int = -1;
	var dragging:Null<Point> = null;
	var draggingAt:Int = -1;
	var bending:Int = -1;
	var bentFrom:Float = 0;
	var bentWas:Int = 0;
	var wasAt:Int = 0;
	var wasValue:Int = 0;

	final trace:Vector<Float> = new Vector<Float>(TRACE * 2);

	public function new(session:Session) {
		super();
		this.session = session;

		focusable = true;
	}

	public inline function rows():Int {
		return holding == null ? targets.length : 1;
	}

	inline function driven():Null<Automation> {
		return holding == null ? null : holding.line;
	}

	inline function drivenPart():Part {
		return holding == null ? session.part : (holding.part:Part);
	}

	public function rowHeight():Float {
		if (rowTall > 0) return rowTall;

		final root = root();
		return root == null ? ROW : root.metrics.whole(ROW);
	}

	public function wants():Float {
		return rows() * rowHeight();
	}

	public inline function targetOf(row:Int):Int {
		return targets[row] >> 8;
	}

	inline function targeted(row:Int):Int {
		final line = driven();
		return line == null ? targetOf(row) : line.target;
	}

	inline function slotted(row:Int):Int {
		final line = driven();
		return line == null ? slotOf(row) : line.slot;
	}

	public inline function slotOf(row:Int):Int {
		return targets[row] & 0xFF;
	}

	public function shows(target:Int, slot:Int):Bool {
		return targets.indexOf((target << 8) | slot) >= 0;
	}

	public function show(target:Int, slot:Int):Void {
		final want = (target << 8) | slot;
		if (targets.indexOf(want) >= 0) return;

		targets.push(want);
		relayout();
	}

	public function hide(row:Int):Void {
		if (row < 0 || row >= targets.length) return;

		targets.splice(row, 1);
		chosen = null;
		chosenAt = -1;

		relayout();
	}

	public function swap(row:Int, target:Int, slot:Int):Void {
		if (row < 0 || row >= targets.length) return;

		targets[row] = (target << 8) | slot;
		chosen = null;
		chosenAt = -1;

		invalidate();
	}

	public function rowAt(py:Float):Int {
		final tall = rowHeight();
		if (tall <= 0) return -1;

		final at = Std.int((py - y) / tall);
		return at < 0 || at >= rows() ? -1 : at;
	}

	public inline function rowTop(row:Int):Float {
		return y + row * rowHeight();
	}

	public inline function tickAt(px:Float):Int {
		return Math.round((px - x - left + offsetX) / perTick);
	}

	public inline function atTick(tick:Int):Float {
		return x + left - offsetX + tick * perTick;
	}

	public function parameterOf(row:Int):Null<Parameter> {
		if (row < 0 || row >= rows()) return null;

		final line = driven();
		if (line != null) return Parameter.found(drivenPart(), line.target, line.slot);

		return Parameter.found(session.part, targetOf(row), slotOf(row));
	}

	public function lineOf(row:Int):Null<Automation> {
		if (holding != null) return row == 0 ? holding.line : null;

		final pattern = session.current();
		if (pattern == null || row < 0 || row >= rows()) return null;

		final target = targetOf(row);
		final slot = slotOf(row);

		for (held in pattern.lane(session.part).automation) {
			if (held.held(target, slot)) return held;
		}

		return null;
	}

	function atValue(row:Int, value:Int):Float {
		final held = parameterOf(row);
		if (held == null) return rowTop(row);

		final span = held.high - held.low;
		if (span <= 0) return rowTop(row);

		final inset = padding();
		final room = rowHeight() - inset * 2;
		final part = (value - held.low) / span;

		return rowTop(row) + inset + room * (1 - part);
	}

	function valueAt(row:Int, py:Float):Int {
		final held = parameterOf(row);
		if (held == null) return 0;

		final inset = padding();
		final room = rowHeight() - inset * 2;
		if (room <= 0) return held.low;

		var part = 1 - (py - rowTop(row) - inset) / room;
		if (part < 0) part = 0;
		if (part > 1) part = 1;

		return held.holds(held.low + Math.round((held.high - held.low) * part));
	}

	function padding():Float {
		final root = root();
		return root == null ? 12 : root.metrics.whole(12);
	}

	public function pointAt(row:Int, px:Float, py:Float):Null<Point> {
		final line = lineOf(row);
		if (line == null) return null;

		final root = root();
		final reach = root == null ? REACH : root.metrics.whole(REACH);

		var found:Null<Point> = null;
		var least = reach * reach * 4;

		for (point in line.points) {
			final dx = atTick(point.at) - px;
			final dy = atValue(row, point.value) - py;
			final away = dx * dx + dy * dy;

			if (away > least) continue;

			least = away;
			found = point;
		}

		return found;
	}

	public function bendAt(row:Int, px:Float, py:Float):Int {
		final line = lineOf(row);
		if (line == null || line.points.length < 2) return -1;

		final root = root();
		final reach = root == null ? REACH : root.metrics.whole(REACH);
		final held = parameterOf(row);

		for (index in 0...line.points.length - 1) {
			final from = line.points[index];
			if (!Automation.moves(from.shape)) continue;
			if (held != null && !held.smooth) continue;

			final to = line.points[index + 1];
			final middle = Std.int((from.at + to.at) / 2);

			final dx = atTick(middle) - px;
			final dy = atValue(row, Automation.between(from, to, middle)) - py;

			if (dx * dx + dy * dy > reach * reach * 4) continue;

			return index;
		}

		return -1;
	}

	override function took(event:Input):Bool {
		switch (event.kind) {
			case Kind.PointerDown:
				return pressed(event);

			case Kind.PointerMove:
				return moved(event);

			case Kind.PointerUp:
				dragging = null;
				bending = -1;
				return true;

			case Kind.KeyDown:
				if (event.code != Key.Delete && event.code != Key.Backspace) return false;
				return erased();

			case _:
		}

		return false;
	}

	function pressed(event:Input):Bool {
		final row = rowAt(event.y);
		if (row < 0) return false;

		if (event.x < x + left) {
			if (onOffer != null) onOffer(this, row, event.x, event.y);
			return true;
		}

		final point = pointAt(row, event.x, event.y);

		if (event.button == Pointer.Right) {
			if (point == null || onShape == null) return true;

			chosen = point;
			chosenAt = row;
			onShape(this, row, point, event.x, event.y);

			return true;
		}

		if (point != null) {
			chosen = point;
			chosenAt = row;
			dragging = point;
			draggingAt = row;
			wasAt = point.at;
			wasValue = point.value;

			invalidate();
			return true;
		}

		final bend = bendAt(row, event.x, event.y);

		if (bend >= 0) {
			final line = lineOf(row);
			if (line == null) return true;

			bending = row;
			bentFrom = event.y;
			bentWas = line.points[bend].tension;
			chosen = line.points[bend];
			chosenAt = row;

			invalidate();
			return true;
		}

		added(row, event.x, event.y);
		return true;
	}

	function added(row:Int, px:Float, py:Float):Void {
		final held = parameterOf(row);
		if (held == null) return;
		if (holding == null && session.current() == null) return;

		var tick = session.snapped(tickAt(px));
		if (tick < 0) tick = 0;

		final line = lineOf(row);
		if (line != null && line.marks(tick)) return;

		final point = new Point(tick, valueAt(row, py));
		point.shape = held.smooth ? Automation.LINEAR : Automation.HOLD;

		session.does(new AddPoint(session.pattern, drivenPart(), targeted(row),
			slotted(row), point, driven()));

		chosen = point;
		chosenAt = row;

		dragging = point;
		draggingAt = row;
		wasAt = point.at;
		wasValue = point.value;

		session.say(held.titled(slotted(row)) + "  " + held.said(point.value));
		invalidate();
	}

	function erased():Bool {
		if (chosen == null || chosenAt < 0) return false;

		session.does(new RemovePoint(session.pattern, drivenPart(), targeted(chosenAt),
			slotted(chosenAt), chosen, driven()));

		chosen = null;
		chosenAt = -1;

		invalidate();
		return true;
	}

	function moved(event:Input):Bool {
		if (bending >= 0) return bent(event);

		if (dragging != null) {
			final held = parameterOf(draggingAt);
			if (held == null) return true;

			var tick = session.snapped(tickAt(event.x));
			if (tick < 0) tick = 0;

			final value = valueAt(draggingAt, event.y);
			if (tick == dragging.at && value == dragging.value) return true;

			dragging.at = wasAt;
			dragging.value = wasValue;

			session.does(new MovePoint(session.pattern, drivenPart(), targeted(draggingAt),
				slotted(draggingAt), dragging, tick, value, driven()));

			session.say(held.titled(slotted(draggingAt)) + "  " + held.said(value));
			invalidate();
			return true;
		}

		final row = rowAt(event.y);
		if (row == hoverRow) return false;

		hoverRow = row;
		invalidate();

		return true;
	}

	function bent(event:Input):Bool {
		if (chosen == null) return true;

		final much = (bentFrom - event.y) / (rowHeight() * 0.5);
		var want = bentWas + Math.round(much * Automation.MOST_TENSION);

		if (want < -Automation.MOST_TENSION) want = -Automation.MOST_TENSION;
		if (want > Automation.MOST_TENSION) want = Automation.MOST_TENSION;

		if (want == chosen.tension) return true;

		chosen.tension = bentWas;
		session.does(new ShapePoint(chosen, chosen.shape, want, chosen.steps));

		session.say("tension " + want);
		invalidate();

		return true;
	}

	override function hovered(on:Bool):Void {
		if (!on) hoverRow = -1;
		super.hovered(on);
	}

	override function paint(paint:Paint):Void {
		final root = root();
		if (root == null || root.metrics.body == null || rows() == 0) return;

		final theme = root.theme;
		final metrics = root.metrics;

		for (row in 0...rows()) drawn(paint, theme, metrics, row);
	}

	function drawn(paint:Paint, theme:Theme, metrics:Metrics, row:Int):Void {
		final small = metrics.small == null ? metrics.body : metrics.small;
		final top = rowTop(row);
		final tall = rowHeight();
		final held = parameterOf(row);

		paint.rect(x, top, width, tall, row % 2 == 0 ? theme.panel : theme.raise1);
		paint.rect(x, top, width, metrics.whole(1), theme.frame, 0.7);

		if (held == null) return;

		final colour = theme.part(drivenPart().index());

		paint.pushClip(x + left, top, width - left, tall);

		if (held.offset) {
			final zero = atValue(row, 0);
			paint.rect(x + left, zero, width - left, metrics.whole(1), theme.frame, 0.8);
		}

		traced(paint, theme, metrics, row, colour);
		paint.popClip();

		paint.pushClip(x, top, left, tall);
		paint.reface(small);

		paint.text(held.titled(slotted(row)), x + metrics.gap,
			top + metrics.gap + small.ascent, theme.ink, held.smooth ? 1 : 0.7);

		final line = lineOf(row);
		final says = chosenAt == row && chosen != null ? held.said(chosen.value)
			: (line == null || line.points.length == 0 ? translate(Locale.LANE_EMPTY)
				: held.said(line.valueAt(playhead < 0 ? 0 : playhead)));

		paint.text(says, x + metrics.gap, top + tall - metrics.gap - small.descent,
			theme.dim, 0.9);

		paint.popClip();

		if (tall < metrics.whole(120)) return;

		paint.textRight(held.said(held.high), x + width - metrics.gap,
			top + padding() + small.ascent * 0.4, theme.dim, 0.5);

		paint.textRight(held.said(held.low), x + width - metrics.gap,
			top + tall - padding() + small.ascent * 0.4, theme.dim, 0.5);
	}

	function traced(paint:Paint, theme:Theme, metrics:Metrics, row:Int,
			colour:mdd.ui.Colour):Void {
		final line = lineOf(row);
		if (line == null || line.points.length == 0) return;

		final hair = metrics.whole(2);
		final knob = metrics.whole(4);

		for (index in 0...line.points.length - 1) {
			final from = line.points[index];
			final to = line.points[index + 1];

			final headX = atTick(from.at);
			final tailX = atTick(to.at);

			if (tailX < x + left || headX > x + width) continue;

			if (!Automation.moves(from.shape)) {
				final level = atValue(row, from.value);

				paint.rect(headX, level, tailX - headX, hair, colour, 0.9);
				paint.rect(tailX, Math.min(level, atValue(row, to.value)), hair,
					Math.abs(atValue(row, to.value) - level) + hair, colour, 0.9);

				continue;
			}

			var many = Std.int((tailX - headX) / metrics.whole(2)) + 2;
			if (many > TRACE) many = TRACE;
			if (many < 2) many = 2;

			for (step in 0...many) {
				final tick = from.at + Std.int((to.at - from.at) * step / (many - 1));

				trace[step * 2] = atTick(tick);
				trace[step * 2 + 1] = atValue(row, Automation.between(from, to, tick));
			}

			paint.polyline(trace, many, hair, colour, 0.9);

			final middle = Std.int((from.at + to.at) / 2);

			paint.ring(atTick(middle), atValue(row, Automation.between(from, to, middle)),
				knob * 0.6, metrics.whole(1), colour, 0.55);
		}

		final last = line.points[line.points.length - 1];

		paint.rect(atTick(last.at), atValue(row, last.value), x + width - atTick(last.at),
			hair, colour, 0.5);

		for (point in line.points) {
			final at = atTick(point.at);
			if (at < x + left - knob || at > x + width + knob) continue;

			final level = atValue(row, point.value);
			final picked = point == chosen && chosenAt == row;

			paint.circle(at, level, knob, picked ? theme.ink : colour);

			if (picked) paint.ring(at, level, knob + metrics.whole(2), metrics.whole(1),
				theme.accent);
		}
	}
}
