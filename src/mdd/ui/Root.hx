package mdd.ui;

@:unreflective
final class Root {
	public var top(default, null):Widget;
	public var metrics(default, null):Metrics;
	public var theme(default, null):Theme;

	public var focus(default, null):Null<Widget> = null;
	public var capture(default, null):Null<Widget> = null;
	public var over(default, null):Null<Widget> = null;

	public var pointerX(default, null):Float = 0;
	public var pointerY(default, null):Float = 0;
	public var mods(default, null):Mod = Mod.None;

	public var width(default, null):Float = 0;
	public var height(default, null):Float = 0;

	public var painted(default, null):Int = 0;

	var soiled:Bool = true;
	var reshaped:Bool = true;

	final event:Input = new Input();
	final order:Array<Widget> = [];

	public function new(top:Widget, metrics:Metrics, theme:Theme) {
		this.top = top;
		this.metrics = metrics;
		this.theme = theme;
		@:privateAccess top.attach(this);
	}

	public function soil():Void {
		soiled = true;
	}

	public function reshape():Void {
		reshaped = true;
		soiled = true;
	}

	public inline function stale():Bool {
		return soiled;
	}

	public function resize(width:Float, height:Float):Void {
		if (this.width == width && this.height == height) return;
		this.width = width;
		this.height = height;
		reshape();
	}

	public function rescale(scale:Float):Void {
		if (metrics.scale == scale) return;
		metrics.wear(scale);
		reshape();
	}

	public function frame(paint:Paint):Bool {
		if (!soiled) return false;

		if (reshaped) {
			top.measure(width, height);
			top.arrange(0, 0, width, height);
			reshaped = false;
		}

		paint.reset();
		top.paint(paint);
		paint.flush();

		top.settle();
		soiled = false;
		painted++;
		return true;
	}

	public function moved(x:Float, y:Float, mods:Mod):Void {
		pointerX = x;
		pointerY = y;
		this.mods = mods;

		if (capture != null) {
			event.pointer(Kind.PointerMove, x, y, Pointer.Left, mods);
			send(capture, event);
			return;
		}

		hover(top.hit(x, y));

		if (over != null) {
			event.pointer(Kind.PointerMove, x, y, Pointer.Nothing, mods);
			send(over, event);
		}
	}

	function hover(next:Null<Widget>):Void {
		if (next == over) return;

		if (over != null) over.hovered(false);
		over = next;
		if (over != null) over.hovered(true);
	}

	public function pressed(x:Float, y:Float, button:Pointer, mods:Mod, clicks:Int = 1):Void {
		pointerX = x;
		pointerY = y;
		this.mods = mods;

		final under = top.hit(x, y);
		hover(under);

		if (under == null) {
			focusOn(null);
			return;
		}

		capture = under;

		if (under.focusable && under.enabled) focusOn(under);
		else focusOn(null);

		event.pointer(Kind.PointerDown, x, y, button, mods, clicks);
		send(under, event);
	}

	public function released(x:Float, y:Float, button:Pointer, mods:Mod):Void {
		pointerX = x;
		pointerY = y;
		this.mods = mods;

		final held = capture;
		capture = null;

		if (held != null) {
			event.pointer(Kind.PointerUp, x, y, button, mods);
			send(held, event);
		}

		hover(top.hit(x, y));
	}

	public function turned(dx:Float, dy:Float, mods:Mod):Void {
		this.mods = mods;

		final under = capture != null ? capture : top.hit(pointerX, pointerY);
		if (under == null) return;

		event.turned(pointerX, pointerY, dx, dy, mods);
		send(under, event);
	}

	public function key(down:Bool, code:Key, mods:Mod, repeat:Bool = false):Bool {
		this.mods = mods;

		if (down && code == Key.Tab) {
			step((mods & Mod.Shift) != 0 ? -1 : 1);
			return true;
		}

		event.keyed(down ? Kind.KeyDown : Kind.KeyUp, code, mods, repeat);

		var at = focus;
		while (at != null) {
			if (at.enabled && at.took(event)) return true;
			at = at.parent;
		}

		return false;
	}

	public function said(text:String, mods:Mod):Bool {
		if (focus == null) return false;

		event.typed(text, mods);
		return focus.enabled && focus.took(event);
	}

	function send(to:Widget, event:Input):Void {
		var at:Null<Widget> = to;

		while (at != null) {
			if (at.enabled && at.took(event)) return;
			if (event.handled) return;
			at = at.parent;
		}
	}

	public function focusOn(next:Null<Widget>):Void {
		if (next == focus) return;

		if (focus != null) focus.focused(false);
		focus = next != null && next.focusable && next.enabled ? next : null;
		if (focus != null) focus.focused(true);

		soil();
	}

	public function step(by:Int):Void {
		order.resize(0);
		top.walk(order);

		if (order.length == 0) {
			focusOn(null);
			return;
		}

		var at = focus == null ? -1 : order.indexOf(focus);
		at += by;

		if (at < 0) at = order.length - 1;
		if (at >= order.length) at = 0;

		focusOn(order[at]);
	}

	public function focusable():Int {
		order.resize(0);
		top.walk(order);
		return order.length;
	}
}
