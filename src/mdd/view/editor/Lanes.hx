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
import mdd.ui.control.Number;
import mdd.view.Parameter;
import mdd.view.Picked;

@:unreflective
final class Lanes extends Widget {
	public static inline final LEAST_ROW = 40;
	public static inline final MOST_ROW = 220;
	public static inline final ROW = 92;

	public static inline final REACH = 8;
	public static inline final KNOB = 5;
	public static inline final TRACE = 512;

	static inline final FINE = 0.125;

	public final session:Session;

	public final targets:Array<Int> = [];

	public var perTick:Float = 0.25;
	public var offsetX:Float = 0;
	public var left:Float = 0;
	public var rowTall:Float = 0;
	public var adding:Bool = true;

	public var offsetY:Float = 0;

	final heights:Array<Float> = [];
	final remembered:Map<Int, Float> = new Map<Int, Float>();
	final shut:Map<Int, Bool> = new Map<Int, Bool>();

	public var onOffer:Null<(Lanes, Int, Float, Float) -> Void> = null;
	public var onShape:Null<(Lanes, Int, Point, Float, Float) -> Void> = null;

	public var holding:Null<mdd.song.Clip> = null;
	public var playhead:Int = -1;
	public var chosen(default, null):Null<Point> = null;
	public var chosenAt(default, null):Int = -1;
	public final picked:Picked<Point> = new Picked<Point>();

	public static inline final STACK = -2;

	var sizing:Int = -1;
	var grabY:Float = 0;
	var grabTall:Float = 0;

	var hoverEdge:Int = -1;
	var hoverRow:Int = -1;
	var hoverName:Bool = false;
	var hoverShed:Bool = false;
	var hoverFold:Bool = false;
	var hoverFoot:Bool = false;
	var dragging:Null<Point> = null;
	var draggingAt:Int = -1;

	var banding:Bool = false;
	var bandRow:Int = -1;
	var bandFromX:Float = 0;
	var bandFromY:Float = 0;
	var bandToX:Float = 0;
	var bandToY:Float = 0;

	final moving:Array<Point> = [];
	final movingAt:Array<Int> = [];
	final movingValue:Array<Int> = [];
	var leastAt:Int = 0;
	var leastValue:Int = 0;
	var mostValue:Int = 0;
	var bending:Int = -1;
	var bentFrom:Float = 0;
	var bentWas:Int = 0;
	var wasAt:Int = 0;
	var wasValue:Int = 0;

	var fining:Bool = false;
	var fineX:Float = 0;
	var fineY:Float = 0;
	var fineAt:Int = 0;
	var fineValue:Int = 0;

	var overSegment:Int = -1;
	var overSegmentAt:Int = -1;

	final trace:Vector<Float> = new Vector<Float>(TRACE * 2);

	public final position:Number;
	public final amount:Number;
	public final shape:Number;
	public final bend:Number;
	public final steps:Number;

	final fields:Array<Number>;

	var settling:Bool = false;

	public function new(session:Session) {
		super();
		this.session = session;

		focusable = true;

		position = new Number("", 0, 0, 1 << 24);
		amount = new Number("", 0, -4096, 4096);
		shape = new Number("", 0, 0, Automation.SHAPES - 1);
		bend = new Number("", 0, -Automation.MOST_TENSION, Automation.MOST_TENSION);
		steps = new Number("", Automation.REPEATS, 2, Automation.MOST_REPEATS);

		fields = [position, amount, shape, bend, steps];

		for (one in fields) {
			one.visible = false;
			add(one);
		}

		position.derived = function(value:Int):String return spelt(value);
		shape.derived = function(value:Int):String
			return translate(Locale.SHAPES[value]);

		position.onChange = function(from:Number):Void placed();
		amount.onChange = function(from:Number):Void placed();

		shape.onChange = function(from:Number):Void shaped();
		bend.onChange = function(from:Number):Void shaped();
		steps.onChange = function(from:Number):Void shaped();
	}

	function spelt(tick:Int):String {
		final beat = session.song.tempo.ppqn;
		if (beat < 1) return "" + tick;

		final bar = beat * 4;

		return (Std.int(tick / bar) + 1) + "." + (Std.int((tick % bar) / beat) + 1)
			+ "." + (tick % beat);
	}

	function placed():Void {
		if (settling || chosen == null || chosenAt < 0) return;

		if (chosen.at == position.value && chosen.value == amount.value) return;

		final was = chosen;

		session.does(new MovePoint(session.pattern, drivenPart(), targeted(chosenAt),
			slotted(chosenAt), was, position.value, amount.value, driven()));

		invalidate();
	}

	function shaped():Void {
		if (settling || chosen == null) return;

		if (chosen.shape == shape.value && chosen.tension == bend.value
			&& chosen.repeats() == steps.value) return;

		session.does(new ShapePoint(chosen, shape.value, bend.value, steps.value));
		relayout();
	}

