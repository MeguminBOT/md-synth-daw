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

/**
	The automation lanes: several parameters at once, each a row of points over time.

	The piano roll and the automation editor both draw this, so a point is the same
	point in either. A point carries a curve that reaches the next one rather than only
	stepping or ramping, and the row header is where a lane is chosen, folded or
	swapped for another.
**/
final class Lanes extends Widget {
	/**
		The shortest a lane row may be drawn.
	**/
	public static inline final LEAST_ROW = 40;

	/**
		The tallest.
	**/
	public static inline final MOST_ROW = 220;

	/**
		How tall a row is by default.
	**/
	public static inline final ROW = 92;

	/**
		The fewest values a lane may be zoomed in to show.
	**/
	public static inline final LEAST_SPAN = 8;

	/**
		What one turn of the wheel over a lane's scale multiplies the values it shows by.
	**/
	static inline final ZOOM = 0.5;

	/**
		How many values a wide lane shows the first time it appears with no points to fit to.
	**/
	public static inline final FIRST_SPAN = 64;

	static inline final REACH = 8;
	static inline final KNOB = 5;
	static inline final TRACE = 512;

	/**
		How many times slower the pointer moves over a point dragged with Ctrl held.
	**/
	static inline final PRECISE = 8.0;

	/**
		The session to read.
	**/
	public final session:Session;

	/**
		Which lanes are shown, packed as a target and a slot.
	**/
	public final targets:Array<Int> = [];

	/**
		How many pixels a tick is, which is the zoom.
	**/
	public var perTick:Float = 0.25;

	/**
		How far the view is scrolled, across.
	**/
	public var offsetX:Float = 0;

	/**
		Where the plot starts, across, past the row headers.
	**/
	public var left:Float = 0;

	/**
		How tall one row is.
	**/
	public var rowTall:Float = 0;

	/**
		Whether clicking empty space adds a point rather than only selecting.
	**/
	public var adding:Bool = true;

	/**
		How far the view is scrolled, down.
	**/
	public var offsetY:Float = 0;

	final heights:Array<Float> = [];
	final remembered:Map<Int, Float> = new Map<Int, Float>();
	final shut:Map<Int, Bool> = new Map<Int, Bool>();

	/**
		The lowest value each zoomed lane shows, by lane. A lane with no entry shows every value its
		parameter takes.
	**/
	final lows:Map<Int, Int> = new Map<Int, Int>();

	/**
		The highest value each zoomed lane shows, by lane.
	**/
	final highs:Map<Int, Int> = new Map<Int, Int>();

	/**
		The lanes last fitted to their points and not zoomed since, which a double click on the scale
		returns to every value rather than fitting again.
	**/
	final fitted:Map<Int, Bool> = new Map<Int, Bool>();

	/**
		The lanes that have been given their first view, so one unzoomed by hand is not framed again.
	**/
	final framed:Map<Int, Bool> = new Map<Int, Bool>();

	var ranging:Int = -1;
	var rangeFrom:Float = 0;
	var rangeLow:Int = 0;

	/**
		Called to open the menu that chooses which lane a row shows.
	**/
	public var onOffer:Null<(Lanes, Int, Float, Float) -> Void> = null;

	/**
		Called to open the menu that chooses a point curve.
	**/
	public var onShape:Null<(Lanes, Int, Point, Float, Float) -> Void> = null;

	/**
		The automation clip being edited, where one is.
	**/
	public var holding:Null<mdd.song.Clip> = null;

	/**
		The instrument whose lanes are edited, by index, where they are what a preset moves on
		every note rather than a pattern's, or -1. A preset's lanes are measured from the key on:
		one in milliseconds draws a millisecond where a pattern draws a tick, and one that follows
		the tempo draws its 960ths of a beat at the tempo the song opens at, so both sit on the
		same axis. A clip being edited takes precedence.
	**/
	public var preset:Int = -1;

	/**
		Where the playhead is, or -1 for nowhere.
	**/
	public var playhead:Int = -1;

	/**
		Which point is chosen.
	**/
	public var chosen(default, null):Null<Point> = null;
	var chosenAt(default, null):Int = -1;

	/**
		Which points are selected.
	**/
	public final picked:Picked<Point> = new Picked<Point>();

	static inline final STACK = -2;

	var sizing:Int = -1;
	var grabY:Float = 0;
	var grabTall:Float = 0;

	var hoverEdge:Int = -1;
	var hoverRow:Int = -1;
	var hoverName:Bool = false;
	var hoverShed:Bool = false;
	var hoverFold:Bool = false;
	var hoverWiden:Bool = false;

	/**
		Whether one lane is maximized, folding every other one away until it is restored.
	**/
	var widening:Bool = false;

	/**
		Which target the maximized lane shows, while `widening` is true.
	**/
	var widened:Int = 0;
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
	var fresh:Bool = false;
	var bending:Int = -1;
	var bentFrom:Float = 0;
	var bentWas:Int = 0;
	var bentPoint:Null<Point> = null;
	var wasAt:Int = 0;
	var wasValue:Int = 0;


	var overSegment:Int = -1;
	var overSegmentAt:Int = -1;

	final trace:Vector<Float> = new Vector<Float>(TRACE * 2);

	/**
		The chosen point position, typed or dragged.
	**/
	public final position:Number;

	/**
		Its value.
	**/
	public final amount:Number;

	/**
		Which curve reaches the next point.
	**/
	public final shape:Number;

	/**
		How hard that curve bends.
	**/
	public final bend:Number;

	/**
		How many steps a stepped curve takes.
	**/
	public final steps:Number;

	final fields:Array<Number>;

	var settling:Bool = false;

	/**
		Builds the lanes and the fields that edit a point.

		@param session The session to read.
	**/
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

		position.tipKey = Locale.LANE_POSITION;
		amount.tipKey = Locale.LANE_AMOUNT;
		shape.tipKey = Locale.LANE_SHAPE;
		bend.tipKey = Locale.LANE_BEND;
		steps.tipKey = Locale.LANE_STEPS;

		for (one in fields) {
			one.visible = false;
			add(one);
		}

