package mdd.view.editor;

import mdd.app.Locale;
import mdd.app.Session;
import mdd.song.Automation;
import mdd.song.Clip;
import mdd.song.Part;
import mdd.song.Point;
import mdd.ui.Input;
import mdd.ui.Kind;
import mdd.ui.Metrics;
import mdd.ui.Paint;
import mdd.ui.Panel;
import mdd.ui.Pointer;
import mdd.ui.Theme;
import mdd.ui.Widget;
import mdd.ui.control.Choice;
import mdd.ui.control.Menu;
import mdd.view.Parameter;

@:unreflective

/**
	The automation editor: one clip driving one lane, drawn large.

	It shows what the lanes under the piano roll show, with the room to place points
	precisely. Both draw the same `Lanes`, so a point moved in either is the same point.

	The switch at the right of its header turns it from the chosen pattern's lanes to what the
	chosen channel's preset moves on every note, measured from the key on, where the ruler reads
	milliseconds and a lane's menu says whether it follows the tempo and where it loops.
**/
final class AutomationEditor extends Widget {
	/**
		The session to read.
	**/
	public final session:Session;

	/**
		The lanes, which do the drawing and the editing.
	**/
	public final stack:Lanes;

	/**
		How many pixels a tick is, which is the zoom.
	**/
	public var perTick:Float = 0.25;

	/**
		How far the view is scrolled, across.
	**/
	public var offsetX:Float = 0;

	/**
		Where the playhead is in the song, or -1 for nowhere.
	**/
	public var playhead:Int = -1;

	/**
		Where the chosen pattern starts in the song, in ticks, which the ruler, the playhead and
		scrubbing are measured from while no automation clip is open.
	**/
	public var origin:Int = 0;

	/**
		The clip being edited, where one automation clip is open rather than a pattern.
	**/
	public var holding:Null<Clip> = null;

	/**
		Which lane is shown.
	**/
	public var target:Int = Automation.LEVEL;

	/**
		Which operator, for a per operator lane.
	**/
	public var slot:Int = 0;

	/**
		Whether it shows what the chosen channel's preset moves on every note rather than the
		chosen pattern's lanes. An open automation clip is shown whichever this says.
	**/
	public var presetting(default, null):Bool = false;

	var menu:Null<Menu> = null;

	var patternFrom:Float = 0;
	var patternTo:Float = 0;
	var presetFrom:Float = 0;
	var presetTo:Float = 0;

	/**
		Builds the editor.

		@param session The session to read.
	**/
	public function new(session:Session) {
		super();
		this.session = session;

		focusable = true;
		opaque = true;

		stack = new Lanes(session);
		stack.onOffer = function(from:Lanes, row:Int, px:Float, py:Float):Void
			offered(px, py, row);
		stack.onShape = function(from:Lanes, row:Int, point:Point, px:Float,
			py:Float):Void shaped(row, point, px, py);

		add(stack);
	}

	/**
		@return How tall the header is.
	**/
	public function head():Float {
		final root = root();
		return root == null ? 26 : root.metrics.head;
	}

	/**
		@return How tall the ruler across the top is.
	**/
	public function ruler():Float {
		final root = root();
		return root == null ? 24 : root.metrics.ruler;
	}

	/**
		@return How wide the lane names down the side are.
	**/
	public function gutter():Float {
		final root = root();
		return root == null ? 110 : root.metrics.whole(110);
	}

	/**
		Opens one automation clip, or goes back to the chosen pattern.

		@param clip The clip, or null for the pattern.
	**/
	public function follows(clip:Null<Clip>):Void {
		holding = clip;

		framedSpan = -1;
		framed();
		relayout();
	}

	/**
		Shows one lane.

		@param target Which lane, from `Automation`.
		@param slot Which operator, for a per operator lane.
	**/
	public function shows(target:Int, slot:Int):Void {
		holding = null;

		this.target = target;
		this.slot = slot;

		stack.holding = null;
		stack.show(target, slot);

		framedSpan = -1;
		framed();
		relayout();
	}

