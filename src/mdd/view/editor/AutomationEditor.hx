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
final class AutomationEditor extends Widget {
	public final session:Session;
	public final stack:Lanes;

	public var perTick:Float = 0.25;
	public var offsetX:Float = 0;
	public var playhead:Int = -1;

	public var holding:Null<Clip> = null;

	public var target:Int = Automation.LEVEL;
	public var slot:Int = 0;

	var menu:Null<Menu> = null;

	public function new(session:Session) {
		super();
		this.session = session;

		focusable = true;
		opaque = true;

		stack = new Lanes(session);
		stack.onOffer = function(from:Lanes, row:Int, px:Float, py:Float):Void
			offered(px, py);
		stack.onShape = function(from:Lanes, row:Int, point:Point, px:Float,
			py:Float):Void shaped(point, px, py);

		add(stack);
	}

	public function head():Float {
		final root = root();
		return root == null ? 26 : root.metrics.head;
	}

	public function ruler():Float {
		final root = root();
		return root == null ? 24 : root.metrics.ruler;
	}

	public function gutter():Float {
		final root = root();
		return root == null ? 110 : root.metrics.whole(110);
	}

	public function follows(clip:Null<Clip>):Void {
		holding = clip;

		framedSpan = -1;
		framed();
		relayout();
	}

	public function shows(target:Int, slot:Int):Void {
		holding = null;

		this.target = target;
		this.slot = slot;

		framedSpan = -1;
		framed();
		relayout();
	}

	public function span():Int {
		if (holding != null) return holding.length;

		final pattern = session.current();
		return pattern == null ? session.song.tempo.ppqn * 16 : pattern.length;
	}

	public function drivenPart():Part {
		return holding == null ? session.part : (holding.part:Part);
	}

	public function held():Null<Parameter> {
		if (holding == null) return Parameter.found(session.part, target, slot);

		final line = holding.line;
		return line == null ? null : Parameter.found(drivenPart(), line.target, line.slot);
	}

	var framedFor:Float = -1;
	var framedSpan:Int = -1;

	public function framed():Void {
		final room = width - gutter();
		final reach = span();

		if (room <= 0 || reach <= 0) return;
		if (room == framedFor && reach == framedSpan) return;

		framedFor = room;
		framedSpan = reach;

		perTick = room / reach;
		offsetX = 0;
	}

	override function layout():Void {
		framed();

		final top = y + head() + ruler();

		stack.perTick = perTick;
		stack.offsetX = offsetX;
		stack.left = gutter();
		stack.playhead = playhead;
		stack.holding = holding;
		stack.rowTall = height - head() - ruler();

		stack.targets.resize(0);
		if (holding == null) stack.targets.push((target << 8) | slot);

		stack.arrange(x, top, width, height - head() - ruler());
	}

	function offered(px:Float, py:Float):Void {
		final root = root();
		if (root == null || holding != null) return;

		menu = new Menu();

		for (one in Parameter.of(session.part)) {
			if (!one.operators) {
				choice(menu, one, one.target, 0);
				continue;
			}

			final slots = new Menu();
			for (which in 0...4) choice(slots, one, one.target, which);

			menu.offer(new Choice(one.name)).submenu = slots;
		}

		root.pop(menu, px, py, this);
	}

	function choice(into:Menu, one:Parameter, want:Int, which:Int):Void {
		final held = into.offer(new Choice(one.titled(which)));
		held.reason = translate(one.about);

		if (want == target && which == slot) {
			held.enabled = false;
			return;
		}

		fires(held, function():Void {
			shows(want, which);
			relayout();
		});
	}

	function shaped(point:Point, px:Float, py:Float):Void {
		final root = root();
		if (root == null) return;

		menu = new Menu();

		final one = held();

		for (shape in 0...Automation.SHAPES) {
			final choice = menu.offer(new Choice(translate(Locale.SHAPES[shape])));

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

	function fires(choice:Choice, what:Void -> Void):Void {
		choice.onFire = function(chosen:Choice):Void what();
	}

	public inline function atTick(tick:Int):Float {
		return x + gutter() - offsetX + tick * perTick;
	}

	override function took(event:Input):Bool {
		if (event.kind != Kind.PointerDown) return false;
		if (event.y >= y + head() + ruler()) return false;
		if (event.x >= x + gutter()) return false;

		offered(event.x, event.y);
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

		final said = one == null ? translate(Locale.LANE_EMPTY)
			: part.name() + "   " + one.titled(holding == null ? slot
				: (holding.line == null ? 0 : holding.line.slot));

		paint.text(said, x + metrics.inset, y + (tall - font.height) * 0.5 + font.ascent,
			theme.part(part.index()));

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
