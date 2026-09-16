package mdd.ui;

@:unreflective

/**
	Everything on screen is one of these: a rectangle that measures itself, lays out
	what it holds, draws itself, and takes input.

	It knows nothing about the Mega Drive. A control that knows what a total level is
	belongs in `mdd.view`, and this package draws and handles input and does nothing
	else.
**/
class Widget {
	/**
		Where it sits, across.
	**/
	public var x(default, null):Float = 0;

	/**
		Where it sits, down.
	**/
	public var y(default, null):Float = 0;

	/**
		How wide it is.
	**/
	public var width(default, null):Float = 0;

	/**
		How tall it is.
	**/
	public var height(default, null):Float = 0;

	/**
		How wide it asked to be, filled in by `measure`.
	**/
	public var wantWidth(default, null):Float = 0;

	/**
		How tall it asked to be.
	**/
	public var wantHeight(default, null):Float = 0;

	/**
		What its tooltip says.
	**/
	public var tip:String = "";

	/**
		A second line for the tooltip.
	**/
	public var detail:String = "";

	/**
		The key the tooltip shows beside the label.
	**/
	public var shortcut:String = "";

	/**
		Whether it is drawn and hit at all.
	**/
	public var visible:Bool = true;

	/**
		Whether it can be used.
	**/
	public var enabled:Bool = true;

	/**
		Whether the keyboard can reach it.
	**/
	public var focusable:Bool = false;

	/**
		Whether it stops a hit rather than letting it through to what is behind.
	**/
	public var opaque:Bool = false;

	/**
		Whether nothing dismisses it: neither a press outside it nor escape. A
		progress bar is sealed, because there is nothing to go back to until the
		work it is reporting has finished.
	**/
	public var sealed:Bool = false;

	/**
		Whether a press outside it is ignored rather than closing it.

		A sheet carrying settings or a form is easy to lose by pressing a pixel
		beside it, and what is lost is whatever was half filled in. Escape and the
		sheet's own buttons still close it, which is what a reader reaches for.
	**/
	public var modal:Bool = false;

	/**
		Whether it wants a tick every frame even when nothing changed.
	**/
	public var drives:Bool = false;

	/**
		Whether it is taking typed text, so the keyboard should be on.
	**/
	public var typing:Bool = false;

	/**
		What holds it, or null where nothing does.
	**/
	public var parent(default, null):Null<Widget> = null;

	/**
		What it holds, in drawing order.
	**/
	public final children:Array<Widget> = [];

	var dirty(default, null):Bool = true;

	var owner:Null<Root> = null;

	/**
		Builds an empty widget at nought by nought.
	**/
	public function new() {}

	/**
		Puts a widget inside this one, taking it out of whatever held it before.

		@param child The widget to add.
		@return The same widget.
	**/
	public function add(child:Widget):Widget {
		if (child.parent != null) child.parent.remove(child);
		child.parent = this;
		child.attach(owner);
		children.push(child);
		invalidate();
		return child;
	}

	/**
		Takes a widget out.

		@param child The widget to remove.
	**/
	public function remove(child:Widget):Void {
		if (!children.remove(child)) return;
		child.parent = null;
		child.attach(null);
		invalidate();
	}

	/**
		Tells this widget and everything in it which root they belong to.

		@param root The root, or null when they are taken out of one.
	**/
	function attach(root:Null<Root>):Void {
		owner = root;
		for (child in children) child.attach(root);
	}

	/**
		Says this widget has just been taken out of the sheet layer, however that came
		about.

		`Root.lower` is reached from more than the button a sheet drew for it: Escape
		lowers anything not sealed, and raising something else lowers what was there. A
		sheet with something to record about being dismissed records it here, or it only
		happens on the one path it drew a button for.
	**/
	public function lowered():Void {}

	/**
		@return The root this belongs to, or null where it is not in one.
	**/
	public function root():Null<Root> {
		return owner;
	}

	/**
		Says the appearance changed, so the next frame draws it again.
	**/
	public function invalidate():Void {
		dirty = true;
		if (owner != null) owner.soil();
	}

	/**
		Says the size or the contents changed, so the next frame lays it out again.
	**/
	public function relayout():Void {
		if (owner != null) owner.reshape();
		invalidate();
	}

	/**
		Lays this widget out now rather than next frame, which a caller needs when it is
		about to measure what it just built.
	**/
	public function settle():Void {
		dirty = false;
		for (child in children) child.settle();
	}

	/**
		Works out how large this widget wants to be, into `wantWidth` and `wantHeight`.
		Override this.

		@param availableWidth How much room there is, across.
		@param availableHeight How much room there is, down.
	**/
	public function measure(availableWidth:Float, availableHeight:Float):Void {
		wantWidth = availableWidth;
		wantHeight = availableHeight;

		for (child in children) {
			if (child.visible) child.measure(availableWidth, availableHeight);
		}
	}

