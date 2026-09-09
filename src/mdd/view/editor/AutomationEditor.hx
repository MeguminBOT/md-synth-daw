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
		Where the playhead is, or -1 for nowhere.
	**/
	public var playhead:Int = -1;

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

	var menu:Null<Menu> = null;

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
		@return How long the thing being edited is, in ticks.
	**/
	public function span():Int {
		if (holding != null) return holding.length;

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
		stack.rowTall = holding == null ? 0 : room;

		if (holding == null) stack.settles();

		stack.perTick = perTick;
		stack.offsetX = offsetX;
		stack.left = gutter();
		stack.playhead = playhead;

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

		for (one in Parameter.of(session.part)) {
			if (!one.operators) {
				choice(menu, one, one.target, 0, row);
				continue;
			}

			final slots = new Menu();
			for (which in 0...4) choice(slots, one, one.target, which, row);

			menu.offer(new Choice(one.name)).submenu = slots;
		}

		root.pop(menu, px, py, this);
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
				choice.reason = translate(Locale.PARAM_PACKED);
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
		final tick = session.snapped(tickAt(px));
		final want = tick < 0 ? 0 : tick;

		final at = holding == null ? want : holding.at + want;

		session.transport.seek(session.song.tempo.samplesAt(at));
		playhead = at;

		invalidate();
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

	override function took(event:Input):Bool {
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

		if (playhead >= 0) {
			final at = atTick(holding == null ? playhead : playhead - holding.at);

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

		final said = holding != null
			? (one == null ? translate(Locale.LANE_EMPTY) : part.name() + "   "
				+ one.titled(holding.line == null ? 0 : holding.line.slot))
			: part.name();

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

		paint.textRight(translate(holding == null ? Locale.AUTOMATION_PATTERN
			: Locale.AUTOMATION_CLIP), x + width - metrics.inset,
			y + (tall - small.height) * 0.5 + small.ascent, theme.dim, 0.85);

	}

	function barred(paint:Paint, theme:Theme, metrics:Metrics):Void {
		final tall = ruler();
		final top = y + head();
		final left = x + gutter();
		final font = metrics.small == null ? metrics.body : metrics.small;

		paint.rect(x, top, width, tall, theme.bar);
		paint.pushClip(left, top, width - gutter(), tall);
		paint.reface(font);

		final bar = session.song.tempo.ppqn * 4;
		final reach = span();

		var tick = 0;
		var written = left - metrics.gap;

		while (tick <= reach) {
			final at = atTick(tick);

			if (at >= left && at < x + width) {
				paint.rect(at, top, metrics.whole(1), tall, theme.frame, 0.8);

				if (at >= written) {
					final said = "" + (Std.int(tick / bar) + 1);

					paint.text(said, at + metrics.unit,
						top + (tall - font.height) * 0.5 + font.ascent, theme.dim, 0.8);

					written = at + metrics.unit + paint.measure(said) + metrics.gap;
				}
			}

			tick += bar;
		}

		paint.popClip();
	}
}