	/**
		Turns between the chosen pattern's lanes and what the chosen channel's preset moves.

		@param on Whether to show the preset's.
	**/
	public function presents(on:Bool):Void {
		if (presetting == on) return;

		presetting = on;
		stack.preset = showsPreset() ? presetOf() : -1;

		if (holding == null) stack.settles();

		framedSpan = -1;
		framed();
		relayout();
	}

	/**
		@return Which instrument the chosen channel plays, by index into the song's.
	**/
	public function presetOf():Int {
		return session.song.rack[session.part.index()];
	}

	/**
		@return Whether what is shown is a preset's, which it is while the switch says so and no
			automation clip is open.
	**/
	public inline function showsPreset():Bool {
		return presetting && holding == null;
	}

	/**
		@return How long the thing being edited is, in ticks, or in milliseconds for a preset's
			lanes.
	**/
	public function span():Int {
		if (holding != null) return holding.length;
		if (presetting) return stack.presetSpan();

		final pattern = session.current();
		return pattern == null ? session.song.tempo.ppqn * 16 : pattern.length;
	}

	/**
		@return Which part the lane drives, which is the clip target for an automation clip and the
			chosen part otherwise.
	**/
	public function drivenPart():Part {
		return holding == null ? session.part : (holding.part:Part);
	}

	/**
		@return What the shown lane actually is, or null where the part does not have it.
	**/
	public function held():Null<Parameter> {
		if (holding == null) return Parameter.found(session.part, target, slot);

		final line = holding.line;
		return line == null ? null : Parameter.found(drivenPart(), line.target, line.slot);
	}

	/**
		@param row Which lane row.
		@return What that lane is, or null.
	**/
	public function heldAt(row:Int):Null<Parameter> {
		return holding == null ? stack.parameterOf(row) : held();
	}

	var framedFor:Float = -1;
	var framedSpan:Int = -1;

	/**
		Zooms and scrolls so the whole thing fits.
	**/
	public function framed():Void {
		final room = width - gutter();
		final reach = span();

		if (room <= 0 || reach <= 0) return;
		if (room == framedFor && reach == framedSpan) return;

		framedFor = room;
		framedSpan = reach;

		perTick = widest();
		offsetX = 0;
	}

	/**
		@return How tall the strip along the bottom is.
	**/
	public function reinTall():Float {
		final root = root();
		return root == null ? 8 : root.metrics.whole(8);
	}

	/**
		@return Whether the lanes are taller than the room for them.
	**/
	public function across():Bool {
		return span() * perTick > width - gutter() + 0.5;
	}

	/**
		@return How much room is left for the lanes once the strips are taken off.
	**/
	public function reined():Float {
		return across() ? reinTall() : 0;
	}

	override function layout():Void {
		framed();

		final top = y + head() + ruler();
		final room = height - head() - ruler() - reined();

		stack.holding = holding;
		stack.preset = showsPreset() ? presetOf() : -1;
		stack.rowTall = holding == null ? 0 : room;

		if (holding == null) stack.settles();

		stack.perTick = perTick;
		stack.offsetX = offsetX;
		stack.left = gutter();
		stack.playhead = playhead < 0 || showsPreset() ? -1 : playhead - start();

		stack.spreads(room);
		stack.offsetY = 0;

		final wants = stack.wants();

		if (wants > room) {
			if (offsetDown > wants - room) offsetDown = wants - room;
			if (offsetDown < 0) offsetDown = 0;

			stack.offsetY = offsetDown;
		} else offsetDown = 0;

		stack.arrange(x, top, width, room);
	}

	function offered(px:Float, py:Float, row:Int):Void {
		final root = root();
		if (root == null || holding != null) return;

		menu = new Menu();

		final offering = showsPreset() ? Parameter.moved(session.part) : Parameter.of(session.part);

		for (one in offering) {
			if (!one.operators) {
				choice(menu, one, one.target, 0, row);
				continue;
			}

			final slots = new Menu();
			for (which in 0...4) choice(slots, one, one.target, which, row);

			menu.offer(new Choice(one.name)).submenu = slots;
		}

		if (showsPreset() && row >= 0) timings(menu, row);

		root.pop(menu, px, py, this);
	}