	function dressed():Void {
		final one = chosenAt < 0 ? null : parameterOf(chosenAt);
		final on = chosen != null && one != null && holding == null;

		settling = true;

		for (field in fields) field.visible = on;

		if (!on) {
			settling = false;
			return;
		}

		final pattern = session.current();

		position.spans(0, pattern == null ? 1 << 24 : pattern.length);
		amount.spans(one.low, one.high);

		position.label = translate(Locale.POINT_AT);
		amount.label = one.titled(slotted(chosenAt));
		shape.label = translate(Locale.POINT_SHAPE);
		bend.label = translate(Locale.POINT_BEND);
		steps.label = translate(Locale.POINT_STEPS);

		amount.derived = function(value:Int):String return one.said(value);

		position.set(chosen.at);
		amount.set(chosen.value);
		shape.set(chosen.shape);
		bend.set(chosen.tension);
		steps.set(chosen.repeats());

		final moves = Automation.moves(chosen.shape) && one.smooth;

		bend.visible = moves;
		steps.visible = Automation.stepped(chosen.shape);
		shape.visible = one.smooth || !Automation.moves(chosen.shape);

		settling = false;
	}

	override function layout():Void {
		dressed();

		final root = root();
		if (root == null || holding != null) return;

		final metrics = root.metrics;
		final tall = metrics.whole(24);
		final top = footTop() + (footTall() - tall) * 0.5;

		var pen = x + width - metrics.gap;

		var index = fields.length - 1;

		while (index >= 0) {
			final field = fields[index];
			index--;

			if (!field.visible) continue;

			final wide = field.fits();

			if (pen - wide < x + addWide() + metrics.gap) {
				field.visible = false;
				continue;
			}

			pen -= wide;
			field.arrange(pen, top, wide, tall);
			pen -= metrics.unit;
		}
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
		return heightOf(0);
	}

	public function heightOf(row:Int):Float {
		if (folded(row)) return headTall();
		if (rowTall > 0) return rowTall;

		if (row >= 0 && row < heights.length && heights[row] > 0) return heights[row];

		final root = root();
		return root == null ? ROW : root.metrics.whole(ROW);
	}

	public function folded(row:Int):Bool {
		if (row < 0 || row >= targets.length) return false;
		return shut.exists(targets[row]) && shut.get(targets[row]);
	}

	public function folds(row:Int):Void {
		if (row < 0 || row >= targets.length) return;

		shut.set(targets[row], !folded(row));
		spreadFor = -1;

		relayout();
	}

	function raised(row:Int, to:Float):Void {
		final root = root();

		final least = root == null ? LEAST_ROW : root.metrics.whole(LEAST_ROW);
		final most = root == null ? MOST_ROW : root.metrics.whole(MOST_ROW);

		final want = to < least ? least : (to > most ? most : to);

		while (heights.length <= row) heights.push(0);
		if (heights[row] == want) return;

		heights[row] = want;
		if (row < targets.length) remembered.set(targets[row], want);

		relayout();
	}

	var spreadFor:Int = -1;

	public function spreads(room:Float):Void {
		if (rowTall > 0) return;

		final many = rows();
		if (many == 0) return;

		if (many == spreadFor) return;
		spreadFor = many;

		final want = room - (holding == null ? footTall() : 0);
		if (want <= 0) return;

		final root = root();
		final least = root == null ? LEAST_ROW : root.metrics.whole(LEAST_ROW);

		var open = 0;
		var shutRoom = 0.0;

		for (row in 0...many) {
			if (folded(row)) shutRoom += headTall();
			else open++;
		}

		final each = open < 1 ? 0 : (want - shutRoom) / open;

		for (row in 0...many) {
			while (heights.length <= row) heights.push(0);
			heights[row] = each < least ? 0 : each;
		}
	}

	function recalls(row:Int):Void {
		while (heights.length <= row) heights.push(0);

		final want = row < targets.length ? targets[row] : -1;
		heights[row] = want >= 0 && remembered.exists(want) ? remembered.get(want) : 0;
	}

	public function headTall():Float {
		final root = root();
		return root == null ? 17 : root.metrics.whole(17);
	}

	public function footTall():Float {
		final root = root();
		return root == null ? 32 : root.metrics.whole(32);
	}

	public function wants():Float {
		var much = holding == null ? footTall() : 0.0;
		for (row in 0...rows()) much += heightOf(row);

		return much;
	}

	public inline function plotTop(row:Int):Float {
		return rowTop(row) + headTall();
	}

	public inline function plotTall(row:Int):Float {
		return heightOf(row) - headTall();
	}

	public function footTop():Float {
		var much = y - offsetY;
		for (row in 0...rows()) much += heightOf(row);

		return much;
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
		recalls(targets.length - 1);

		relayout();
	}

	public function hide(row:Int):Void {
		if (row < 0 || row >= targets.length) return;

		targets.splice(row, 1);
		if (row < heights.length) heights.splice(row, 1);

		forgets();

		relayout();
	}

	public function swap(row:Int, target:Int, slot:Int):Void {
		if (row < 0 || row >= targets.length) return;

		targets[row] = (target << 8) | slot;
		recalls(row);

		forgets();

		relayout();
	}

