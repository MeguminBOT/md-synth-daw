package mdd.ui.control;

import haxe.ds.Vector;

@:unreflective

/**
	A menu: a list of entries, some of which open menus of their own.

	It is a widget rather than a system menu, so it draws in the theme and carries a
	shortcut and a reason on every entry. The root owns the stack of open menus; this
	owns only whichever one it opened itself.
**/
final class Menu extends Widget {
	/**
		How many entries fit before the menu is called crowded and drawn in two columns.
	**/
	public static inline final CEILING = 9;
	static inline final DWELL = 0.200;
	static inline final RISE = 4.0;

	/**
		The entries, in order.
	**/
	public final choices:Array<Choice> = [];

	/**
		Called when an entry is chosen, before its own handler.
	**/
	public var onChoose:Null<Choice -> Void> = null;

	/**
		Called once the closing fade has finished.
	**/
	public var onClose:Null<Motion -> Void> = null;

	/**
		Which entry the pointer is over, or -1.
	**/
	public var hoverAt(default, null):Int = -1;

	/**
		The menu this one opened, where it has one open.
	**/
	public var opened(default, null):Null<Menu> = null;

	/**
		Whether it is fading out. It still draws while it is.
	**/
	public var closing(default, null):Bool = false;

	/**
		Where it was asked to open, across.
	**/
	public var anchorX(default, null):Float = 0;

	/**
		Where it was asked to open, down.
	**/
	public var anchorY(default, null):Float = 0;

	/**
		How far it has faded in.
	**/
	public final fade:Motion;

	/**
		How far it has risen into place.
	**/
	public final rise:Motion;

	final arrow:Vector<Float> = new Vector<Float>(6);
	var dwelt:Float = 0;

	/**
		Builds an empty menu.
	**/
	public function new() {
		super();
		opaque = true;
		focusable = true;
		fade = new Motion(this, 0, false);
		rise = new Motion(this, 0, true);
	}

	/**
		Adds an entry.

		@param choice The entry.
		@return The same entry.
	**/
	public function offer(choice:Choice):Choice {
		choices.push(choice);
		relayout();
		return choice;
	}

	/**
		Adds a line between groups.
	**/
	public function divide():Void {
		offer(Choice.divider());
	}

	/**
		@return How many entries can actually be chosen, dividers left out.
	**/
	public function commands():Int {
		var count = 0;
		for (choice in choices) if (!choice.divides) count++;
		return count;
	}

	/**
		@return Whether there are more entries than fit in one column.
	**/
	public inline function crowded():Bool {
		return commands() > CEILING;
	}

	/**
		Records where it was asked to open, which is not always where it fits.

		@param px Where, across.
		@param py Where, down.
	**/
	public function anchor(px:Float, py:Float):Void {
		anchorX = px;
		anchorY = py;
	}

	/**
		Starts the fade and the rise.
	**/
	public function arrive():Void {
		closing = false;
		fade.hold(0);
		rise.hold(0);
		hoverAt = -1;
		dwelt = 0;
	}

	/**
		Starts fading out. It keeps drawing until the fade finishes, and `onClose` is called
		then.
	**/
	public function leaving():Void {
		closing = true;
		shutSubmenu();
	}

	/**
		How much room is left above and below a menu long enough to scroll, so it
		does not sit flush against the top and bottom of the window.
	**/
	static inline final MARGIN = 8;

	/**
		How far down the entries are scrolled, in pixels.
	**/
	var offset:Float = 0;

	/**
		How far they can be scrolled, which is nought where they all fit. A menu of
		every icon is longer than a window is tall, and one that cannot scroll simply
		runs off the bottom with no way to reach what is down there.
	**/
	var most:Float = 0;

	/**
		@param metrics The sizes to draw at.
		@param choice An entry.
		@return How tall it draws, which is less for a divider.
	**/
	function rowHeight(metrics:Metrics, choice:Choice):Float {
		if (choice.divides) return metrics.whole(9);

		var tall = metrics.row;
		if (!choice.enabled && choice.reason != "") tall += metrics.whole(16);
		return tall;
	}

	/**
		@param index An entry.
		@return Where it sits, down.
	**/
	public function topOf(index:Int):Float {
		final root = root();
		if (root == null) return 0;

		return raised(index) - offset;
	}

	/**
		@param index An entry.
		@return Where it sits before the menu is scrolled.
	**/
	function raised(index:Int):Float {
		final root = root();
		if (root == null) return 0;

		var top = root.metrics.unit;
		for (at in 0...index) top += rowHeight(root.metrics, choices[at]);

		return top;
	}