	/**
		Offers what a preset's lane is measured in and whether it loops, on the lane's own menu.

		@param into The menu.
		@param row Which lane row.
	**/
	function timings(into:Menu, row:Int):Void {
		final line = stack.lineOf(row);
		final preset = presetOf();

		into.divide();

		final ms = into.offer(new Choice(translate(Locale.LANE_MILLISECONDS)));
		final beats = into.offer(new Choice(translate(Locale.LANE_BEATS)));

		if (line == null || line.points.length == 0) {
			ms.enabled = false;
			beats.enabled = false;
			ms.reason = translate(Locale.LANE_EMPTY);
			beats.reason = translate(Locale.LANE_EMPTY);
			return;
		}

		if (line.synced) beats.shortcut = "•";
		else ms.shortcut = "•";

		fires(line.synced ? ms : beats, function():Void {
			session.does(new mdd.song.edit.TimeLane(preset, line.target, line.slot, !line.synced,
				session.song.tempo.beatsAt(0)));
			relayout();
		});

		into.divide();

		final from = stack.chosen == null ? -1 : line.points.indexOf(stack.chosen);
		final loop = into.offer(new Choice(translate(Locale.LANE_LOOP)));
		final hold = into.offer(new Choice(translate(Locale.LANE_HOLD)));

		if (line.loop >= 0) loop.shortcut = "•";
		else hold.shortcut = "•";

		if (from < 0 || from >= line.points.length - 1) {
			loop.enabled = false;
			loop.reason = translate(Locale.LANE_LOOP_WHERE);
		} else {
			fires(loop, function():Void {
				session.does(new mdd.song.edit.LoopLane(preset, line.target, line.slot, from));
				relayout();
			});
		}

		if (line.loop < 0) hold.enabled = false;
		else fires(hold, function():Void {
			session.does(new mdd.song.edit.LoopLane(preset, line.target, line.slot, -1));
			relayout();
		});
	}

	function choice(into:Menu, one:Parameter, want:Int, which:Int, row:Int):Void {
		final many = stack.carries(want, which);

		final held = into.offer(new Choice(one.titled(which), many == 0 ? "" : "" + many));
		held.reason = translate(one.about);

		if (row < 0 && stack.shows(want, which)) {
			held.enabled = false;
			return;
		}

		fires(held, function():Void {
			if (row >= 0) {
				stack.swap(row, want, which);
				relayout();
				return;
			}

			shows(want, which);
		});
	}

	function shaped(row:Int, point:Point, px:Float, py:Float):Void {
		final root = root();
		if (root == null) return;

		menu = new Menu();

		final one = heldAt(row);

		for (shape in 0...Automation.SHAPES) {
			final choice = menu.offer(new Choice(translate(mdd.view.Shapes.NAMES[shape])));

			if (shape == point.shape) choice.enabled = false;
			else if (one != null && !one.smooth && Automation.moves(shape)) {
				choice.enabled = false;
				choice.reason = translate(one.target == Automation.INSTRUMENT ? Locale.PARAM_WHOLE
					: Locale.PARAM_PACKED);
			} else {
				fires(choice, function():Void {
					session.does(new mdd.song.edit.ShapePoint(point, shape, point.tension,
						point.steps));
					stack.invalidate();
				});
			}
		}

		if (Automation.stepped(point.shape)) {
			menu.divide();

			for (many in [2, 3, 4, 6, 8, 12, 16]) {
				final choice = menu.offer(new Choice("" + many));

				if (many == point.repeats()) choice.enabled = false;
				else fires(choice, function():Void {
					session.does(new mdd.song.edit.ShapePoint(point, point.shape,
						point.tension, many));
					stack.invalidate();
				});
			}
		}

		root.pop(menu, px, py, this);
	}

	/**
		@param tick A position in the piece, in ticks.
		@return Where it draws, across.
	**/
	public inline function atTick(tick:Int):Float {
		return x + gutter() - offsetX + tick * perTick;
	}

	/**
		@return The zoom at which the thing exactly fills the view.
	**/
	public function widest():Float {
		final reach = span();
		final room = width - gutter();

		if (reach < 1 || room <= 0) return 0.01;
		return room / reach;
	}

