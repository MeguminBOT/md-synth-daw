package mdd.ui.control;

import haxe.ds.Vector;

@:unreflective
final class Menu extends Widget {
	public static inline final CEILING = 9;
	public static inline final DWELL = 0.200;
	public static inline final RISE = 4.0;

	public final choices:Array<Choice> = [];

	public var onChoose:Null<Choice -> Void> = null;
	public var onClose:Null<Motion -> Void> = null;

	public var hoverAt(default, null):Int = -1;
	public var opened(default, null):Null<Menu> = null;
	public var closing(default, null):Bool = false;

	public var anchorX(default, null):Float = 0;
	public var anchorY(default, null):Float = 0;

	public final fade:Motion;
	public final rise:Motion;

	final arrow:Vector<Float> = new Vector<Float>(6);
	var dwelt:Float = 0;

	public function new() {
		super();
		opaque = true;
		focusable = true;
		fade = new Motion(this, 0, false);
		rise = new Motion(this, 0, true);
	}

	public function offer(choice:Choice):Choice {
		choices.push(choice);
		relayout();
		return choice;
	}

	public function divide():Void {
		offer(Choice.divider());
	}

	public function commands():Int {
		var count = 0;
		for (choice in choices) if (!choice.divides) count++;
		return count;
	}

	public inline function crowded():Bool {
		return commands() > CEILING;
	}

	public function anchor(px:Float, py:Float):Void {
		anchorX = px;
		anchorY = py;
	}

	public function arrive():Void {
		closing = false;
		fade.hold(0);
		rise.hold(0);
		hoverAt = -1;
		dwelt = 0;
	}

	public function leaving():Void {
		closing = true;
		shutSubmenu();
	}

	function rowHeight(metrics:Metrics, choice:Choice):Float {
		if (choice.divides) return metrics.whole(9);

		var tall = metrics.row;
		if (!choice.enabled && choice.reason != "") tall += metrics.whole(16);
		return tall;
	}

	public function topOf(index:Int):Float {
		final root = root();
		if (root == null) return 0;

		var top = root.metrics.unit;
		for (at in 0...index) top += rowHeight(root.metrics, choices[at]);
		return top;
	}

	public function rowAt(py:Float):Int {
		final root = root();
		if (root == null) return -1;

		final metrics = root.metrics;
		var top = y + metrics.unit;

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
			if (choice.chord != "") wide += metrics.whole(28) + font.measure(choice.chord);
			if (choice.opens()) wide += metrics.whole(18);
			if (!choice.enabled && choice.reason != "") {
				final reason = small.measure(choice.reason);
				if (reason > wide) wide = reason;
			}

			if (wide > widest) widest = wide;
		}

		wantWidth = widest + metrics.inset * 2;
		wantHeight = tall;
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

	public function expand(at:Int):Void {
		final root = root();
		if (root == null || at < 0 || at >= choices.length) return;

		final choice = choices[at];
		if (!choice.opens() || !choice.enabled || opened == choice.submenu) return;

		shutSubmenu();

		final sub = choice.submenu;
		opened = sub;
		root.pop(sub, x + width - root.metrics.unit, y + topOf(at));
	}

	function shutSubmenu():Void {
		if (opened == null) return;

		final root = root();
		if (root != null) root.shut(opened);
		opened = null;
	}

	function hoverOn(at:Int):Void {
		if (at == hoverAt) return;

		hoverAt = at;
		dwelt = 0;
		shutSubmenu();
		invalidate();
	}

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

	function steered(code:Key, root:Root):Bool {
		switch (code) {
			case Key.Up:
				hoverOn(near(hoverAt, -1));
				return true;

			case Key.Down:
				hoverOn(near(hoverAt, 1));
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

		paint.roundedRect(x, y, width, height, metrics.radiusWindow, theme.raise1, alpha);
		paint.outline(x, y, width, height, theme.frame, metrics.whole(1), alpha);

		var top = y + metrics.unit;

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

			if (choice.chord != "") {
				paint.textRight(choice.chord,
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

		paint.popTransform();
	}

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
