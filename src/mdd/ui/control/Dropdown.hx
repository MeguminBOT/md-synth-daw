package mdd.ui.control;

import haxe.ds.Vector;

@:unreflective

/**
	One of a short list: it shows the entry chosen and opens the whole list as a menu.

	It is drawn as a `Number` is, so the two sit in one row and read as one. It holds which entry
	is chosen rather than the entries, and `named` says what each one is called when it is shown,
	which lets an entry that is a word follow the language.
**/
final class Dropdown extends Widget implements Range {
	/**
		What it is called, drawn small before the entry. It may be empty.
	**/
	public var label:String;

	/**
		Which entry is chosen, from nought.
	**/
	public var value(get, never):Int;

	/**
		How many entries there are.
	**/
	public var count(default, null):Int;

	/**
		Called when a different entry is chosen.
	**/
	public var onChange:Null<Dropdown -> Void> = null;

	/**
		What an entry says. Without it an entry shows its index.
	**/
	public var named:Null<Int -> String> = null;

	var carried:Int = 0;
	var list:Null<Menu> = null;
	final arrow:Vector<Float> = new Vector<Float>(6);

	var spokenValue:Int = -1;
	var spokenCount:Int = 0;
	var spokenLanguage:String = "";
	var spoken:String = "";

	/**
		Builds a dropdown.

		@param label What it is called.
		@param value Which entry it starts on.
		@param count How many entries there are, at least one.
	**/
	public function new(label:String, value:Int, count:Int) {
		super();
		this.label = label;
		this.count = count < 1 ? 1 : count;
		focusable = true;
		opaque = true;
		set(value);
	}

	/**
		Changes how many entries there are, moving the chosen one onto the last where it no longer
		fits, and telling `onChange` where that moved it.

		@param count How many entries there are now, at least one.
	**/
	public function counts(count:Int):Void {
		final held = count < 1 ? 1 : count;
		if (held == this.count) return;

		this.count = held;
		invalidate();

		if (carried >= held) set(held - 1);
	}

	/**
		@return How far it can move.
	**/
	public function span():Int {
		return count - 1;
	}

	/**
		@return How far down the list the chosen entry is, 0 to 1.
	**/
	public function share():Float {
		return count <= 1 ? 0 : carried / (count - 1);
	}

	function get_value():Int {
		return carried;
	}

	/**
		Chooses an entry, clamped to the list, telling `onChange` only where it actually moved.

		@param next Which entry to choose.
	**/
	public function set(next:Int):Void {
		var held = next;
		if (held < 0) held = 0;
		if (held >= count) held = count - 1;

		if (held == carried) return;
		carried = held;
		invalidate();
		if (onChange != null) onChange(this);
	}

	/**
		@param index An entry.
		@return What it says.
	**/
	public function entry(index:Int):String {
		return named != null ? named(index) : Std.string(index);
	}

	/**
		@return What the chosen entry says, asked of `named` again only when the entry, the length
			of the list or the language has changed since, so a dropdown sitting still draws
			without allocating.
	**/
	public function shown():String {
		final root = root();
		final language = root == null ? "" : root.translation.language;

		if (carried != spokenValue || count != spokenCount || language != spokenLanguage) {
			spoken = entry(carried);
			spokenValue = carried;
			spokenCount = count;
			spokenLanguage = language;
		}

		return spoken;
	}

	/**
		Asks `named` again for what the chosen entry says, which an owner whose names follow
		something other than the entry and the language calls when that changes.
	**/
	public function renamed():Void {
		spokenValue = -1;
		invalidate();
	}

	/**
		@return Whether its list is open.
	**/
	public function open():Bool {
		return list != null && !list.closing;
	}

	/**
		Opens the list under it, with the chosen entry ticked.
	**/
	public function opens():Void {
		final root = root();
		if (root == null) return;

		final menu = new Menu();
		menu.ticking = true;

		for (index in 0...count) {
			final which = index;
			final choice = menu.offer(new Choice(entry(which)));

			choice.ticked = which == carried;
			fires(choice, function():Void set(which));
		}

		list = menu;
		root.pop(menu, x, y + height, this);
	}

	override function took(event:Input):Bool {
		switch (event.kind) {
			case Kind.PointerDown:
				if (event.button != Pointer.Left) return false;

				opens();
				return true;

			case Kind.Wheel:
				set(carried - Std.int(event.dy));
				return true;

			case Kind.KeyDown:
				return keyed(event);

			case _:
		}
		return false;
	}

	/**
		Opens the list on enter or space, and moves through it with the arrow keys without opening
		it.

		@param event The event.
		@return Whether it was taken.
	**/
	function keyed(event:Input):Bool {
		switch (event.code) {
			case Key.Return, Key.Space:
				opens();
				return true;

			case Key.Up:
				set(carried - 1);
				return true;

			case Key.Down:
				set(carried + 1);
				return true;

			case _:
		}
		return false;
	}

	/**
		@return How wide it needs to be for the widest entry it could show, so choosing another
			never moves what sits beside it.
	**/
	public function fits():Float {
		final root = root();
		if (root == null) return 70;

		final metrics = root.metrics;
		final mono = metrics.mono;
		final small = metrics.small;

		if (mono == null || small == null) return 70;

		var widest = 0.0;
		for (index in 0...count) {
			final wide = mono.measure(entry(index));
			if (wide > widest) widest = wide;
		}

		final wide = small.measure(label) + widest + metrics.whole(8) + metrics.unit * 5
			+ metrics.inset;
		final least = metrics.whole(70);

		return wide < least ? least : wide;
	}

	/**
		Wants the width `fits` gives and whatever height it is offered.

		@param availableWidth How much room there is, across.
		@param availableHeight How much room there is, down.
	**/
	override function measure(availableWidth:Float, availableHeight:Float):Void {
		wantWidth = fits();
		wantHeight = availableHeight;
	}

	override function paint(paint:Paint):Void {
		final root = root();
		if (root == null) return;

		final theme = root.theme;
		final metrics = root.metrics;
		final mono = metrics.mono;
		final small = metrics.small;
		if (mono == null || small == null) return;

		final lit = open();

		paint.roundedRect(x, y, width, height, metrics.radiusRow, theme.sink);

		if (root.over == this || lit) {
			paint.roundedRect(x, y, width, height, metrics.radiusRow, theme.accent, Theme.HOVER);
		}

		paint.outline(x, y, width, height, root.focus == this || lit ? theme.accent : theme.frame,
			metrics.whole(1), 1, metrics.radiusRow);

		final size = metrics.whole(4);
		final middle = x + width - metrics.unit * 2 - size;
		final centre = y + height * 0.5;

		paint.reface(small);
		paint.text(label, x + metrics.unit * 2, y + (height - small.height) * 0.5 + small.ascent,
			theme.dim, 0.7);

		paint.reface(mono);
		paint.textRight(shown(), middle - size - metrics.unit,
			y + (height - mono.height) * 0.5 + mono.ascent, theme.ink, 0.85);

		arrow[0] = middle - size;
		arrow[1] = centre - size * 0.5;
		arrow[2] = middle + size;
		arrow[3] = centre - size * 0.5;
		arrow[4] = middle;
		arrow[5] = centre + size * 0.6;

		paint.polygon(arrow, 3, theme.dim);
	}
}