	/**
		Zooms in or out, keeping a point where it was.

		@param by What to multiply the zoom by.
		@param around The point to keep still, across.
	**/
	public function zoom(by:Float, around:Float):Void {
		final tick = Math.round((around - x - gutter() + offsetX) / perTick);
		final want = perTick * by;
		final least = widest();

		perTick = want < least ? least : (want > 4 ? 4 : want);
		scrollTo(tick * perTick - (around - x - gutter()));
	}

	/**
		How far the view is scrolled, down.
	**/
	public var offsetDown:Float = 0;

	/**
		Scrolls down, clamped to the lanes.

		@param py How far down.
	**/
	public function scrollDown(py:Float):Void {
		final most = stack.wants() - (height - head() - ruler() - reined());

		offsetDown = py < 0 ? 0 : (py > most ? (most < 0 ? 0 : most) : py);
		relayout();
	}

	/**
		How far in from the left edge the playhead lands when the view turns to keep it in sight,
		as a share of the view.
	**/
	static inline final LEAD = 0.02;

	/**
		Turns the view on a page to keep a position in sight: where it has reached the right edge or
		is left of the left one, the view scrolls to put it just in from the left edge. A position
		outside what is open moves nothing.

		@param tick A position in the song, in ticks.
	**/
	public function keeps(tick:Int):Void {
		if (showsPreset()) return;

		final local = tick - start();
		if (local < 0 || local > span()) return;

		final room = width - gutter();
		if (room <= 0 || perTick <= 0) return;

		final at = local * perTick - offsetX;
		if (at >= 0 && at < room) return;

		scrollTo(local * perTick - room * LEAD);
	}

	/**
		Scrolls across, clamped to the thing being edited.

		@param px How far across.
	**/
	public function scrollTo(px:Float):Void {
		final most = span() * perTick - (width - gutter());

		offsetX = px < 0 ? 0 : (px > most ? (most < 0 ? 0 : most) : px);
		relayout();
	}

	/**
		@param px A point, across.
		@return Which tick is there.
	**/
	public inline function tickAt(px:Float):Int {
		return Math.round((px - x - gutter() + offsetX) / perTick);
	}

	/**
		Moves the playhead to a point on the ruler.

		@param px A point, across.
	**/
	public function scrubbed(px:Float):Void {
		if (showsPreset()) return;

		final tick = session.snapped(tickAt(px));
		final want = tick < 0 ? 0 : tick;

		final at = start() + want;

		session.transport.seek(session.song.tempo.samplesAt(at));
		playhead = at;

		invalidate();
	}

	/**
		@return Where what is being edited starts in the song, in ticks: the open automation clip, or
			else the chosen pattern.
	**/
	function start():Int {
		return holding == null ? origin : holding.at;
	}

	function onRuler(px:Float, py:Float):Bool {
		return py >= y + head() && py < y + head() + ruler() && px >= x + gutter();
	}

	var scrubbing:Bool = false;
	var dragging:Bool = false;

	/**
		@param px A point, across.
		@param py A point, down.
		@return Whether the point is on the strip along the bottom.
	**/
	public function onRein(px:Float, py:Float):Bool {
		if (!across()) return false;

		final floor = y + height;
		return py >= floor - reinTall() && py < floor && px >= x + gutter();
	}

	function thumb(wide:Float, reach:Float):Float {
		final root = root();
		final least = root == null ? 24.0 : root.metrics.whole(24);
		final held = wide * wide / reach;

		return held < least ? least : held;
	}

	function drags(px:Float):Void {
		final wide = width - gutter();
		final reach = span() * perTick;

		final held = thumb(wide, reach);
		final room = wide - held;

		if (room <= 0) return;

		final want = (px - x - gutter() - held * 0.5) / room;
		scrollTo(want * (reach - wide));
	}

	function rein(paint:Paint, theme:Theme, metrics:Metrics):Void {
		if (!across()) return;

		final thick = reinTall();
		final wide = width - gutter();
		final reach = span() * perTick;

		final held = thumb(wide, reach);
		final room = wide - held;
		final most = reach - wide;
		final at = most <= 0 ? 0 : offsetX / most * room;

		final top = y + height - thick;

		paint.rect(x + gutter(), top, wide, thick, theme.sink, 0.7);
		paint.roundedRect(x + gutter() + at, top + metrics.whole(2), held,
			thick - metrics.whole(4), metrics.whole(2), theme.frame);
	}