		position.derived = function(value:Int):String return spelt(value);
		shape.derived = function(value:Int):String
			return translate(mdd.view.Shapes.NAMES[value]);

		position.onChange = function(from:Number):Void placed();
		amount.onChange = function(from:Number):Void placed();

		shape.onChange = function(from:Number):Void shaped();
		bend.onChange = function(from:Number):Void shaped();
		steps.onChange = function(from:Number):Void shaped();
	}

	function spelt(tick:Int):String {
		if (instrumented() != null) {
			final line = lineOf(chosenAt);

			if (line != null && line.synced) {
				return Math.round(tick * 100 / Automation.BEAT) / 100 + " " + translate(Locale.LANE_BEATS_SHORT);
			}

			return tick + " ms";
		}

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
			slotted(chosenAt), was, position.value, amount.value, driven(), presetting()));

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

		position.spans(0, instrumented() != null ? 1 << 20 : (pattern == null ? 1 << 24 : pattern.length));
		amount.spans(one.low, one.high);

		position.label = translate(Locale.POINT_AT);
		position.tipKey = instrumented() != null ? Locale.LANE_AFTER : Locale.LANE_POSITION;
		amount.label = one.titled(slotted(chosenAt));
		shape.label = translate(Locale.POINT_SHAPE);
		bend.label = translate(Locale.POINT_BEND);
		steps.label = translate(Locale.POINT_STEPS);

		amount.derived = function(value:Int):String return told(one, value);

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

	/**
		@return How many lane rows are shown.
	**/
	public inline function rows():Int {
		return holding == null ? targets.length : 1;
	}

	/**
		@param held The parameter a lane is.
		@param value A value of it.
		@return What the value means, which for a preset lane is the preset's name.
	**/
	function told(held:Parameter, value:Int):String {
		if (held.target != Automation.INSTRUMENT) return held.said(value);

		final instrument = session.song.instrumentAt(value);
		return instrument == null ? "" + value : instrument.name;
	}

	inline function driven():Null<Automation> {
		return holding == null ? null : holding.line;
	}

	/**
		@return The instrument whose lanes are edited, or null where a pattern's or a clip's are.
	**/
	public function instrumented():Null<mdd.song.Instrument> {
		return preset < 0 || holding != null ? null : session.song.instrumentAt(preset);
	}

	/**
		@return Which instrument an edit acts on, by index, or -1 for the pattern or the clip.
	**/
	inline function presetting():Int {
		return holding == null ? preset : -1;
	}

	/**
		@param row Which lane row.
		@return How many of the axis's units one of the lane's is: one, except on a preset's lane
			that follows the tempo, which counts 960ths of a beat where the axis counts
			milliseconds.
	**/
	function scaleOf(row:Int):Float {
		if (instrumented() == null) return 1;

		final line = lineOf(row);
		if (line == null || !line.synced) return 1;

		final beats = session.song.tempo.beatsAt(0);
		return 60000 / ((beats <= 0 ? 120 : beats) * Automation.BEAT);
	}

	/**
		@param row Which lane row.
		@param at A place on its lane.
		@return Where that draws, across.
	**/
	inline function atPlace(row:Int, at:Float):Float {
		return x + left - offsetX + at * scaleOf(row) * perTick;
	}

	/**
		@param row Which lane row.
		@param px A point, across.
		@return Which place on its lane that is.
	**/
	inline function placeAt(row:Int, px:Float):Int {
		return Math.round((px - x - left + offsetX) / perTick / scaleOf(row));
	}

	/**
		@param row Which lane row.
		@param at A place on its lane.
		@param free Whether to ignore the snap, which holding alt does.
		@return The place snapped: to the song's grid for a pattern, a clip or a preset's lane that
			follows the tempo, and to the millisecond grid for a preset's lane in milliseconds.
	**/
	function snapsIn(row:Int, at:Int, free:Bool):Int {
		if (free) return at;
		if (instrumented() == null) return session.snapped(at);

		final line = lineOf(row);

		if (line != null && line.synced) {
			final ppqn = session.song.tempo.ppqn;
			final tick = session.snapped(Math.round(at * ppqn / Automation.BEAT));
			return Math.round(tick * Automation.BEAT / ppqn);
		}

		final grid = msGrid();
		return Math.round(at / grid) * grid;
	}

	/**
		The millisecond steps the grid of a preset's lanes may take, the finest first.
	**/
	static final GRIDS:Array<Int> = [1, 2, 5, 10, 20, 50, 100, 200, 500, 1000];

	/**
		@return The finest millisecond step at least seven pixels wide at the zoom in use, which is
			the grid a preset's lanes snap to and draw.
	**/
	public function msGrid():Int {
		final root = root();
		final least = root == null ? 7 : root.metrics.whole(7);

		for (step in GRIDS) if (step * perTick >= least) return step;
		return GRIDS[GRIDS.length - 1];
	}

	/**
		@return How far a preset's lanes are shown from the key on, in milliseconds: past the end of
			the longest by a quarter, and never less than two seconds.
	**/
	public function presetSpan():Int {
		final instrument = instrumented();
		var most = 0.0;

		if (instrument != null) {
			final beats = session.song.tempo.beatsAt(0);
			final unit = 60000 / ((beats <= 0 ? 120 : beats) * Automation.BEAT);

			for (line in instrument.lanes) {
				if (line.points.length == 0) continue;

				final last = line.points[line.points.length - 1].at * (line.synced ? unit : 1);
				if (last > most) most = last;
			}
		}

		final want = Math.ceil(most * 1.25);
		return want < 2000 ? 2000 : want;
	}

	inline function drivenPart():Part {
		return holding == null ? session.part : (holding.part:Part);
	}

	/**
		@return How tall an unfolded row is.
	**/
	public function rowHeight():Float {
		return heightOf(0);
	}

	/**
		@param row Which lane row.
		@return How tall it draws, which is the header alone where it is folded.
	**/
	public function heightOf(row:Int):Float {
		if (folded(row)) return headTall();
		if (rowTall > 0) return rowTall;

		if (row >= 0 && row < heights.length && heights[row] > 0) return heights[row];

		final root = root();
		return root == null ? ROW : root.metrics.whole(ROW);
	}

	/**
		@param row Which lane row.
		@return Whether it is folded away.
	**/
	public function folded(row:Int):Bool {
		if (row < 0 || row >= targets.length) return false;
		if (widening && targets.indexOf(widened) >= 0) return targets[row] != widened;

		return shut.exists(targets[row]) && shut.get(targets[row]);
	}

	/**
		Maximizes a row, so it takes the whole room and every other row folds to its header, or
		restores every row where that one is already maximized.

		@param row Which lane row.
	**/
	public function widens(row:Int):Void {
		if (row < 0 || row >= targets.length) return;

		if (widening && widened == targets[row]) {
			widening = false;
		} else {
			widening = true;
			widened = targets[row];
		}

		spreadFor = -1;
		relayout();
	}

	/**
		@param row Which lane row.
		@return Whether it is the maximized one.
	**/
	public function wide(row:Int):Bool {
		return widening && row >= 0 && row < targets.length && targets[row] == widened;
	}

	/**
		Folds a row away, or unfolds it.

		@param row Which lane row.
	**/
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

	/**
		Shares the room between the unfolded rows.

		@param room How much room there is, down.
	**/
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

		firstViews(row);
	}

	/**
		Gives a lane its first view the first time it appears, where every value its parameter takes
		would be too many to read one step from the next: a lane that is an offset, or one wider than
		a register byte. It is fitted to its points where it has any, and otherwise shows
		`FIRST_SPAN` values from where it rests. A lane zoomed or framed before keeps what it had.

		@param row Which lane row.
	**/
	function firstViews(row:Int):Void {
		final held = parameterOf(row);
		if (held == null) return;

		final key = keyOf(row);
		if (key < 0 || framed.exists(key)) return;

		framed.set(key, true);

		if (lows.exists(key)) return;
		if (!held.offset && held.high - held.low <= 255) return;
		if (held.high - held.low <= FIRST_SPAN) return;

		final line = lineOf(row);

		if (line != null && line.points.length > 0) {
			fits(row);
			return;
		}

		final from = held.offset ? -Std.int(FIRST_SPAN / 2) : held.low;
		ranged(row, from, from + FIRST_SPAN);
	}

	/**
		@return How tall a row header is.
	**/
	public function headTall():Float {
		final root = root();
		return root == null ? 17 : root.metrics.whole(17);
	}

	function footTall():Float {
		final root = root();
		return root == null ? 32 : root.metrics.whole(32);
	}

	/**
		@return How tall every row together would like to be.
	**/
	public function wants():Float {
		var much = holding == null ? footTall() : 0.0;
		for (row in 0...rows()) much += heightOf(row);

		return much;
	}

	/**
		@param row Which lane row.
		@return Where its plot starts, down, past its header.
	**/
	public inline function plotTop(row:Int):Float {
		return rowTop(row) + headTall();
	}

	/**
		@param row Which lane row.
		@return How tall its plot is.
	**/
	public inline function plotTall(row:Int):Float {
		return heightOf(row) - headTall();
	}

	function footTop():Float {
		var much = y - offsetY;
		for (row in 0...rows()) much += heightOf(row);

		return much;
	}

	/**
		@param row Which lane row.
		@return Which lane it shows.
	**/
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

	/**
		@param row Which lane row.
		@return Which operator it shows, for a per operator lane.
	**/
	public inline function slotOf(row:Int):Int {
		return targets[row] & 0xFF;
	}

	/**
		@param target Which lane, from `Automation`.
		@param slot Which operator, for a per operator lane.
		@return Whether a row is already showing that lane.
	**/
	public function shows(target:Int, slot:Int):Bool {
		return targets.indexOf((target << 8) | slot) >= 0;
	}

	/**
		Adds a row for a lane, unless one is already showing it.

		@param target Which lane, from `Automation`.
		@param slot Which operator, for a per operator lane.
	**/
	public function show(target:Int, slot:Int):Void {
		final want = (target << 8) | slot;
		if (targets.indexOf(want) >= 0) return;

		targets.push(want);
		recalls(targets.length - 1);

		relayout();
	}

	/**
		Takes a row away and removes the points it shows, as one step on the undo stack.
		A row showing a lane that carries nothing is taken away on its own.

		@param row Which lane row.
	**/
	public function sheds(row:Int):Void {
		if (row < 0 || row >= targets.length) return;

		final line = lineOf(row);
		final held = parameterOf(row);

		if (line != null && line.points.length > 0) {
			final going = line.points.copy();
			final group = new mdd.song.edit.Together("remove "
				+ (held == null ? "a lane" : held.titled(slotted(row))));

			for (point in going) {
				group.also(new RemovePoint(session.pattern, drivenPart(), targeted(row),
					slotted(row), point, driven(), presetting()));
			}

			session.does(group);
		}

		hide(row);
	}

	/**
		Takes a row away, leaving whatever it shows in the song.

		@param row Which lane row.
	**/
	public function hide(row:Int):Void {
		if (row < 0 || row >= targets.length) return;

		targets.splice(row, 1);
		if (row < heights.length) heights.splice(row, 1);

		forgets();

		relayout();
	}

	/**
		Points a row at another lane.

		@param row Which lane row.
		@param target Which lane, from `Automation`.
		@param slot Which operator, for a per operator lane.
	**/
	public function swap(row:Int, target:Int, slot:Int):Void {
		if (row < 0 || row >= targets.length) return;

		targets[row] = (target << 8) | slot;
		recalls(row);

		forgets();

		relayout();
	}

	/**
		How many rows may be shown at once.
	**/
	public var opens:Int = 64;

	var filledFor:Int = -1;

	/**
		Reads the chosen point into the fields that edit it.
	**/
	public function settles():Void {
		if (holding != null) return;

		final key = filledKey();
		if (key == filledFor) return;

		filledFor = key;
		fills(false);
	}

	/**
		@return What the rows were worked out for: the preset whose lanes they are, or the part
			and the pattern.
	**/
	inline function filledKey():Int {
		return preset >= 0 ? -2 - preset : session.part.index() * 4096 + session.pattern;
	}

	/**
		@return Whether another part or pattern has been chosen since the rows were worked out, so
			they are showing what is no longer there.
	**/
	public function stale():Bool {
		return holding == null && filledKey() != filledFor;
	}

	/**
		Works out which rows to show from what the part actually carries.

		@param again Whether to throw away the rows that are already shown.
	**/
	public function fills(again:Bool = true):Void {
		if (holding != null) return;

		final pattern = session.current();

		targets.resize(0);
		heights.resize(0);

		forgets();

		if (preset >= 0) {
			final instrument = instrumented();

			if (instrument != null) {
				for (line in instrument.lanes) {
					if (targets.length >= opens) break;
					if (line.points.length == 0) continue;
					if (Parameter.movedFound(session.part, line.target, line.slot) == null) continue;
					if (shows(line.target, line.slot)) continue;

					targets.push((line.target << 8) | line.slot);
					recalls(targets.length - 1);
				}
			}

			if (again) relayout();
			return;
		}

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

	/**
		@param target Which lane, from `Automation`.
		@param slot Which operator, for a per operator lane.
		@return How many points that lane holds.
	**/
	public function carries(target:Int, slot:Int):Int {
		if (preset >= 0 && holding == null) {
			final instrument = instrumented();
			final line = instrument == null ? null : instrument.lane(target, slot);

			return line == null ? 0 : line.points.length;
		}

		final pattern = session.current();
		if (pattern == null) return 0;

		for (line in pattern.lane(session.part).automation) {
			if (line.held(target, slot)) return line.points.length;
		}

		return 0;
	}

	/**
		Chooses a point and reads it into the fields.

		@param point The point.
		@param row Which lane row.
	**/
	public function picks(point:Point, row:Int):Void {
		chosen = point;
		chosenAt = row;
		picked.only(point);

		relayout();
	}

	/**
		@param many How many there are.
		@return What to call them in an undo entry. Those name a step for the gate to
			recognise rather than for a reader, and nothing puts one on screen, so this
			stays in one language.
	**/
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

	/**
		Selects every point in the shown rows.

		@return Whether anything was selected.
	**/
	public function picksAll():Bool {
		final row = chosenAt < 0 ? 0 : chosenAt;
		final line = lineOf(row);

		if (line == null || line.points.length == 0) return false;

		picked.clear();
		for (point in line.points) picked.adds(point);

		chosen = picked.lead();
		chosenAt = row;

		session.says(Locale.SAID_POINTS_SELECTED, "" + picked.count);
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
		final line = lineOf(chosenAt);
		final held:Array<Point> = [];

		if (line != null) {
			for (point in line.points) if (picked.holds(point)) held.push(point);
		}

		if (held.length == 0) return false;

		var least = held[0].at;
		for (point in held) if (point.at < least) least = point.at;

		session.copiedPoints.resize(0);

		for (point in held) {
			final made = point.copy();
			made.at -= least;

			session.copiedPoints.push(made);
		}

		session.says(Locale.SAID_POINTS_COPIED, "" + held.length);
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
				slotted(row), point, driven(), presetting()));
		}

		if (made.length == 0) return false;
		session.does(group);

		picked.clear();
		for (point in made) picked.adds(point);

		chosen = picked.lead();
		chosenAt = row;

		session.says(Locale.SAID_POINTS_PASTED, "" + made.length);
		relayout();

		return true;
	}

	/**
		@return How near a point counts as being on it, for dragging.
	**/
	public function edge():Float {
		final root = root();
		return root == null ? 5 : root.metrics.whole(5);
	}

	function edgeAt(px:Float, py:Float):Int {
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

	/**
		@param py A point, down.
		@return Which row is there, or -1.
	**/
	public function rowAt(py:Float):Int {
		var top = y - offsetY;

		for (row in 0...rows()) {
			final tall = heightOf(row);
			if (py >= top && py < top + tall) return row;

			top += tall;
		}

		return -1;
	}

	/**
		@param row Which lane row.
		@return Where it starts, down.
	**/
	public function rowTop(row:Int):Float {
		var top = y - offsetY;
		for (before in 0...row) top += heightOf(before);

		return top;
	}

	/**
		@param tick A position in the piece, in ticks.
		@param free Whether to ignore the snap, which holding alt does.
		@return The tick snapped, or left alone.
	**/
	public inline function freely(tick:Int, free:Bool):Int {
		return free ? tick : session.snapped(tick);
	}

	/**
		@param px A point, across.
		@return Which tick is there.
	**/
	public inline function tickAt(px:Float):Int {
		return Math.round((px - x - left + offsetX) / perTick);
	}

	/**
		@param tick A position in the piece, in ticks.
		@return Where it draws, across.
	**/
	public inline function atTick(tick:Int):Float {
		return x + left - offsetX + tick * perTick;
	}

	/**
		@param row Which lane row.
		@return What that lane actually is, or null where the part does not have it.
	**/
	public function parameterOf(row:Int):Null<Parameter> {
		if (row < 0 || row >= rows()) return null;

		final line = driven();
		if (line != null) return Parameter.found(drivenPart(), line.target, line.slot);

		if (preset >= 0) return Parameter.movedFound(session.part, targetOf(row), slotOf(row));

		return Parameter.found(session.part, targetOf(row), slotOf(row));
	}

	/**
		@param row Which lane row.
		@return The lane itself, or null where nothing has been written to it yet.
	**/
	public function lineOf(row:Int):Null<Automation> {
		if (holding != null) return row == 0 ? holding.line : null;

		if (preset >= 0) {
			final instrument = instrumented();
			if (instrument == null || row < 0 || row >= rows()) return null;

			return instrument.lane(targetOf(row), slotOf(row));
		}

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

		final low = lowOf(row);
		final span = highOf(row) - low;
		if (span <= 0) return plotTop(row);

		final inset = padding();
		final room = plotTall(row) - inset * 2;
		final part = (value - low) / span;
		final up = held.attenuates() ? 1 - part : part;

		return plotTop(row) + inset + room * (1 - up);
	}

	function valueAt(row:Int, py:Float):Int {
		final held = parameterOf(row);
		if (held == null) return 0;

		final low = lowOf(row);
		return held.holds(low + Math.round((highOf(row) - low) * partAt(row, py)));
	}

	/**
		@param row Which lane row.
		@param py A point, down.
		@return How far up the values the row shows the point sits, from nought at its lowest value to
			one at its highest, held inside the plot.
	**/
	function partAt(row:Int, py:Float):Float {
		final held = parameterOf(row);
		final inset = padding();
		final room = plotTall(row) - inset * 2;
		if (held == null || room <= 0) return 0;

		var up = 1 - (py - plotTop(row) - inset) / room;
		if (up < 0) up = 0;
		if (up > 1) up = 1;

		return held.attenuates() ? 1 - up : up;
	}

	/**
		@param row Which lane row.
		@return The lane a row shows, packed as a target and a slot, which is what its zoom is kept
			under, so a zoom follows its lane to whichever row shows it.
	**/
	function keyOf(row:Int):Int {
		final line = driven();
		if (line != null) return (line.target << 8) | line.slot;

		return row >= 0 && row < targets.length ? targets[row] : -1;
	}

	/**
		@param row Which lane row.
		@return The lowest value the row shows, which is the lowest its parameter takes unless the row
			is zoomed.
	**/
	public function lowOf(row:Int):Int {
		final held = parameterOf(row);
		if (held == null) return 0;

		final key = keyOf(row);
		return lows.exists(key) ? lows.get(key) : held.low;
	}

	/**
		@param row Which lane row.
		@return The highest value the row shows.
	**/
	public function highOf(row:Int):Int {
		final held = parameterOf(row);
		if (held == null) return 0;

		final key = keyOf(row);
		return highs.exists(key) ? highs.get(key) : held.high;
	}

	/**
		@param row Which lane row.
		@return Whether the row shows fewer values than its parameter takes.
	**/
	public function zoomed(row:Int):Bool {
		return lows.exists(keyOf(row));
	}

	/**
		Shows a row between two values, held inside what its parameter takes and to at least
		`LEAST_SPAN` of them. A range as wide as the parameter is forgotten rather than kept.

		@param row Which lane row.
		@param low The lowest value to show.
		@param high The highest.
	**/
	function ranged(row:Int, low:Int, high:Int):Void {
		final held = parameterOf(row);
		if (held == null) return;

		final full = held.high - held.low;
		final least = LEAST_SPAN < full ? LEAST_SPAN : full;

		var span = high - low;
		if (span < least) span = least;
		if (span > full) span = full;

		var from = low;
		if (from + span > held.high) from = held.high - span;
		if (from < held.low) from = held.low;

		final key = keyOf(row);

		if (span >= full) {
			lows.remove(key);
			highs.remove(key);
		} else {
			lows.set(key, from);
			highs.set(key, from + span);
		}

		fitted.remove(key);
		invalidate();
	}

	/**
		Zooms the values a row shows in or out, keeping the value under the pointer where it is.

		@param row Which lane row.
		@param py Where the pointer is, down.
		@param by What to multiply the span shown by: under one zooms in.
	**/
	public function zooms(row:Int, py:Float, by:Float):Void {
		if (parameterOf(row) == null) return;

		final low = lowOf(row);
		final span = highOf(row) - low;
		if (span <= 0) return;

		final part = partAt(row, py);
		final want = Math.round(span * by);
		final from = Math.round(low + span * part - want * part);

		ranged(row, from, from + want);
	}

	/**
		Zooms a row to the values its points reach, with a little room either side. A lane that is an
		offset keeps nought in view, and a row with no points shows every value again.

		@param row Which lane row.
	**/
	public function fits(row:Int):Void {
		final held = parameterOf(row);
		final line = lineOf(row);
		if (held == null) return;

		if (line == null || line.points.length == 0) {
			unzooms(row);
			return;
		}

		var least = line.points[0].value;
		var most = least;

		for (point in line.points) {
			if (point.value < least) least = point.value;
			if (point.value > most) most = point.value;
		}

		if (held.offset) {
			if (least > 0) least = 0;
			if (most < 0) most = 0;
		}

		final room = Math.ceil((most - least) * 0.1) + 1;
		final span = most - least + room * 2;

		if (span >= LEAST_SPAN) {
			ranged(row, least - room, most + room);
		} else {
			final from = Math.floor((least + most - LEAST_SPAN) * 0.5);
			ranged(row, from, from + LEAST_SPAN);
		}

		fitted.set(keyOf(row), true);
	}

	/**
		Shows every value a row's parameter takes again.

		@param row Which lane row.
	**/
	public function unzooms(row:Int):Void {
		final key = keyOf(row);

		lows.remove(key);
		highs.remove(key);
		fitted.remove(key);

		invalidate();
	}

	/**
		Moves the values a zoomed row shows with the pointer dragging its scale, so what is under the
		pointer stays under it.

		@param py Where the pointer is, down.
	**/
	function panned(py:Float):Void {
		final held = parameterOf(ranging);
		final room = plotTall(ranging) - padding() * 2;
		if (held == null || room <= 0) return;

		final span = highOf(ranging) - lowOf(ranging);
		final by = Math.round((py - rangeFrom) / room * span) * (held.attenuates() ? -1 : 1);

		if (zoomed(ranging)) ranged(ranging, rangeLow + by, rangeLow + by + span);
	}

	/**
		@param px A point, across.
		@param py A point, down.
		@return The row whose scale the point is on, which is the strip of values beside its plot, or
			-1 for none.
	**/
	function scaleAt(px:Float, py:Float):Int {
		if (left <= 0 || px < x || px >= x + left) return -1;

		final row = rowAt(py);
		if (row < 0 || folded(row) || parameterOf(row) == null) return -1;

		final top = plotTop(row);
		return py >= top && py < top + plotTall(row) ? row : -1;
	}

	/**
		Offers what a row's scale can show: fitted to its points, every value, and for a lane that is
		an offset, a span either side of nought.

		@param row Which lane row.
		@param px Where the menu opens, across.
		@param py Where it opens, down.
	**/
	function scaled(row:Int, px:Float, py:Float):Void {
		final root = root();
		final held = parameterOf(row);
		if (root == null || held == null) return;

		final menu = new mdd.ui.control.Menu();
		final line = lineOf(row);

		final fit = menu.offer(new mdd.ui.control.Choice(translate(Locale.LANE_FIT)));
		fit.enabled = line != null && line.points.length > 0;
		fires(fit, function():Void fits(row));

		final whole = menu.offer(new mdd.ui.control.Choice(translate(Locale.LANE_RESET)));
		whole.enabled = zoomed(row);
		fires(whole, function():Void unzooms(row));

		if (held.offset && held.low < 0 && held.high > 0) {
			menu.divide();

			var reach = 1;
			while (reach * 2 < held.high) reach *= 2;

			while (reach * 2 >= LEAST_SPAN) {
				final each = reach;
				final choice = menu.offer(new mdd.ui.control.Choice("±" + each));

				choice.enabled = lowOf(row) != -each || highOf(row) != each;
				fires(choice, function():Void ranged(row, -each, each));

				reach = Std.int(reach / 2);
			}
		}

		root.pop(menu, px, py, this);
	}

	function padding():Float {
		final root = root();
		return root == null ? 9 : root.metrics.whole(9);
	}

	function pointAt(row:Int, px:Float, py:Float):Null<Point> {
		final line = lineOf(row);
		if (line == null) return null;

		final root = root();
		final reach = root == null ? REACH : root.metrics.whole(REACH);

		var found:Null<Point> = null;
		var least = reach * reach * 4;

		for (point in line.points) {
			final dx = atPlace(row, point.at) - px;
			final dy = atValue(row, point.value) - py;
			final away = dx * dx + dy * dy;

			if (away > least) continue;

			least = away;
			found = point;
		}

		return found;
	}

	function segmentAt(row:Int, px:Float):Int {
		final line = lineOf(row);
		if (line == null || line.points.length < 2) return -1;

		for (index in 0...line.points.length - 1) {
			if (!Automation.moves(line.points[index].shape)) continue;

			if (px >= atPlace(row, line.points[index].at)
				&& px < atPlace(row, line.points[index + 1].at)) return index;
		}

		return -1;
	}

	function bendAt(row:Int, px:Float, py:Float):Int {
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

			final dx = atPlace(row, middle) - px;
			final dy = atValue(row, Automation.between(from, to, middle)) - py;

			if (dx * dx + dy * dy > reach * reach * 4) continue;

			return index;
		}

		return -1;
	}

	/**
		The line between two lanes resizes them, and nothing on the screen says so.

		@param px A point, across.
		@param py A point, down.
		@return Which cursor shape belongs there.
	**/
	override function cursorAt(px:Float, py:Float):Int {
		if (sizing != -1 || ranging != -1 || edgeAt(px, py) != -1) return mdd.host.Sdl.CURSOR_DOWN;
		if (scaleAt(px, py) != -1) return mdd.host.Sdl.CURSOR_DOWN;

		return mdd.host.Sdl.CURSOR_ARROW;
	}

	override function took(event:Input):Bool {
		switch (event.kind) {
			case Kind.Wheel:
				final row = scaleAt(event.x, event.y);
				if (row < 0 || event.dy == 0) return false;

				zooms(row, event.y, event.dy > 0 ? ZOOM : 1 / ZOOM);
				return true;

			case Kind.PointerDown:
				return pressed(event);

			case Kind.PointerMove:
				return moved(event);

			case Kind.PointerUp:
				if (banding) banded();
				if (dragging != null) dropped();
				if (bending >= 0) bendDropped();

				dragging = null;
				bending = -1;
				sizing = -1;
				ranging = -1;
				precision = 1;
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

		final scale = scaleAt(event.x, event.y);

		if (scale >= 0) {
			if (event.button == Pointer.Right) {
				scaled(scale, event.x, event.y);
				return true;
			}

			if (event.clicks > 1) {
				if (fitted.exists(keyOf(scale))) unzooms(scale);
				else fits(scale);

				return true;
			}

			ranging = scale;
			rangeFrom = event.y;
			rangeLow = lowOf(scale);
			return true;
		}

		final row = rowAt(event.y);
		if (row < 0) return false;

		if (event.y < rowTop(row) + headTall()) {
			if (onShed(row, event.x)) {
				sheds(row);
				return true;
			}

			if (onWiden(row, event.x)) {
				widens(row);
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
			fresh = false;

			grabs(point, row);
			precision = PRECISE;

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
			final at = atPlace(bandRow, point.at);
			final up = atValue(bandRow, point.value);

			if (at < left || at > right || up < top || up > floor) continue;
			picked.adds(point);
		}

		chosen = picked.lead();
		chosenAt = picked.count == 0 ? -1 : bandRow;

		if (picked.count > 0) session.says(Locale.SAID_POINTS_SELECTED, "" + picked.count);
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
		if (holding == null && preset < 0 && session.current() == null) return;
		if (holding == null && preset >= 0 && instrumented() == null) return;

		var tick = snapsIn(row, placeAt(row, px), event.alt());
		if (tick < 0) tick = 0;

		final line = lineOf(row);
		if (line != null && line.marks(tick)) return;

		final point = new Point(tick, valueAt(row, py));
		point.shape = held.smooth ? Automation.LINEAR : Automation.HOLD;

		session.does(new AddPoint(session.pattern, drivenPart(), targeted(row),
			slotted(row), point, driven(), presetting()));

		picked.only(point);

		chosen = point;
		chosenAt = row;

		dragging = point;
		draggingAt = row;
		wasAt = point.at;
		wasValue = point.value;
		fresh = true;

		grabs(point, row);

		session.say(held.titled(slotted(row)) + "  " + told(held, point.value));

		precision = PRECISE;
		relayout();
	}

	function shifts(byTick:Int, byValue:Int, held:Parameter):Void {
		var tick = byTick;
		var value = byValue;

		if (leastAt + tick < 0) tick = -leastAt;
		if (leastValue + value < held.low) value = held.low - leastValue;
		if (mostValue + value > held.high) value = held.high - mostValue;

		for (index in 0...moving.length) {
			moving[index].at = movingAt[index] + tick;
			moving[index].value = held.holds(movingValue[index] + value);
		}

		final line = lineOf(draggingAt);
		if (line != null) line.sort();

		session.changed();
	}

	function dropped():Void {
		if (draggingAt < 0 || moving.length == 0) return;

		if (fresh) {
			fresh = false;
			return;
		}

		var many = 0;

		for (index in 0...moving.length) {
			if (moving[index].at != movingAt[index]
				|| moving[index].value != movingValue[index]) many++;
		}

		if (many == 0) return;

		final wantAt:Array<Int> = [];
		final wantValue:Array<Int> = [];

		for (point in moving) {
			wantAt.push(point.at);
			wantValue.push(point.value);
		}

		for (index in 0...moving.length) {
			moving[index].at = movingAt[index];
			moving[index].value = movingValue[index];
		}

		if (moving.length == 1) {
			session.does(new MovePoint(session.pattern, drivenPart(), targeted(draggingAt),
				slotted(draggingAt), moving[0], wantAt[0], wantValue[0], driven(), presetting()));

			return;
		}

		final group = new mdd.song.edit.Together("move " + counted(moving.length));

		for (index in 0...moving.length) {
			group.also(new MovePoint(session.pattern, drivenPart(), targeted(draggingAt),
				slotted(draggingAt), moving[index], wantAt[index], wantValue[index],
				driven(), presetting()));
		}

		session.does(group);
	}

	function erased():Bool {
		if (chosenAt < 0 || picked.count == 0) return false;

		final row = chosenAt;
		final line = lineOf(row);
		final held:Array<Point> = [];

		if (line != null) {
			for (point in line.points) if (picked.holds(point)) held.push(point);
		}

		if (held.length == 0) {
			forgets();
			return false;
		}

		if (held.length == 1) {
			session.does(new RemovePoint(session.pattern, drivenPart(), targeted(row),
				slotted(row), held[0], driven(), presetting()));
		} else {
			final group = new mdd.song.edit.Together("remove " + counted(held.length));

			for (point in held) {
				group.also(new RemovePoint(session.pattern, drivenPart(), targeted(row),
					slotted(row), point, driven(), presetting()));
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

		if (ranging != -1) {
			panned(event.y);
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

			var tick = event.ctrl() ? placeAt(draggingAt, event.x)
				: snapsIn(draggingAt, placeAt(draggingAt, event.x), event.alt());

			if (tick < 0) tick = 0;

			final value = valueAt(draggingAt, event.y);

			if (tick == dragging.at && value == dragging.value) return true;

			shifts(tick - wasAt, value - wasValue, held);

			session.say(held.titled(slotted(draggingAt)) + "  " + told(held, value));
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

		final widen = row >= 0 && event.y < rowTop(row) + headTall()
			&& onWiden(row, event.x);

		described(row, name, shed, fold, widen, foot, grip == -1 && !foot
			? scaleAt(event.x, event.y) : -1);

		if (row == hoverRow && name == hoverName && shed == hoverShed && fold == hoverFold
			&& widen == hoverWiden && foot == hoverFoot && grip == hoverEdge
			&& segment == overSegment && row == overSegmentAt) return false;

		hoverFold = fold;
		hoverWiden = widen;

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

	/**
		Says in the tooltip what the pointer is over in a lane's header, on its scale or on the
		foot that adds one. A plot says nothing, because its points are the music itself.

		@param row The row under the pointer, or -1.
		@param name Whether the pointer is on the row's name.
		@param shed Whether it is on the button that takes the row away.
		@param fold Whether it is on the button that folds the row.
		@param widen Whether it is on the button that maximizes the row.
		@param foot Whether it is on the foot.
		@param scale The row whose scale it is on, or -1.
	**/
	function described(row:Int, name:Bool, shed:Bool, fold:Bool, widen:Bool, foot:Bool,
			scale:Int):Void {
		detail = "";

		if (foot) tip = translate(Locale.LANE_ADD);
		else if (scale >= 0) {
			tip = translate(Locale.LANE_SCALE);
			detail = translate(Locale.LANE_SCALE_DETAIL);
		} else if (shed) {
			tip = translate(Locale.LANE_SHED);
			detail = translate(Locale.LANE_SHED_DETAIL);
		} else if (widen) tip = translate(wide(row) ? Locale.LANE_RESTORE : Locale.LANE_WIDEN);
		else if (fold) tip = translate(folded(row) ? Locale.LANE_UNFOLD : Locale.LANE_FOLD);
		else if (name) tip = translate(Locale.LANE_CHOOSE);
		else tip = "";
	}

	function bent(event:Input):Bool {
		if (chosen == null) return true;

		final much = (bentFrom - event.y) / (rowHeight() * 0.5);
		var want = bentWas + Math.round(much * Automation.MOST_TENSION);

		if (want < -Automation.MOST_TENSION) want = -Automation.MOST_TENSION;
		if (want > Automation.MOST_TENSION) want = Automation.MOST_TENSION;

		if (want == chosen.tension) return true;

		chosen.tension = want;
		bentPoint = chosen;

		session.says(Locale.SAID_TENSION, "" + want);
		session.changed();
		invalidate();

		return true;
	}

	function bendDropped():Void {
		final point = bentPoint;

		bentPoint = null;
		if (point == null || point.tension == bentWas) return;

		final want = point.tension;
		point.tension = bentWas;

		session.does(new ShapePoint(point, point.shape, want, point.steps));
	}

	override function hovered(on:Bool):Void {
		if (!on) {
			hoverRow = -1;
			hoverName = false;
			hoverShed = false;
			hoverFold = false;
			hoverWiden = false;
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

	function onFoot(px:Float, py:Float):Bool {
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

		final low = lowOf(row);
		final high = highOf(row);
		final nought = held.offset && low < 0 && high > 0;

		if (nought) {
			final zero = atValue(row, 0);
			paint.rect(x + left, zero, width - left, metrics.whole(1), theme.frame, 0.8);
		}

		traced(paint, theme, metrics, row, colour);
		paint.popClip();

		paint.reface(small);

		final ceiling = plotTop(row) + padding();
		final floor = plotTop(row) + plotTall(row) - padding();
		final lift = zoomed(row) ? 0.75 : 0.45;

		paint.textRight(told(held, held.attenuates() ? low : high), x + left - metrics.unit,
			ceiling + small.ascent * 0.5, theme.dim, lift);

		paint.textRight(told(held, held.attenuates() ? high : low),
			x + left - metrics.unit, floor + small.ascent * 0.5, theme.dim, lift);

		if (!nought) return;

		paint.textRight("0", x + left - metrics.unit,
			atValue(row, 0) + small.ascent * 0.5, theme.dim, 0.55);
	}

	function gridded(paint:Paint, theme:Theme, metrics:Metrics, row:Int):Void {
		if (instrumented() != null) {
			timed(paint, theme, metrics, row);
			return;
		}

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

	/**
		Draws the millisecond grid behind a preset's lane, a stronger line every tenth step.
	**/
	function timed(paint:Paint, theme:Theme, metrics:Metrics, row:Int):Void {
		if (perTick <= 0) return;

		final step = msGrid();
		final hair = metrics.whole(1);
		final top = plotTop(row);
		final tall = plotTall(row);
		final from = x + left;
		final reach = presetSpan();

		var at = Std.int(tickAt(from) / step) * step;
		if (at < 0) at = 0;

		while (at <= reach) {
			final px = atTick(at);
			if (px > x + width) break;

			if (px > from) paint.rect(px, top, hair, tall, theme.frame, at % (step * 10) == 0 ? 0.35 : 0.12);

			at += step;
		}
	}

	/**
		@return How long the thing being edited is, in ticks.
	**/
	public function span():Int {
		final pattern = session.current();
		return pattern == null ? session.song.tempo.ppqn * 16 : pattern.length;
	}

	function nameWide(row:Int):Float {
		final root = root();
		final held = parameterOf(row);

		if (root == null || held == null) return 0;

		final metrics = root.metrics;
		final small = metrics.small == null ? metrics.body : metrics.small;

		return metrics.gap + small.measure(held.titled(slotted(row))) + metrics.unit
			+ metrics.whole(7) + metrics.gap;
	}

	/**
		@param row Which lane row.
		@param px A point, across.
		@return Whether the point is on the row name, which is what opens the lane menu.
	**/
	public function onName(row:Int, px:Float):Bool {
		return px >= x && px < x + nameWide(row);
	}

	function onShed(row:Int, px:Float):Bool {
		final root = root();
		if (root == null || holding != null || !adding) return false;

		final metrics = root.metrics;
		return px >= x + width - metrics.whole(20) && px < x + width;
	}

	function onFold(row:Int, px:Float):Bool {
		final root = root();
		if (root == null || holding != null || !adding) return false;

		final metrics = root.metrics;
		final at = x + width - metrics.whole(40);

		return px >= at && px < at + metrics.whole(18);
	}

	function onWiden(row:Int, px:Float):Bool {
		final root = root();
		if (root == null || holding != null || !adding) return false;

		final metrics = root.metrics;
		final at = x + width - metrics.whole(60);

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

			widener(paint, theme, metrics, x + width - metrics.whole(60), top, tall, wide(row),
				lit && hoverWiden);
		}

		final says = held.offset ? translate(Locale.LANE_RIDES) : "";
		final wide = says == "" ? 0.0 : small.measure(says);

		final value = lineOf(row);
		final now = value == null || value.points.length == 0 ? ""
			: told(held, value.valueAt(playhead < 0 ? 0 : playhead));

		final right = x + width - (holding == null && adding ? metrics.whole(62) : metrics.gap);

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

	/**
		Draws the button that maximizes a lane: one square to maximize, two overlapping ones to
		restore.

		@param paint What to draw with.
		@param theme The colours.
		@param metrics The sizes.
		@param at Where the button starts, across.
		@param top Where the header starts, down.
		@param tall How tall the header is.
		@param widened Whether this lane is the maximized one.
		@param lit Whether the pointer is over the button.
	**/
	function widener(paint:Paint, theme:Theme, metrics:Metrics, at:Float, top:Float, tall:Float,
			widened:Bool, lit:Bool):Void {
		final size = metrics.whole(16);
		final box = top + (tall - size) * 0.5;

		if (lit) {
			paint.roundedRect(at, box, size, size, metrics.radiusSmall, theme.accent,
				Theme.HOVER);
		}

		final ink = lit ? theme.ink : theme.dim;
		final hair = metrics.whole(1);
		final side = metrics.whole(8);
		final left = at + (size - side) * 0.5;
		final upper = box + (size - side) * 0.5;

		if (!widened) {
			paint.outline(left, upper, side, side, ink, hair, 0.9, 0);
			return;
		}

		final shift = metrics.whole(2);

		paint.outline(left + shift, upper - shift, side, side, ink, hair, 0.6, 0);
		paint.outline(left - shift, upper + shift, side, side, ink, hair, 0.9, 0);
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

			final headX = atPlace(row, from.at);
			final tailX = atPlace(row, to.at);

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

				trace[step * 2] = atPlace(row, tick);
				trace[step * 2 + 1] = atValue(row, Automation.between(from, to, tick));
			}

			final lit = row == overSegmentAt && index == overSegment;

			paint.polyline(trace, many, lit ? hair + metrics.whole(1) : hair, colour,
				lit ? 1 : 0.9);

			if (!lit) continue;

			final middle = Std.int((from.at + to.at) / 2);
			final level = atValue(row, Automation.between(from, to, middle));

			paint.circle(atPlace(row, middle), level, knob * 0.8, theme.bar);
			paint.ring(atPlace(row, middle), level, knob * 0.8, metrics.whole(2), colour, 0.95);
		}

		final last = line.points[line.points.length - 1];

		if (instrumented() != null && line.loop >= 0 && line.loop < line.points.length - 1) {
			final from = atPlace(row, line.points[line.loop].at);
			final to = atPlace(row, last.at);

			if (to > from) paint.rect(from, plotTop(row), to - from, plotTall(row), colour, 0.08);
		}

		paint.rect(atPlace(row, last.at), atValue(row, last.value), x + width - atPlace(row, last.at),
			hair, colour, 0.5);

		for (point in line.points) {
			final at = atPlace(row, point.at);
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