	/**
		@param py A point, down.
		@return Which entry is there, or -1.
	**/
	public function rowAt(py:Float):Int {
		final root = root();
		if (root == null) return -1;

		final metrics = root.metrics;
		if (py < y || py >= y + height) return -1;

		var top = y + metrics.unit - offset;

		for (at in 0...choices.length) {
			final tall = rowHeight(metrics, choices[at]);
			if (py >= top && py < top + tall) return at;
			top += tall;
		}
		return -1;
	}

	override function measure(availableWidth:Float, availableHeight:Float):Void {
		final root = root();

		if (root == null || root.metrics.body == null) {
			wantWidth = 0;
			wantHeight = 0;
			return;
		}

		final metrics = root.metrics;
		final font = metrics.body;
		final small = metrics.small == null ? font : metrics.small;

		var widest = metrics.whole(120);
		var tall = metrics.unit * 2;

		for (choice in choices) {
			tall += rowHeight(metrics, choice);
			if (choice.divides) continue;

			var wide = font.measure(choice.label);
			if (choice.shortcut != "") wide += metrics.whole(28) + font.measure(choice.shortcut);
			if (choice.opens()) wide += metrics.whole(18);
			if (!choice.enabled && choice.reason != "") {
				final reason = small.measure(choice.reason);
				if (reason > wide) wide = reason;
			}

			if (wide > widest) widest = wide;
		}

		wantWidth = widest + metrics.inset * 2;

		final room = availableHeight - metrics.whole(MARGIN) * 2;

		if (room > 0 && tall > room) {
			wantHeight = room;
			most = tall - room;
		} else {
			wantHeight = tall;
			most = 0;
		}

		if (offset > most) offset = most;
		if (offset < 0) offset = 0;
	}

	override function accepts(px:Float, py:Float):Bool {
		return visible && !closing && holds(px, py);
	}

	override function tick(seconds:Float):Void {
		if (hoverAt < 0 || opened != null) return;

		final choice = choices[hoverAt];
		if (!choice.opens() || !choice.enabled) return;

		dwelt += seconds;
		if (dwelt >= DWELL) expand(hoverAt);
	}

	/**
		Opens the menu an entry carries, beside it.

		@param at Which entry.
	**/
	function expand(at:Int):Void {
		final root = root();
		if (root == null || at < 0 || at >= choices.length) return;

		final choice = choices[at];
		if (!choice.opens() || !choice.enabled || opened == choice.submenu) return;

		shutSubmenu();

		final sub = choice.submenu;
		opened = sub;
		root.pop(sub, x + width - root.metrics.unit, y + topOf(at));
	}

	/**
		Closes whichever menu this one opened.
	**/
	function shutSubmenu():Void {
		if (opened == null) return;

		final root = root();
		if (root != null) root.shut(opened);
		opened = null;
	}

	/**
		Moves the hover, opening or closing a nested menu as it goes.

		@param at Which entry, or -1 for none.
	**/
	function hoverOn(at:Int):Void {
		if (at == hoverAt) return;

		hoverAt = at;
		dwelt = 0;
		shutSubmenu();
		invalidate();
	}

	/**
		Chooses an entry: tells `onChoose`, then the entry's own handler, then closes the
		whole stack.

		@param at Which entry.
	**/
	public function fire(at:Int):Void {
		if (at < 0 || at >= choices.length) return;

		final choice = choices[at];
		if (!choice.pickable()) return;

		if (choice.opens()) {
			expand(at);
			return;
		}

		final root = root();
		if (onChoose != null) onChoose(choice);
		if (choice.onFire != null) choice.onFire(choice);
		if (root != null) root.dismiss();
	}

	override function took(event:Input):Bool {
		final root = root();
		if (root == null) return false;

		switch (event.kind) {
			case Kind.Wheel:
				return scrolled(event.dy * root.metrics.row);

			case Kind.PointerMove:
				hoverOn(rowAt(event.y));
				return true;

			case Kind.PointerDown:
				final at = rowAt(event.y);
				hoverOn(at);
				if (event.button == Pointer.Left) fire(at);
				return true;

			case Kind.PointerUp:
				return true;

			case Kind.KeyDown:
				return steered(event.code, root);

			case _:
		}
		return false;
	}

	/**
		Scrolls the entries.

		@param by How far to move them, in pixels. A positive number shows what is above.
		@return Whether there was anywhere to scroll to.
	**/
	function scrolled(by:Float):Bool {
		if (most <= 0) return false;

		final was = offset;
		offset -= by;

		if (offset < 0) offset = 0;
		if (offset > most) offset = most;

		if (offset == was) return true;

		invalidate();
		return true;
	}

	/**
		Brings an entry into view, which is what the arrow keys need once a menu is
		longer than the room it has.

		@param index Which entry.
	**/
	function shows(index:Int):Void {
		if (most <= 0 || index < 0 || index >= choices.length) return;

		final root = root();
		if (root == null) return;

		final metrics = root.metrics;
		final top = raised(index);
		final tall = rowHeight(metrics, choices[index]);

		if (top - offset < metrics.unit) offset = top - metrics.unit;
		if (top + tall - offset > height) offset = top + tall - height;

		if (offset < 0) offset = 0;
		if (offset > most) offset = most;

		invalidate();
	}