	/**
		Says in the tooltip what the pointer is over: the ruler, or the corner above the lane
		names that adds a lane.

		@param px A point, across.
		@param py A point, down.
	**/
	function described(px:Float, py:Float):Void {
		detail = "";

		if (onRuler(px, py)) {
			tip = translate(Locale.EDITOR_RULER);
			detail = translate(Locale.EDITOR_RULER_DETAIL);
			return;
		}

		if (py < y + head() && holding == null) {
			if (px >= patternFrom && px < patternTo) {
				tip = translate(Locale.AUTOMATION_PATTERN_TIP);
				return;
			}

			if (px >= presetFrom && px < presetTo) {
				tip = translate(Locale.AUTOMATION_PRESET_TIP);
				return;
			}
		}

		tip = py < y + head() + ruler() && px < x + gutter() ? translate(Locale.LANE_ADD) : "";
	}

	override function took(event:Input):Bool {
		if (event.kind == Kind.PointerMove && !scrubbing && !dragging) described(event.x, event.y);

		if (event.kind == Kind.PointerMove && scrubbing) {
			scrubbed(event.x);
			return true;
		}

		if (event.kind == Kind.PointerUp && scrubbing) {
			scrubbing = false;
			return true;
		}

		if (event.kind == Kind.PointerDown && onRein(event.x, event.y)) {
			dragging = true;
			drags(event.x);
			return true;
		}

		if (event.kind == Kind.PointerMove && dragging) {
			drags(event.x);
			return true;
		}

		if (event.kind == Kind.PointerUp && dragging) {
			dragging = false;
			return true;
		}

		if (event.kind == Kind.PointerDown && onRuler(event.x, event.y)) {
			scrubbing = true;
			scrubbed(event.x);
			return true;
		}

		if (event.kind == Kind.Wheel) {
			if (event.ctrl() || event.alt()) {
				zoom(event.dy > 0 ? 1.25 : 0.8, event.x);
				return true;
			}

			if (event.shift()) {
				scrollTo(offsetX - event.dy * (width - gutter()) * 0.12);
				return true;
			}

			scrollDown(offsetDown - event.dy * stack.headTall() * 3);
			return true;
		}

		if (event.kind != Kind.PointerDown) return false;
		if (event.y >= y + head() + ruler()) return false;

		if (event.y < y + head() && holding == null) {
			if (event.x >= patternFrom && event.x < patternTo) {
				presents(false);
				return true;
			}

			if (event.x >= presetFrom && event.x < presetTo) {
				presents(true);
				return true;
			}
		}

		if (event.x >= x + gutter()) return false;

		offered(event.x, event.y, -1);
		return true;
	}

	override function paint(paint:Paint):Void {
		final root = root();
		if (root == null || root.metrics.body == null) return;

		final theme = root.theme;
		final metrics = root.metrics;

		paint.rect(x, y, width, height, theme.ground);

		heading(paint, theme, metrics);
		barred(paint, theme, metrics);

		super.paint(paint);
		rein(paint, theme, metrics);

		if (playhead >= 0 && !showsPreset()) {
			final at = atTick(playhead - start());

			if (at >= x + gutter() && at < x + width) {
				paint.rect(at, y + head(), metrics.whole(2), height - head(), theme.warn, 0.9);
			}
		}

	}