	public var opens:Int = 64;

	var filledFor:Int = -1;

	public function settles():Void {
		if (holding != null) return;

		final key = session.part.index() * 4096 + session.pattern;
		if (key == filledFor) return;

		filledFor = key;
		fills(false);
	}

	public function fills(again:Bool = true):Void {
		if (holding != null) return;

		final pattern = session.current();

		targets.resize(0);
		heights.resize(0);

		forgets();

		if (pattern == null) {
			if (again) relayout();
			return;
		}

		final lane = pattern.lane(session.part);

		while (targets.length < opens) {
			var best:Null<Automation> = null;
			var most = 0;

			for (line in lane.automation) {
				if (line.points.length <= most) continue;
				if (Parameter.found(session.part, line.target, line.slot) == null) continue;
				if (shows(line.target, line.slot)) continue;

				best = line;
				most = line.points.length;
			}

			if (best == null) break;

			targets.push((best.target << 8) | best.slot);
			recalls(targets.length - 1);
		}

		if (again) relayout();
	}

	public function carries(target:Int, slot:Int):Int {
		final pattern = session.current();
		if (pattern == null) return 0;

		for (line in pattern.lane(session.part).automation) {
			if (line.held(target, slot)) return line.points.length;
		}

		return 0;
	}

	public function picks(point:Point, row:Int):Void {
		chosen = point;
		chosenAt = row;
		picked.only(point);

		relayout();
	}

	static function counted(many:Int):String {
		return many + (many == 1 ? " point" : " points");
	}

	function alters(point:Point, row:Int, shift:Bool):Void {
		if (row != chosenAt) picked.clear();

		if (shift) {
			picked.toggles(point);

			chosen = picked.holds(point) ? point : picked.lead();
			chosenAt = picked.count == 0 ? -1 : row;

			return;
		}

		if (!picked.holds(point)) picked.only(point);

		chosen = point;
		chosenAt = row;
	}

	function forgets():Void {
		picked.clear();

		chosen = null;
		chosenAt = -1;
	}

	public function picksAll():Bool {
		final row = chosenAt < 0 ? 0 : chosenAt;
		final line = lineOf(row);

		if (line == null || line.points.length == 0) return false;

		picked.clear();
		for (point in line.points) picked.adds(point);

		chosen = picked.lead();
		chosenAt = row;

		session.say(counted(picked.count) + " selected");
		session.changed();

		relayout();
		return true;
	}

	override function edited(what:Int):Bool {
		switch (what) {
			case mdd.ui.Edit.ALL:
				return picksAll();

			case mdd.ui.Edit.COPY:
				return copies();

			case mdd.ui.Edit.CUT:
				if (!copies()) return false;
				return erased();

			case mdd.ui.Edit.PASTE:
				if (session.copiedPoints.length == 0) return false;
				return pasted(chosenAt < 0 ? 0 : chosenAt);

			case _:
		}

		return false;
	}

	function copies():Bool {
		final held = picked.taken();
		if (held.length == 0) return false;

		var least = held[0].at;
		for (point in held) if (point.at < least) least = point.at;

		session.copiedPoints.resize(0);

		for (point in held) {
			final made = point.copy();
			made.at -= least;

			session.copiedPoints.push(made);
		}

		session.say("copied " + counted(held.length));
		session.changed();

		return true;
	}

	function pasted(row:Int):Bool {
		final copied = session.copiedPoints;
		final line = lineOf(row);

		if (copied.length == 0) return false;

		var where = session.snapped(playhead < 0 ? 0 : playhead);
		if (where < 0) where = 0;

		final group = new mdd.song.edit.Together("paste " + counted(copied.length));
		final made:Array<Point> = [];

		for (one in copied) {
			final point = one.copy();
			point.at = where + point.at;

			if (line != null && line.marks(point.at)) continue;

			made.push(point);
			group.also(new AddPoint(session.pattern, drivenPart(), targeted(row),
				slotted(row), point, driven()));
		}

		if (made.length == 0) return false;
		session.does(group);

		picked.clear();
		for (point in made) picked.adds(point);

		chosen = picked.lead();
		chosenAt = row;

		session.say("pasted " + counted(made.length));
		relayout();

		return true;
	}

	public function edge():Float {
		final root = root();
		return root == null ? 5 : root.metrics.whole(5);
	}

	public function edgeAt(px:Float, py:Float):Int {
		if (rowTall > 0 || rows() == 0) return -1;
		if (px < x || px >= x + width) return -1;

		final reach = edge();
		if (Math.abs(py - y) <= reach) return STACK;

		var top = y;

		for (row in 0...rows()) {
			top += heightOf(row);
			if (Math.abs(py - top) <= reach) return row;
		}

		return -1;
	}

	function sized(py:Float):Void {
		if (sizing == STACK) {
			final many = rows();
			if (many < 1) return;

			final want = (grabTall + grabY - py) / many;
			for (row in 0...many) raised(row, want);

			return;
		}

		raised(sizing, grabTall + py - grabY);
	}