	/**
		Moves the hover with the arrow keys, opens a nested menu with right, closes with
		left, and chooses with enter.

		@param code Which key.
		@param root The root the menu is open in.
		@return Whether it was taken.
	**/
	function steered(code:Key, root:Root):Bool {
		switch (code) {
			case Key.Up:
				hoverOn(near(hoverAt, -1));
				shows(hoverAt);
				return true;

			case Key.Down:
				hoverOn(near(hoverAt, 1));
				shows(hoverAt);
				return true;

			case Key.Return, Key.Space:
				fire(hoverAt);
				return true;

			case Key.Right:
				if (hoverAt >= 0 && choices[hoverAt].opens()) {
					expand(hoverAt);
					if (opened != null) root.focusOn(opened);
					return true;
				}
				return false;

			case Key.Left, Key.Escape:
				root.shut(this);
				return true;

			case _:
		}
		return false;
	}

	/**
		@param from Where to start.
		@param by One forwards, minus one backwards.
		@return The next entry that can be chosen, skipping dividers and disabled ones.
	**/
	function near(from:Int, by:Int):Int {
		if (choices.length == 0) return -1;

		var at = from;
		for (step in 0...choices.length) {
			at += by;
			if (at < 0) at = choices.length - 1;
			if (at >= choices.length) at = 0;
			if (choices[at].pickable()) return at;
		}
		return from;
	}

	override function paint(paint:Paint):Void {
		final root = root();
		if (root == null || root.metrics.body == null) return;

		final theme = root.theme;
		final metrics = root.metrics;
		final font = metrics.body;
		final small = metrics.small == null ? font : metrics.small;
		final alpha = fade.value;

		if (alpha <= 0.004) return;

		final lift = (1 - rise.value) * metrics.sizeOf(RISE);
		paint.pushTransform(0, lift);

		final lift = metrics.whole(3);

		paint.roundedRect(x + lift, y + lift, width, height, metrics.radiusWindow, theme.sink,
			alpha * 0.45);
		paint.roundedRect(x, y, width, height, metrics.radiusWindow, theme.raise1, alpha);
		paint.outline(x, y, width, height, theme.raise2, metrics.whole(1), alpha,
			metrics.radiusWindow);

		paint.pushClip(x, y, width, height);

		var top = y + metrics.unit - offset;

		for (at in 0...choices.length) {
			final choice = choices[at];
			final tall = rowHeight(metrics, choice);

			if (choice.divides) {
				paint.rect(x + metrics.gap, top + tall * 0.5, width - metrics.gap * 2,
					metrics.whole(1), theme.frame, alpha);
				top += tall;
				continue;
			}

			if (at == hoverAt && choice.enabled) {
				paint.roundedRect(x + metrics.unit, top, width - metrics.unit * 2, metrics.row,
					metrics.radiusSmall, theme.accent, Theme.SELECT * alpha);
			}

			paint.reface(font);

			final ink = choice.enabled ? theme.ink : theme.dim;
			final line = top + (metrics.row - font.height) * 0.5 + font.ascent;
			final shade = choice.enabled ? alpha : alpha * 0.55;

			paint.text(choice.label, x + metrics.inset, line, ink, shade);

			if (choice.shortcut != "") {
				paint.textRight(choice.shortcut,
					x + width - metrics.inset - (choice.opens() ? metrics.whole(14) : 0), line,
					theme.dim, shade);
			}

			if (choice.opens()) chevron(paint, theme, metrics, top, alpha);

			if (!choice.enabled && choice.reason != "") {
				paint.reface(small);
				paint.text(choice.reason, x + metrics.inset,
					top + metrics.row + small.ascent, theme.dim, alpha * 0.55);
			}

			top += tall;
		}

		paint.popClip();
		paint.popTransform();
	}

	/**
		Draws the triangle that says an entry opens a menu of its own.

		@param paint What to draw with.
		@param theme The colours to draw in.
		@param metrics The sizes to draw at.
		@param top Where the entry sits, down.
		@param alpha How opaque to draw it.
	**/
	function chevron(paint:Paint, theme:Theme, metrics:Metrics, top:Float, alpha:Float):Void {
		final size = metrics.whole(4);
		final cx = x + width - metrics.inset - size;
		final cy = top + metrics.row * 0.5;

		arrow[0] = cx - size * 0.5;
		arrow[1] = cy - size;
		arrow[2] = cx + size * 0.7;
		arrow[3] = cy;
		arrow[4] = cx - size * 0.5;
		arrow[5] = cy + size;

		paint.polygon(arrow, 3, theme.dim, alpha);
	}
}