	function heading(paint:Paint, theme:Theme, metrics:Metrics):Void {
		final tall = head();
		final font = metrics.body;
		final small = metrics.small == null ? font : metrics.small;
		final one = held();
		final part = drivenPart();

		paint.rect(x, y, width, tall, theme.bar);
		paint.rect(x, y + tall - metrics.whole(1), width, metrics.whole(1), theme.frame, 0.7);

		paint.reface(font);

		final instrument = showsPreset() ? session.song.instrumentAt(presetOf()) : null;

		final said = holding != null
			? (one == null ? translate(Locale.LANE_EMPTY) : part.name() + "   "
				+ one.titled(holding.line == null ? 0 : holding.line.slot))
			: (showsPreset() ? part.name() + "   " + (instrument == null
				? translate(Locale.AUTOMATION_NO_PRESET) : instrument.name) : part.name());

		paint.text(said, x + metrics.inset, y + (tall - font.height) * 0.5 + font.ascent,
			theme.part(part.index()));

		if (holding == null && stack.rows() > 0) {
			paint.reface(small);

			paint.text(stack.rows() + " " + translate(stack.rows() == 1
				? Locale.LANE_ONE : Locale.LANE_MANY),
				x + metrics.inset + font.measure(said) + metrics.inset,
				y + (tall - small.height) * 0.5 + small.ascent, theme.dim, 0.7);

			paint.reface(font);
		}

		paint.reface(small);

		final line = y + (tall - small.height) * 0.5 + small.ascent;

		if (holding != null) {
			patternFrom = patternTo = presetFrom = presetTo = 0;

			paint.textRight(translate(Locale.AUTOMATION_CLIP), x + width - metrics.inset, line,
				theme.dim, 0.85);
			return;
		}

		final preset = translate(Locale.AUTOMATION_PRESET);
		final pattern = translate(Locale.AUTOMATION_PATTERN);

		presetTo = x + width - metrics.inset;
		presetFrom = presetTo - small.measure(preset);
		patternTo = presetFrom - metrics.inset * 2;
		patternFrom = patternTo - small.measure(pattern);

		switched(paint, theme, metrics, pattern, patternFrom, patternTo, !presetting, line, tall);
		switched(paint, theme, metrics, preset, presetFrom, presetTo, presetting, line, tall);
	}

	/**
		Draws one side of the switch between a pattern's lanes and a preset's, lit where it is the
		one shown.
	**/
	function switched(paint:Paint, theme:Theme, metrics:Metrics, said:String, from:Float, to:Float,
			on:Bool, line:Float, tall:Float):Void {
		if (on) {
			paint.roundedRect(from - metrics.unit, y + metrics.whole(3), to - from + metrics.unit * 2,
				tall - metrics.whole(6), metrics.radiusSmall, theme.accent, 0.25);
		}

		paint.text(said, from, line, on ? theme.ink : theme.dim, on ? 0.95 : 0.7);
	}

	function barred(paint:Paint, theme:Theme, metrics:Metrics):Void {
		final tall = ruler();
		final top = y + head();
		final left = x + gutter();
		final font = metrics.small == null ? metrics.body : metrics.small;

		paint.rect(x, top, width, tall, theme.bar);
		paint.pushClip(left, top, width - gutter(), tall);
		paint.reface(font);

		if (showsPreset()) {
			timed(paint, theme, metrics, top, tall, font);
			paint.popClip();
			return;
		}

		final bar = session.song.tempo.ppqn * 4;
		final reach = span();

		var tick = 0;
		var written = left - metrics.gap;

		while (tick <= reach) {
			final at = atTick(tick);

			if (at >= left && at < x + width) {
				paint.rect(at, top, metrics.whole(1), tall, theme.frame, 0.8);

				if (at >= written) {
					final said = "" + (Std.int((start() + tick) / bar) + 1);

					paint.text(said, at + metrics.unit,
						top + (tall - font.height) * 0.5 + font.ascent, theme.dim, 0.8);

					written = at + metrics.unit + paint.measure(said) + metrics.gap;
				}
			}

			tick += bar;
		}

		paint.popClip();
	}

	/**
		Draws the ruler over a preset's lanes: milliseconds from the key on, marked every tenth step
		of the lanes' grid and at least far enough apart to read.
	**/
	function timed(paint:Paint, theme:Theme, metrics:Metrics, top:Float, tall:Float,
			font:mdd.ui.Font):Void {
		final left = x + gutter();
		final step = stack.msGrid() * 10;
		final reach = span();

		var at = 0;
		var written = left - metrics.gap;

		while (at <= reach) {
			final px = atTick(at);

			if (px >= left && px < x + width) {
				paint.rect(px, top, metrics.whole(1), tall, theme.frame, 0.8);

				if (px >= written) {
					final said = at < 1000 ? at + " ms" : (at / 1000) + " s";

					paint.text(said, px + metrics.unit, top + (tall - font.height) * 0.5 + font.ascent,
						theme.dim, 0.8);

					written = px + metrics.unit + paint.measure(said) + metrics.gap;
				}
			}

			at += step;
		}
	}
}