	public function rowAt(py:Float):Int {
		var top = y - offsetY;

		for (row in 0...rows()) {
			final tall = heightOf(row);
			if (py >= top && py < top + tall) return row;

			top += tall;
		}

		return -1;
	}

	public function rowTop(row:Int):Float {
		var top = y - offsetY;
		for (before in 0...row) top += heightOf(before);

		return top;
	}

	public inline function freely(tick:Int, free:Bool):Int {
		return free ? tick : session.snapped(tick);
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
		if (held == null) return plotTop(row);

		final span = held.high - held.low;
		if (span <= 0) return plotTop(row);

		final inset = padding();
		final room = plotTall(row) - inset * 2;
		final part = (value - held.low) / span;
		final up = held.attenuates() ? 1 - part : part;

		return plotTop(row) + inset + room * (1 - up);
	}

	function valueAt(row:Int, py:Float):Int {
		final held = parameterOf(row);
		if (held == null) return 0;

		final inset = padding();
		final room = plotTall(row) - inset * 2;
		if (room <= 0) return held.low;

		var up = 1 - (py - plotTop(row) - inset) / room;
		if (up < 0) up = 0;
		if (up > 1) up = 1;

		final part = held.attenuates() ? 1 - up : up;

		return held.holds(held.low + Math.round((held.high - held.low) * part));
	}

	function padding():Float {
		final root = root();
		return root == null ? 9 : root.metrics.whole(9);
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

	public function segmentAt(row:Int, px:Float):Int {
		final line = lineOf(row);
		if (line == null || line.points.length < 2) return -1;

		for (index in 0...line.points.length - 1) {
			if (!Automation.moves(line.points[index].shape)) continue;

			if (px >= atTick(line.points[index].at)
				&& px < atTick(line.points[index + 1].at)) return index;
		}

		return -1;
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
				if (banding) banded();

				dragging = null;
				bending = -1;
				sizing = -1;
				fining = false;
				return true;

			case Kind.KeyDown:
				if (event.code == Key.Escape && picked.count > 0) {
					forgets();
					relayout();
					return true;
				}

				if (event.code != Key.Delete && event.code != Key.Backspace) return false;
				return erased();

			case _:
		}

		return false;
	}

	function pressed(event:Input):Bool {
		final held = edgeAt(event.x, event.y);

		if (held != -1 && event.button == Pointer.Left) {
			sizing = held;
			grabY = event.y;

			grabTall = held == STACK ? wants() - footTall() : heightOf(held);
			return true;
		}

		if (onFoot(event.x, event.y)) {
			if (onOffer != null) onOffer(this, -1, event.x, event.y);
			return true;
		}

		final row = rowAt(event.y);
		if (row < 0) return false;

		if (event.y < rowTop(row) + headTall()) {
			if (onShed(row, event.x)) {
				hide(row);
				return true;
			}

			if (onFold(row, event.x)) {
				folds(row);
				return true;
			}

			if (onName(row, event.x) && onOffer != null) {
				onOffer(this, row, event.x, rowTop(row) + headTall());
			}

			return true;
		}

		final point = pointAt(row, event.x, event.y);

		if (event.button == Pointer.Right) {
			if (point == null || onShape == null) return true;

			alters(point, row, false);
			onShape(this, row, point, event.x, event.y);

			return true;
		}

		if (point != null) {
			final adding = event.shift();
			alters(point, row, adding);

			if (adding) {
				relayout();
				return true;
			}

			dragging = point;
			draggingAt = row;
			wasAt = point.at;
			wasValue = point.value;

			grabs(point, row);
			anchors(event, point);

			relayout();
			return true;
		}

		if (session.tool == Session.SELECT || event.shift()) {
			bands(event, row);
			return true;
		}

		final bend = bendAt(row, event.x, event.y);

		if (bend >= 0) {
			final line = lineOf(row);
			if (line == null) return true;

			bending = row;
			bentFrom = event.y;
			bentWas = line.points[bend].tension;
			alters(line.points[bend], row, false);

			invalidate();
			return true;
		}

		added(event, row, event.x, event.y);
		return true;
	}

	function bands(event:Input, row:Int):Void {
		banding = true;
		bandRow = row;
		bandFromX = event.x;
		bandFromY = event.y;
		bandToX = event.x;
		bandToY = event.y;

		if (!event.shift()) forgets();

		invalidate();
	}

	function banded():Void {
		banding = false;

		final line = lineOf(bandRow);
		final left = bandFromX < bandToX ? bandFromX : bandToX;
		final right = bandFromX < bandToX ? bandToX : bandFromX;
		final top = bandFromY < bandToY ? bandFromY : bandToY;
		final floor = bandFromY < bandToY ? bandToY : bandFromY;

		if (line == null || (right - left < 2 && floor - top < 2)) {
			invalidate();
			return;
		}

		if (bandRow != chosenAt) picked.clear();

		for (point in line.points) {
			final at = atTick(point.at);
			final up = atValue(bandRow, point.value);

			if (at < left || at > right || up < top || up > floor) continue;
			picked.adds(point);
		}

		chosen = picked.lead();
		chosenAt = picked.count == 0 ? -1 : bandRow;

		if (picked.count > 0) session.say(counted(picked.count) + " selected");
		session.changed();

		relayout();
	}

