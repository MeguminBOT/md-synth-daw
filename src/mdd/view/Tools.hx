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

/**
	The tool buttons: select, draw, erase, slice, pan, and the snap, the notes on other channels
	and following the playhead, which are switches.

	Not every editor allows every tool, so `allowed` says which are offered and the
	rest are left out rather than drawn dead.
**/
final class Tools extends Widget {
	/**
		The snap button, which sits after the tools.
	**/
	public static inline final SNAP = Session.TOOLS;
	static inline final GHOSTS = Session.TOOLS + 1;

	/**
		The switch that keeps the playhead in sight while the song plays.
	**/
	public static inline final FOLLOW = Session.TOOLS + 2;

	/**
		The switch that holds the tracker to the chosen pattern rather than the whole piece.
	**/
	public static inline final LOCK = Session.TOOLS + 3;
	static inline final CELLS = Session.TOOLS + 4;

	/**
		Which chord reaches each tool, for the tooltips.
	**/
	public var bindings:Null<mdd.app.Bindings> = null;

	/**
		@param index Which button.
		@return The chord that reaches it, as text.
	**/
	function shortcutAt(index:Int):String {
		if (bindings == null) return "";
		if (index == FOLLOW) return bindings.shortcut(mdd.app.Bindings.FOLLOW);
		if (index < 0 || index > 4) return "";

		return bindings.shortcut(mdd.app.Bindings.SELECT + index);
	}

	public static final KEYS:Array<mdd.ui.Key> = [mdd.ui.Key.E, mdd.ui.Key.P, mdd.ui.Key.D,
		mdd.ui.Key.C, mdd.ui.Key.H];

	static final TIPS:Array<Locale> = [Locale.TOOL_SELECT, Locale.TOOL_DRAW, Locale.TOOL_ERASE,
		Locale.TOOL_SLICE, Locale.TOOL_PAN, Locale.TOOL_SNAP, Locale.TOOL_GHOSTS,
		Locale.TOOL_FOLLOW, Locale.TOOL_LOCK];

	/**
		The session to read.
	**/
	public final session:Session;

	var hoverAt:Int = -1;

	/**
		Builds the tool buttons.

		@param session The session to read.
	**/
	public function new(session:Session) {
		super();
		this.session = session;
	}

	/**
		@return How wide one button is.
	**/
	public function cell():Float {
		final root = root();
		if (root == null) return 24;

		final metrics = root.metrics;
		final tall = metrics.tab - metrics.whole(3) - metrics.unit * 2;

		return tall < 12 ? metrics.whole(24) : tall;
	}

	/**
		@return Where the buttons start, down.
	**/
	public function top():Float {
		final root = root();
		if (root == null) return y;

		return y + root.metrics.whole(3) + root.metrics.unit;
	}

	/**
		How much room the buttons have.
	**/
	public var room:Float = 0;

	/**
		Every tool and switch, as bits.
	**/
	public static inline final EVERY = (1 << (Session.TOOLS + 4)) - 1;

	/**
		Which tools this editor offers, as bits.
	**/
	public var allowed:Int = EVERY;

	final order:Array<Int> = [];

	/**
		@return Which buttons to draw, in order, leaving out the ones this editor does not offer.
	**/
	function orders():Array<Int> {
		order.resize(0);
		for (index in 0...CELLS) if (allowed & (1 << index) != 0) order.push(index);

		return order;
	}

	/**
		@return How many buttons are drawn.
	**/
	public function shown():Int {
		final many = orders().length;
		if (many == 0) return 0;

		final root = root();
		if (root == null || room <= 0) return many;

		final gap = root.metrics.unit;
		final step = cell() + gap;

		var fits = many;
		while (fits > 1 && step * fits - gap > room) fits--;

		return fits;
	}

	/**
		@param which A position in the drawn buttons.
		@return Which tool is there.
	**/
	public function toolAt(which:Int):Int {
		final held = orders();
		return which < 0 || which >= held.length ? -1 : held[which];
	}

	/**
		@return Where the buttons start, across.
	**/
	public function lead():Float {
		final root = root();
		return root == null ? 8.0 : root.metrics.inset * 0.5;
	}

	/**
		@return How wide the whole row is.
	**/
	public function wide():Float {
		final many = shown();
		if (many == 0) return 0;

		final root = root();
		final gap = root == null ? 4.0 : root.metrics.unit;

		return cell() * many + gap * (many - 1) + lead() * 2;
	}

	/**
		@param px A point, across.
		@param py A point, down.
		@return Which button is there, or -1.
	**/
	function cellAt(px:Float, py:Float):Int {
		final root = root();
		if (root == null) return -1;

		final size = cell();
		final top = top();

		if (py < top || py >= top + size) return -1;

		var pen = x + lead();

		for (which in 0...shown()) {
			if (px >= pen && px < pen + size) return toolAt(which);
			pen += size + root.metrics.unit;
		}

		return -1;
	}

	/**
		@param index Which button.
		@return Whether it is the tool in hand.
	**/
	function lit(index:Int):Bool {
		return switch (index) {
			case SNAP: session.snapping > 0;
			case GHOSTS: session.ghosts;
			case FOLLOW: session.following;
			case LOCK: session.lockedToPattern;
			case _: session.tool == index;
		}
	}

