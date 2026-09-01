package mdd.ui;

@:unreflective
final class Toggle extends Widget {
	public var label:String;
	public var on(default, null):Bool = false;
	public var onChange:Null<Toggle -> Void> = null;

	public function new(label:String, on:Bool = false) {
		super();
		this.label = label;
		this.on = on;
		focusable = true;
		opaque = true;
	}

	public function set(next:Bool):Void {
		if (next == on) return;
		on = next;
		invalidate();
		if (onChange != null) onChange(this);
	}

	override function took(event:Input):Bool {
		switch (event.kind) {
			case Kind.PointerDown:
				if (event.button != Pointer.Left) return false;
				set(!on);
				return true;

			case Kind.KeyDown:
				if (!event.plain()) return false;
				if (event.code != Key.Space && event.code != Key.Return) return false;
				set(!on);
				return true;

			case _:
		}
		return false;
	}

	override function paint(paint:Paint):Void {
		final root = root();
		if (root == null || root.metrics.body == null) return;

		final theme = root.theme;
		final metrics = root.metrics;
		final font = metrics.body;
		final box = metrics.whole(14);
		final top = y + (height - box) * 0.5;

		paint.roundedRect(x, top, box, box, metrics.radiusSmall, on ? theme.accent : theme.sink);
		paint.outline(x, top, box, box, root.focus == this ? theme.accent : theme.frame,
			metrics.whole(1));

		if (on) {
			final inset = metrics.whole(4);
			paint.roundedRect(x + inset, top + inset, box - inset * 2, box - inset * 2,
				metrics.whole(2), theme.ink);
		}

		paint.reface(font);
		paint.text(label, x + box + metrics.unit * 2, y + (height - font.height) * 0.5 + font.ascent,
			on ? theme.ink : theme.dim);
	}
}