	function grabs(lead:Point, row:Int):Void {
		moving.resize(0);
		movingAt.resize(0);
		movingValue.resize(0);

		if (picked.count > 1 && picked.holds(lead) && row == chosenAt) {
			for (index in 0...picked.count) moving.push(picked.at(index));
		} else {
			moving.push(lead);
		}

		leastAt = moving[0].at;
		leastValue = moving[0].value;
		mostValue = leastValue;

		for (point in moving) {
			movingAt.push(point.at);
			movingValue.push(point.value);

			if (point.at < leastAt) leastAt = point.at;
			if (point.value < leastValue) leastValue = point.value;
			if (point.value > mostValue) mostValue = point.value;
		}
	}

	function added(event:Input, row:Int, px:Float, py:Float):Void {
		final held = parameterOf(row);
		if (held == null) return;
		if (holding == null && session.current() == null) return;

		var tick = freely(tickAt(px), event.alt());
		if (tick < 0) tick = 0;

		final line = lineOf(row);
		if (line != null && line.marks(tick)) return;

		final point = new Point(tick, valueAt(row, py));
		point.shape = held.smooth ? Automation.LINEAR : Automation.HOLD;

		session.does(new AddPoint(session.pattern, drivenPart(), targeted(row),
			slotted(row), point, driven()));

		picked.only(point);

		chosen = point;
		chosenAt = row;

		dragging = point;
		draggingAt = row;
		wasAt = point.at;
		wasValue = point.value;

		grabs(point, row);

		session.say(held.titled(slotted(row)) + "  " + held.said(point.value));

		anchors(event, point);
		relayout();
	}

	function hauled(byTick:Int, byValue:Int, held:Parameter):Void {
		var tick = byTick;
		var value = byValue;

		if (leastAt + tick < 0) tick = -leastAt;
		if (leastValue + value < held.low) value = held.low - leastValue;
		if (mostValue + value > held.high) value = held.high - mostValue;

		for (index in 0...moving.length) {
			moving[index].at = movingAt[index];
			moving[index].value = movingValue[index];
		}

		if (tick == 0 && value == 0) return;

		final group = new mdd.song.edit.Together("move " + counted(moving.length));

		for (index in 0...moving.length) {
			group.also(new MovePoint(session.pattern, drivenPart(), targeted(draggingAt),
				slotted(draggingAt), moving[index], movingAt[index] + tick,
				held.holds(movingValue[index] + value), driven()));
		}

		session.does(group);
	}

	function anchors(event:Input, point:Point):Void {
		fining = event.ctrl();
		fineX = event.x;
		fineY = event.y;
		fineAt = point.at;
		fineValue = point.value;
	}

	function erased():Bool {
		if (chosenAt < 0 || picked.count == 0) return false;

		final held = picked.taken();
		final row = chosenAt;

		if (held.length == 1) {
			session.does(new RemovePoint(session.pattern, drivenPart(), targeted(row),
				slotted(row), held[0], driven()));
		} else {
			final group = new mdd.song.edit.Together("remove " + counted(held.length));

			for (point in held) {
				group.also(new RemovePoint(session.pattern, drivenPart(), targeted(row),
					slotted(row), point, driven()));
			}

			session.does(group);
		}

		forgets();

		relayout();
		return true;
	}

	function moved(event:Input):Bool {
		if (sizing != -1) {
			sized(event.y);
			return true;
		}

		if (banding) {
			bandToX = event.x;
			bandToY = event.y;
			invalidate();
			return true;
		}

		if (bending >= 0) return bent(event);

		if (dragging != null) {
			final held = parameterOf(draggingAt);
			if (held == null) return true;

			final fine = event.ctrl();

			if (fine != fining) {
				fining = fine;
				fineX = event.x;
				fineY = event.y;
				fineAt = dragging.at;
				fineValue = dragging.value;
			}

			var tick = fine
				? tickAt(atTick(fineAt) + (event.x - fineX) * FINE)
				: freely(tickAt(event.x), event.alt());

			if (tick < 0) tick = 0;

			final value = fine
				? valueAt(draggingAt, atValue(draggingAt, fineValue) + (event.y - fineY) * FINE)
				: valueAt(draggingAt, event.y);

			if (tick == dragging.at && value == dragging.value) return true;

			if (moving.length > 1) {
				hauled(tick - wasAt, value - wasValue, held);
			} else {
				dragging.at = wasAt;
				dragging.value = wasValue;

				session.does(new MovePoint(session.pattern, drivenPart(),
					targeted(draggingAt), slotted(draggingAt), dragging, tick, value,
					driven()));
			}

			session.say(held.titled(slotted(draggingAt)) + "  " + held.said(value));
			invalidate();
			return true;
		}

		final row = rowAt(event.y);
		final foot = onFoot(event.x, event.y);
		final grip = edgeAt(event.x, event.y);

		final segment = row < 0 || event.y < rowTop(row) + headTall() ? -1
			: segmentAt(row, event.x);

		final name = row >= 0 && event.y < rowTop(row) + headTall()
			&& onName(row, event.x);

		final shed = row >= 0 && event.y < rowTop(row) + headTall()
			&& onShed(row, event.x);

		final fold = row >= 0 && event.y < rowTop(row) + headTall()
			&& onFold(row, event.x);

		if (row == hoverRow && name == hoverName && shed == hoverShed && fold == hoverFold
			&& foot == hoverFoot && grip == hoverEdge && segment == overSegment
			&& row == overSegmentAt) return false;

		hoverFold = fold;

		overSegment = segment;
		overSegmentAt = row;

		hoverRow = row;
		hoverName = name;
		hoverShed = shed;
		hoverFoot = foot;
		hoverEdge = grip;

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
		if (!on) {
			hoverRow = -1;
			hoverName = false;
			hoverShed = false;
			hoverFold = false;
			hoverFoot = false;
			hoverEdge = -1;
			overSegment = -1;
			overSegmentAt = -1;
		}

		super.hovered(on);
	}