	/**
		Puts a tool in hand, or turns one of the switches over.

		@param index Which button.
	**/
	public function press(index:Int):Void {
		switch (index) {
			case SNAP:
				session.snapping = session.snapping > 0 ? 0 : mdd.app.Session.SIXTEENTH;
				session.changed();

			case GHOSTS:
				session.ghosts = !session.ghosts;
				session.changed();

			case FOLLOW:
				session.following = !session.following;
				session.say(translate(session.following ? Locale.SAID_FOLLOW_ON
					: Locale.SAID_FOLLOW_OFF));
				session.changed();

			case LOCK:
				session.lockedToPattern = !session.lockedToPattern;
				session.say(translate(session.lockedToPattern ? Locale.SAID_LOCK_ON
					: Locale.SAID_LOCK_OFF));
				session.changed();

			case _:
				session.uses(index);
		}

		invalidate();
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
				shortcut = shortcutAt(index);

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

		paint.rect(x, y, width, height, theme.sink);

		var pen = x + lead();

		for (which in 0...shown()) {
			final index = toolAt(which);
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

	/**
		Draws the mark on one button, which is a shape rather than an icon so it stays
		sharp at any density.

		@param paint What to draw with.
		@param theme The colours to draw in.
		@param metrics The sizes to draw at.
		@param index Which button.
		@param at Where it goes, across.
		@param top Where it goes, down.
		@param size How large to draw it.
		@param on Whether this is the tool in hand, which decides the colour.
	**/
	function glyph(paint:Paint, theme:Theme, metrics:Metrics, index:Int, at:Float, top:Float,
			size:Float, on:Bool):Void {
		final ink = on ? theme.ink : theme.dim;
		final middle = at + size * 0.5;
		final centre = top + size * 0.5;
		final reach = metrics.whole(5);
		final hair = metrics.whole(2);

		switch (index) {
			case Session.SELECT:
				final arrow = new haxe.ds.Vector<Float>(14);
				final left = middle - reach * 0.5;
				final head = centre - reach;

				arrow[0] = left;
				arrow[1] = head;
				arrow[2] = left;
				arrow[3] = head + reach * 1.62;
				arrow[4] = left + reach * 0.42;
				arrow[5] = head + reach * 1.22;
				arrow[6] = left + reach * 0.7;
				arrow[7] = head + reach * 1.86;
				arrow[8] = left + reach * 1.02;
				arrow[9] = head + reach * 1.74;
				arrow[10] = left + reach * 0.74;
				arrow[11] = head + reach * 1.12;
				arrow[12] = left + reach * 1.2;
				arrow[13] = head + reach * 1.06;

				paint.polygon(arrow, 7, ink);

			case Session.DRAW:
				paint.line(middle - reach * 0.8, centre + reach * 0.8,
					middle + reach * 0.55, centre - reach * 0.55, hair * 1.4, ink);

				final nib = new haxe.ds.Vector<Float>(6);

				nib[0] = middle - reach;
				nib[1] = centre + reach;
				nib[2] = middle - reach * 0.9;
				nib[3] = centre + reach * 0.35;
				nib[4] = middle - reach * 0.35;
				nib[5] = centre + reach * 0.9;

				paint.polygon(nib, 3, ink);

			case Session.ERASE:
				final block = new haxe.ds.Vector<Float>(8);

				block[0] = middle - reach * 0.2;
				block[1] = centre - reach * 0.9;
				block[2] = middle + reach;
				block[3] = centre + reach * 0.1;
				block[4] = middle + reach * 0.4;
				block[5] = centre + reach * 0.75;
				block[6] = middle - reach * 0.8;
				block[7] = centre - reach * 0.25;

				paint.polygon(block, 4, ink);

				paint.line(middle - reach, centre + reach * 0.85,
					middle + reach, centre + reach * 0.85, hair, ink, 0.7);

			case Session.SLICE:
				paint.line(middle - reach * 0.7, centre - reach,
					middle + reach * 0.5, centre + reach * 0.5, hair, ink);

				paint.line(middle + reach * 0.7, centre - reach,
					middle - reach * 0.5, centre + reach * 0.5, hair, ink);

				paint.circle(middle - reach * 0.6, centre + reach * 0.7, hair * 0.9, ink);
				paint.circle(middle + reach * 0.6, centre + reach * 0.7, hair * 0.9, ink);

			case Session.PAN:
				final palm = reach * 1.3;

				paint.roundedRect(middle - palm * 0.5, centre - reach * 0.2, palm,
					reach * 1.1, hair, ink);

				for (finger in 0...3) {
					final tall = reach * (finger == 1 ? 0.95 : 0.75);

					paint.roundedRect(middle - palm * 0.5 + finger * reach * 0.45,
						centre - reach * 0.2 - tall, reach * 0.34, tall + hair, hair * 0.6,
						ink);
				}

				paint.roundedRect(middle - palm * 0.5 - reach * 0.34,
					centre + reach * 0.1, reach * 0.4, reach * 0.55, hair * 0.6, ink);

			case SNAP:
				for (step in 0...3) {
					paint.rect(middle - reach + step * reach, centre - reach * 0.8, hair,
						reach * 1.6, ink, step == 1 ? 1 : 0.5);
				}

			case GHOSTS:
				paint.rect(middle - reach, centre - hair, reach * 1.2, hair * 2, ink, 0.4);
				paint.rect(middle - reach * 0.2, centre - hair, reach * 1.2, hair * 2, ink);

			case FOLLOW:
				paint.rect(middle - reach * 0.7, centre - reach, hair, reach * 2, ink);

				final arrow = new haxe.ds.Vector<Float>(6);

				arrow[0] = middle - reach * 0.1;
				arrow[1] = centre - reach * 0.7;
				arrow[2] = middle + reach;
				arrow[3] = centre;
				arrow[4] = middle - reach * 0.1;
				arrow[5] = centre + reach * 0.7;

				paint.polygon(arrow, 3, ink);

			case LOCK:
				paint.ring(middle, centre - reach * 0.3, reach * 0.6, hair, ink);
				paint.roundedRect(middle - reach * 0.85, centre - reach * 0.15, reach * 1.7,
					reach * 1.2, hair * 0.6, ink);

			case _:
		}
	}
}
