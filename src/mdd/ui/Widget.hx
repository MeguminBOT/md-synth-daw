package mdd.ui;

@:unreflective
class Widget {
	public var x(default, null):Float = 0;
	public var y(default, null):Float = 0;
	public var width(default, null):Float = 0;
	public var height(default, null):Float = 0;

	public var wantWidth(default, null):Float = 0;
	public var wantHeight(default, null):Float = 0;

	public var tip:String = "";
	public var detail:String = "";
	public var chord:String = "";

	public var visible:Bool = true;
	public var enabled:Bool = true;
	public var focusable:Bool = false;
	public var opaque:Bool = false;
	public var sealed:Bool = false;
	public var typing:Bool = false;

	public var parent(default, null):Null<Widget> = null;
	public final children:Array<Widget> = [];

	public var dirty(default, null):Bool = true;

	var owner:Null<Root> = null;

	public function new() {}

	public function add(child:Widget):Widget {
		if (child.parent != null) child.parent.remove(child);
		child.parent = this;
		child.attach(owner);
		children.push(child);
		invalidate();
		return child;
	}

	public function remove(child:Widget):Void {
		if (!children.remove(child)) return;
		child.parent = null;
		child.attach(null);
		invalidate();
	}

	function attach(root:Null<Root>):Void {
		owner = root;
		for (child in children) child.attach(root);
	}

	public function root():Null<Root> {
		return owner;
	}

	public function invalidate():Void {
		dirty = true;
		if (owner != null) owner.soil();
	}

	public function relayout():Void {
		if (owner != null) owner.reshape();
		invalidate();
	}

	public function settle():Void {
		dirty = false;
		for (child in children) child.settle();
	}

	public function measure(availableWidth:Float, availableHeight:Float):Void {
		wantWidth = availableWidth;
		wantHeight = availableHeight;

		for (child in children) {
			if (child.visible) child.measure(availableWidth, availableHeight);
		}
	}

	public function arrange(x:Float, y:Float, width:Float, height:Float):Void {
		this.x = x;
		this.y = y;
		this.width = width < 0 ? 0 : width;
		this.height = height < 0 ? 0 : height;

		layout();
	}

	function layout():Void {
		for (child in children) {
			if (child.visible) child.arrange(x, y, width, height);
		}
	}

	public inline function holds(px:Float, py:Float):Bool {
		return px >= x && px < x + width && py >= y && py < y + height;
	}

	public function accepts(px:Float, py:Float):Bool {
		return visible && holds(px, py);
	}

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

	public function paint(paint:Paint):Void {
		for (child in children) {
			if (child.visible) child.paint(paint);
		}
	}

	public function took(event:Input):Bool {
		return false;
	}

	public function tick(seconds:Float):Void {}

	public function translate(key:String):String {
		final held = root();
		return held == null ? key : held.translate(key);
	}

	public function focused(on:Bool):Void {
		invalidate();
	}

	public function hovered(on:Bool):Void {
		invalidate();
	}

	public function walk(into:Array<Widget>):Void {
		if (!visible) return;
		if (focusable && enabled) into.push(this);
		for (child in children) child.walk(into);
	}
}