	override function paint(paint:Paint):Void {
		final root = root();
		if (root == null || root.metrics.body == null || rows() == 0) return;

		final theme = root.theme;
		final metrics = root.metrics;

		paint.pushClip(x, y, width, height);

		for (row in 0...rows()) drawn(paint, theme, metrics, row);

		if (banding) band(paint, theme, metrics);

		if (left > 0) {
			final hair = metrics.whole(1);
			paint.rect(x + left - hair, y, hair, height, theme.frame);
		}

		if (holding == null) footed(paint, theme, metrics);

		paint.popClip();

		if (holding == null) {
			for (field in fields) if (field.visible) field.paint(paint);
		}

		gripped(paint, theme, metrics);
	}

	function gripped(paint:Paint, theme:Theme, metrics:Metrics):Void {
		final held = sizing != -1 ? sizing : hoverEdge;
		if (held == -1 || rowTall > 0) return;

		final at = held == STACK ? y : rowTop(held) + heightOf(held);
		final thick = metrics.whole(2);

		paint.rect(x, at - thick * 0.5, width, thick, theme.accent, 0.8);

		final wide = metrics.whole(24);
		final middle = x + left + (width - left) * 0.5;

		paint.roundedRect(middle - wide * 0.5, at - thick * 1.5, wide, thick * 3,
			thick, theme.accent, 0.9);
	}

	public function onFoot(px:Float, py:Float):Bool {
		if (holding != null || !adding) return false;

		final top = footTop();
		return py >= top && py < top + footTall() && px >= x && px < x + addWide();
	}

	function addWide():Float {
		final root = root();
		if (root == null || root.metrics.small == null || !adding) return 0;

		final metrics = root.metrics;
		return metrics.gap + metrics.whole(9)
			+ metrics.small.measure(translate(Locale.LANE_ADD)) + metrics.inset;
	}

	function footed(paint:Paint, theme:Theme, metrics:Metrics):Void {
		final small = metrics.small == null ? metrics.body : metrics.small;
		final top = footTop();
		final tall = footTall();

		paint.rect(x, top, width, tall, theme.sink);
		paint.rect(x, top, width, metrics.whole(1), theme.frame, 0.7);

		if (!adding) return;

		final wide = addWide();
		final box = top + metrics.whole(3);
		final deep = tall - metrics.whole(6);

		paint.roundedRect(x + metrics.unit, box, wide - metrics.unit * 2, deep,
			metrics.radiusSmall, hoverFoot ? theme.raise2 : theme.raise1);

		paint.outline(x + metrics.unit, box, wide - metrics.unit * 2, deep, theme.frame,
			metrics.whole(1), 1, metrics.radiusSmall);

		final ink = hoverFoot ? theme.ink : theme.dim;
		final middle = box + deep * 0.5;
		final at = x + metrics.gap + metrics.whole(4);
		final reach = metrics.whole(4);
		final hair = metrics.whole(1);

		paint.rect(at - reach, middle - hair * 0.5, reach * 2, hair, ink);
		paint.rect(at - hair * 0.5, middle - reach, hair, reach * 2, ink);

		paint.reface(small);
		paint.text(translate(Locale.LANE_ADD), at + reach + metrics.gap,
			middle - small.height * 0.5 + small.ascent, ink, 0.9);
	}

