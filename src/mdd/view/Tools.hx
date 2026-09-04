package mdd.view;

import mdd.app.Locale;
import mdd.app.Session;
import mdd.ui.Input;
import mdd.ui.Kind;
import mdd.ui.Metrics;
import mdd.ui.Paint;
import mdd.ui.Theme;
import mdd.ui.Widget;

@:unreflective
final class Tools extends Widget {
	public static inline final SNAP = Session.TOOLS;
	public static inline final GHOSTS = Session.TOOLS + 1;
	public static inline final CELLS = Session.TOOLS + 2;

	static final TIPS:Array<String> = [Locale.TOOL_SELECT, Locale.TOOL_DRAW, Locale.TOOL_ERASE,
		Locale.TOOL_SLICE, Locale.TOOL_PAN, Locale.TOOL_SNAP, Locale.TOOL_GHOSTS];

	public final session:Session;

	var hoverAt:Int = -1;

	public function new(session:Session) {
		super();
		this.session = session;
	}

	public function cell():Float {
		final root = root();
		if (root == null) return 24;

		final metrics = root.metrics;
		final tall = metrics.tab - metrics.whole(3) - metrics.unit * 2;

		return tall < 12 ? metrics.whole(24) : tall;
	}

	public function top():Float {
		final root = root();
		if (root == null) return y;

		return y + root.metrics.whole(3) + root.metrics.unit;
	}

	public var room:Float = 0;

	public function shown():Int {
		final root = root();
		if (root == null) return CELLS;

		final gap = root.metrics.unit;
		final step = cell() + gap;

		if (room <= 0) return CELLS;

		var many = CELLS;
		while (many > 1 && step * many - gap > room) many--;

		return many;
	}

	public function lead():Float {
		final root = root();
		return root == null ? 8.0 : root.metrics.inset * 0.5;
	}

	public function wide():Float {
		final root = root();
		final gap = root == null ? 4.0 : root.metrics.unit;
		final many = shown();

		return cell() * many + gap * (many - 1) + lead() * 2;
	}

	public function cellAt(px:Float, py:Float):Int {
		final root = root();
		if (root == null) return -1;

		final size = cell();
		final top = top();

		if (py < top || py >= top + size) return -1;

		var pen = x + lead();

		for (index in 0...shown()) {
			if (px >= pen && px < pen + size) return index;
			pen += size + root.metrics.unit;
		}

		return -1;
	}

	function lit(index:Int):Bool {
		return switch (index) {
			case SNAP: session.snap > 0;
			case GHOSTS: session.ghosts;
			case _: session.tool == index;
		}
	}

	public function press(index:Int):Void {
		switch (index) {
			case SNAP:
				session.snap = session.snap > 0 ? 0 : Math.round(session.song.tempo.ppqn / 4);
				session.changed();

			case GHOSTS:
				session.ghosts = !session.ghosts;
				session.changed();

			case _:
				session.uses(index);
		}
	}

	override function took(event:Input):Bool {
		switch (event.kind) {
			case Kind.PointerDown:
				final index = cellAt(event.x, event.y);
				if (index < 0) return false;

				press(index);
				invalidate();
				return true;

			case Kind.PointerMove:
				final index = cellAt(event.x, event.y);
				tip = index < 0 ? "" : translate(TIPS[index]);

				if (index == hoverAt) return false;

				hoverAt = index;
				invalidate();
				return true;

			case _:
		}

		return false;
	}

	override function hovered(on:Bool):Void {
		if (!on) hoverAt = -1;
		super.hovered(on);
	}

	override function paint(paint:Paint):Void {
		final root = root();
		if (root == null || root.metrics.body == null) return;

		final theme = root.theme;
		final metrics = root.metrics;
		final size = cell();
		final top = top();

		var pen = x + lead();

		for (index in 0...shown()) {
			final on = lit(index);

			if (on) {
				paint.roundedGradient(pen, top, size, size, metrics.radiusRow,
					theme.accent.lift(0.20), theme.accent.sink(0.16), 0.95);
			} else {
				paint.roundedRect(pen, top, size, size, metrics.radiusRow, theme.raise1);
			}

			if (!on) {
				paint.outline(pen, top, size, size, theme.frame, metrics.whole(1), 1,
					metrics.radiusRow);
			}

			if (index == hoverAt) {
				paint.roundedRect(pen, top, size, size, metrics.radiusRow, theme.accent,
					Theme.HOVER);
			}

			glyph(paint, theme, metrics, index, pen, top, size, on);
			pen += size + metrics.unit;
		}
	}

	function glyph(paint:Paint, theme:Theme, metrics:Metrics, index:Int, at:Float, top:Float,
			size:Float, on:Bool):Void {
		final ink = on ? theme.ink : theme.dim;
		final middle = at + size * 0.5;
		final centre = top + size * 0.5;
		final reach = metrics.whole(5);
		final hair = metrics.whole(2);

		switch (index) {
			case Session.SELECT:
				paint.outline(middle - reach, centre - reach * 0.7, reach * 2, reach * 1.4,
					ink, hair);

			case Session.DRAW:
				paint.rect(middle - reach, centre - hair * 0.5, reach * 1.4, hair, ink);
				paint.rect(middle + reach * 0.4, centre - reach * 0.5, hair, reach, ink);

			case Session.ERASE:
				paint.rect(middle - reach, centre - hair * 0.5, reach * 2, hair, ink);

			case Session.SLICE:
				paint.rect(middle - hair * 0.5, centre - reach, hair, reach * 2, ink);
				paint.rect(middle - reach, centre - hair * 0.5, reach * 2, hair, ink, 0.35);

			case Session.PAN:
				paint.ring(middle, centre, reach * 0.8, hair, ink);

			case SNAP:
				for (step in 0...3) {
					paint.rect(middle - reach + step * reach, centre - reach * 0.8, hair,
						reach * 1.6, ink, step == 1 ? 1 : 0.5);
				}

			case GHOSTS:
				paint.rect(middle - reach, centre - hair, reach * 1.2, hair * 2, ink, 0.4);
				paint.rect(middle - reach * 0.2, centre - hair, reach * 1.2, hair * 2, ink);

			case _:
		}
	}
}