	/**
		Puts this widget where it is going and lays out what it holds.

		@param x Where it goes, across.
		@param y Where it goes, down.
		@param width How wide.
		@param height How tall.
	**/
	public function arrange(x:Float, y:Float, width:Float, height:Float):Void {
		final left = Math.round(x);
		final top = Math.round(y);
		final right = Math.round(x + (width < 0 ? 0 : width));
		final bottom = Math.round(y + (height < 0 ? 0 : height));

		this.x = left;
		this.y = top;
		this.width = right < left ? 0 : right - left;
		this.height = bottom < top ? 0 : bottom - top;

		layout();
	}

	/**
		Places the children inside this widget. Override this rather than `arrange`.
	**/
	function layout():Void {
		for (child in children) {
			if (child.visible) child.arrange(x, y, width, height);
		}
	}

	/**
		@param px A point, across.
		@param py A point, down.
		@return Whether it is inside this widget rectangle.
	**/
	public inline function holds(px:Float, py:Float):Bool {
		return px >= x && px < x + width && py >= y && py < y + height;
	}

	/**
		@param px A point, across.
		@param py A point, down.
		@return Whether this widget takes a hit there. Override for a shape that is not its
			rectangle.
	**/
	public function accepts(px:Float, py:Float):Bool {
		return visible && holds(px, py);
	}

	/**
		Finds what is under a point, deepest first.

		@param px A point, across.
		@param py A point, down.
		@return The widget there, or null where nothing takes it.
	**/
	public function hit(px:Float, py:Float):Null<Widget> {
		if (!accepts(px, py)) return null;

		var found:Null<Widget> = null;
		var i = children.length - 1;

		while (i >= 0) {
			final child = children[i];
			if (child.visible) {
				final deeper = child.hit(px, py);
				if (deeper != null) {
					found = deeper;
					break;
				}
			}
			i--;
		}

		return found != null ? found : this;
	}

	/**
		Draws this widget and everything in it. Override this.

		@param paint What to draw with.
	**/
	public function paint(paint:Paint):Void {
		for (child in children) {
			if (child.visible) child.paint(paint);
		}
	}

	/**
		Handles one event. Override this.

		@param event The event.
		@return Whether it was taken.
	**/
	public function took(event:Input):Bool {
		return false;
	}

	/**
		Handles one editing command, from a key or a menu.

		@param what One of the `Edit` values.
		@return Whether it was taken.
	**/
	public function edited(what:Int):Bool {
		return false;
	}

	/**
		Called once a frame while `drives` is set.

		@param seconds How long since the last call.
	**/
	public function tick(seconds:Float):Void {}

	/**
		Wires a menu entry to something to do. It takes a closure rather than a method
		reference, because a method reference on an `@:unreflective` class lowers to a
		dynamic wrapper the metadata removes, and the compiler names a method nobody
		wrote.

		@param choice The menu entry.
		@param what What to do when it is chosen.
	**/
	public function fires(choice:mdd.ui.control.Choice, what:Void -> Void):Void {
		choice.onFire = function(from:mdd.ui.control.Choice):Void {
			what();
			invalidate();
		};
	}

	/**
		@param key A string key.
		@return What it says in the language in force, or the key itself where this widget is not in
			a root.
	**/
	public function translate(key:Int):String {
		final held = root();
		return held == null ? "" : held.translate(key);
	}

	/**
		The same, with values put in the numbered places the string leaves for them.

		@param key Which string.
		@param values What goes in those places, in order.
		@return The line, or an empty string where there is no root to ask.
	**/
	public function filled(key:Int, values:Array<String>):String {
		final held = root();
		return held == null ? ""
			: mdd.ui.Translation.filled(held.translate(key), values);
	}

	/**
		Told when the keyboard arrives or leaves.

		@param on Whether it now has the keyboard.
	**/
	public function focused(on:Bool):Void {
		invalidate();
	}

	/**
		What the pointer should look like over a point inside this widget.

		The default is the ordinary arrow. A widget answers something else where it
		has an edge that resizes or a field that takes typing, because those are
		affordances with nothing else to show them.

		@param px A point, across.
		@param py A point, down.
		@return One of the cursor shapes `mdd.host.Sdl` names.
	**/
	public function cursorAt(px:Float, py:Float):Int {
		return mdd.host.Sdl.CURSOR_ARROW;
	}

	/**
		Told when the pointer arrives or leaves.

		@param on Whether the pointer is now over it.
	**/
	public function hovered(on:Bool):Void {
		invalidate();
	}

	/**
		Collects this widget and everything in it, in order.

		@param into Where they go.
	**/
	public function walk(into:Array<Widget>):Void {
		if (!visible) return;
		if (focusable && enabled) into.push(this);
		for (child in children) child.walk(into);
	}
}