	function drawn(paint:Paint, theme:Theme, metrics:Metrics, row:Int):Void {
		final small = metrics.small == null ? metrics.body : metrics.small;
		final top = rowTop(row);
		final tall = rowHeight();
		final held = parameterOf(row);

		paint.rect(x, top, width, tall, row % 2 == 0 ? theme.panel : theme.raise1);
		paint.rect(x, top, width, metrics.whole(1), theme.frame, 0.7);

		heading(paint, theme, metrics, row, held);

		if (held == null) return;

		final colour = theme.part(drivenPart().index());

		paint.pushClip(x + left, plotTop(row), width - left, plotTall(row));

		gridded(paint, theme, metrics, row);

		if (held.offset) {
			final zero = atValue(row, 0);
			paint.rect(x + left, zero, width - left, metrics.whole(1), theme.frame, 0.8);
		}

		traced(paint, theme, metrics, row, colour);
		paint.popClip();

		paint.reface(small);

		final ceiling = plotTop(row) + padding();
		final floor = plotTop(row) + plotTall(row) - padding();
		final upper = held.attenuates() ? held.low : held.high;

		paint.textRight(held.said(upper), x + left - metrics.unit,
			ceiling + small.ascent * 0.5, theme.dim, 0.45);

		paint.textRight(held.said(held.attenuates() ? held.high : held.low),
			x + left - metrics.unit, floor + small.ascent * 0.5, theme.dim, 0.45);

		if (!held.offset) return;

		paint.textRight("0", x + left - metrics.unit,
			atValue(row, 0) + small.ascent * 0.5, theme.dim, 0.55);
	}

	function gridded(paint:Paint, theme:Theme, metrics:Metrics, row:Int):Void {
		final beat = session.song.tempo.ppqn;
		if (beat < 1 || perTick <= 0) return;

		final bar = beat * 4;
		final step = session.snap < 1 ? beat : session.snap;
		final hair = metrics.whole(1);

		final top = plotTop(row);
		final tall = plotTall(row);
		final from = x + left;

		var fine = step;
		while (fine * perTick < metrics.whole(7) && fine < bar) fine *= 2;

		var tick = Std.int(tickAt(from) / fine) * fine;
		if (tick < 0) tick = 0;

		final reach = holding != null ? holding.length : span();

		while (tick <= reach) {
			final at = atTick(tick);
			if (at > x + width) break;

			if (at > from) {
				final much = tick % (bar * 4) == 0 ? 0.55
					: (tick % bar == 0 ? 0.35 : (tick % beat == 0 ? 0.18 : 0.09));

				paint.rect(at, top, hair, tall, theme.frame, much);
			}

			tick += fine;
		}
	}

	public function span():Int {
		final pattern = session.current();
		return pattern == null ? session.song.tempo.ppqn * 16 : pattern.length;
	}

	public function nameWide(row:Int):Float {
		final root = root();
		final held = parameterOf(row);

		if (root == null || held == null) return 0;

		final metrics = root.metrics;
		final small = metrics.small == null ? metrics.body : metrics.small;

		return metrics.gap + small.measure(held.titled(slotted(row))) + metrics.unit
			+ metrics.whole(7) + metrics.gap;
	}

	public function onName(row:Int, px:Float):Bool {
		return px >= x && px < x + nameWide(row);
	}

	public function onShed(row:Int, px:Float):Bool {
		final root = root();
		if (root == null || holding != null || !adding) return false;

		final metrics = root.metrics;
		return px >= x + width - metrics.whole(20) && px < x + width;
	}

	public function onFold(row:Int, px:Float):Bool {
		final root = root();
		if (root == null || holding != null || !adding) return false;

		final metrics = root.metrics;
		final at = x + width - metrics.whole(40);

		return px >= at && px < at + metrics.whole(18);
	}

	function heading(paint:Paint, theme:Theme, metrics:Metrics, row:Int,
			held:Null<Parameter>):Void {
		final small = metrics.small == null ? metrics.body : metrics.small;
		final top = rowTop(row);
		final tall = headTall();
		final line = top + (tall - small.height) * 0.5 + small.ascent;
		final lit = hoverRow == row;

		paint.rect(x, top, width, tall, theme.bar, lit ? 1 : 0.75);
		paint.rect(x, top + tall - metrics.whole(1), width, metrics.whole(1), theme.frame, 0.5);

		paint.reface(small);

		if (held == null) {
			paint.text(translate(Locale.LANE_EMPTY), x + metrics.gap, line, theme.dim, 0.8);
			return;
		}

		final said = held.titled(slotted(row));

		if (lit && hoverName) {
			paint.roundedRect(x + metrics.unit, top + metrics.whole(2),
				nameWide(row) - metrics.unit * 2, tall - metrics.whole(4), metrics.radiusSmall,
				theme.accent, Theme.HOVER);
		}

		paint.text(said, x + metrics.gap, line, theme.ink, 0.95);

		chevron(paint, theme, metrics, x + metrics.gap + small.measure(said) + metrics.unit
			+ metrics.whole(3), top + tall * 0.5);

		if (holding == null && adding) {
			shed(paint, theme, metrics, x + width - metrics.whole(20), top, tall,
				lit && hoverShed);

			fold(paint, theme, metrics, x + width - metrics.whole(40), top, tall,
				folded(row), lit && hoverFold);
		}

		final says = held.offset ? translate(Locale.LANE_RIDES) : "";
		final wide = says == "" ? 0.0 : small.measure(says);

		final value = lineOf(row);
		final now = value == null || value.points.length == 0 ? ""
			: held.said(value.valueAt(playhead < 0 ? 0 : playhead));

		final right = x + width - (holding == null && adding ? metrics.whole(42) : metrics.gap);

		if (now != "") {
			paint.textRight(now, right, line, theme.ink, 0.8);

			if (says != "" && nameWide(row) + wide + small.measure(now)
				+ metrics.whole(48) < width) {
				paint.textRight(says, right - small.measure(now) - metrics.inset, line,
					theme.dim, 0.55);
			}

			return;
		}

		if (says != "") paint.textRight(says, right, line, theme.dim, 0.55);
	}

	function chevron(paint:Paint, theme:Theme, metrics:Metrics, at:Float, middle:Float):Void {
		final reach = metrics.whole(3);
		final points = new Vector<Float>(6);

		points[0] = at - reach;
		points[1] = middle - reach * 0.5;
		points[2] = at + reach;
		points[3] = middle - reach * 0.5;
		points[4] = at;
		points[5] = middle + reach * 0.7;

		paint.polygon(points, 3, theme.dim, 0.9);
	}

	function fold(paint:Paint, theme:Theme, metrics:Metrics, at:Float, top:Float, tall:Float,
			shut:Bool, lit:Bool):Void {
		final size = metrics.whole(16);
		final box = top + (tall - size) * 0.5;

		if (lit) {
			paint.roundedRect(at, box, size, size, metrics.radiusSmall, theme.accent,
				Theme.HOVER);
		}

		final reach = metrics.whole(3);
		final middle = at + size * 0.5;
		final centre = box + size * 0.5;
		final ink = lit ? theme.ink : theme.dim;

		final arrow = new Vector<Float>(6);

		if (shut) {
			arrow[0] = middle - reach * 0.6;
			arrow[1] = centre - reach;
			arrow[2] = middle + reach * 0.8;
			arrow[3] = centre;
			arrow[4] = middle - reach * 0.6;
			arrow[5] = centre + reach;
		} else {
			arrow[0] = middle - reach;
			arrow[1] = centre - reach * 0.6;
			arrow[2] = middle + reach;
			arrow[3] = centre - reach * 0.6;
			arrow[4] = middle;
			arrow[5] = centre + reach * 0.8;
		}

		paint.polygon(arrow, 3, ink, 0.9);
	}

	function shed(paint:Paint, theme:Theme, metrics:Metrics, at:Float, top:Float, tall:Float,
			lit:Bool):Void {
		final size = metrics.whole(16);
		final box = top + (tall - size) * 0.5;

		if (lit) {
			paint.roundedRect(at, box, size, size, metrics.radiusSmall, theme.over,
				Theme.HOVER);
		}

		final reach = metrics.whole(3);
		final middle = at + size * 0.5;
		final centre = box + size * 0.5;
		final weight = metrics.whole(1);
		final ink = lit ? theme.over : theme.dim;

		paint.line(middle - reach, centre - reach, middle + reach, centre + reach, weight, ink);
		paint.line(middle - reach, centre + reach, middle + reach, centre - reach, weight, ink);
	}

	function traced(paint:Paint, theme:Theme, metrics:Metrics, row:Int,
			colour:mdd.ui.Colour):Void {
		final line = lineOf(row);
		if (line == null || line.points.length == 0) return;

		final hair = metrics.whole(2);
		final knob = metrics.whole(KNOB);

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

			final lit = row == overSegmentAt && index == overSegment;

			paint.polyline(trace, many, lit ? hair + metrics.whole(1) : hair, colour,
				lit ? 1 : 0.9);

			if (!lit) continue;

			final middle = Std.int((from.at + to.at) / 2);
			final level = atValue(row, Automation.between(from, to, middle));

			paint.circle(atTick(middle), level, knob * 0.8, theme.bar);
			paint.ring(atTick(middle), level, knob * 0.8, metrics.whole(2), colour, 0.95);
		}

		final last = line.points[line.points.length - 1];

		paint.rect(atTick(last.at), atValue(row, last.value), x + width - atTick(last.at),
			hair, colour, 0.5);

		for (point in line.points) {
			final at = atTick(point.at);
			if (at < x + left - knob || at > x + width + knob) continue;

			final level = atValue(row, point.value);
			final on = chosenAt == row && picked.holds(point);

			paint.circle(at, level, knob, on ? theme.ink : colour);

			if (on) paint.ring(at, level, knob + metrics.whole(2), metrics.whole(1),
				theme.accent, point == chosen ? 1 : 0.6);
		}
	}

	function band(paint:Paint, theme:Theme, metrics:Metrics):Void {
		final left = bandFromX < bandToX ? bandFromX : bandToX;
		final top = bandFromY < bandToY ? bandFromY : bandToY;
		final wide = bandToX > bandFromX ? bandToX - bandFromX : bandFromX - bandToX;
		final tall = bandToY > bandFromY ? bandToY - bandFromY : bandFromY - bandToY;

		if (wide < 1 || tall < 1) return;

		paint.rect(left, top, wide, tall, theme.ink, 0.1);
		paint.outline(left, top, wide, tall, theme.ink, metrics.whole(1), 0.6);
	}
}
