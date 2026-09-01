package mdd.ui;

@:unreflective
final class Root {
	public static inline final STILL = 0.450;
	public static inline final GRACE = 0.250;

	public var top(default, null):Widget;
	public var metrics(default, null):Metrics;
	public var theme(default, null):Theme;

	public var flow:Flow = Flow.Full;

	public var onChord:Null<(Key, Mod) -> Bool> = null;

	public var focus(default, null):Null<Widget> = null;
	public var capture(default, null):Null<Widget> = null;
	public var over(default, null):Null<Widget> = null;

	public var pointerX(default, null):Float = 0;
	public var pointerY(default, null):Float = 0;
	public var mods(default, null):Mod = Mod.None;

	public var width(default, null):Float = 0;
	public var height(default, null):Float = 0;

	public var painted(default, null):Int = 0;

	public final popups:Array<Menu> = [];
	public final tooltip:Tooltip = new Tooltip();
	public final translation:Translation = new Translation();

	public var sheet(default, null):Null<Widget> = null;

	public final scrim:Motion;

	public var tipUp(default, null):Bool = false;

	var soiled:Bool = true;
	var reshaped:Bool = true;

	var still:Float = 0;
	var grace:Float = GRACE;
	var blocked:Bool = false;

	var returnFocus:Null<Widget> = null;
	var tipText:String = "";
	var tipDetail:String = "";
	var opener:Null<Widget> = null;

	final event:Input = new Input();
	final order:Array<Widget> = [];
	final running:Array<Motion> = [];

	public function new(top:Widget, metrics:Metrics, theme:Theme) {
		this.top = top;
		this.metrics = metrics;
		this.theme = theme;
		@:privateAccess top.attach(this);
		@:privateAccess tooltip.attach(this);

		scrim = new Motion(null, 0, false);
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

	public inline function animating():Int {
		return running.length;
	}

	public function start(motion:Motion, to:Float, duration:Float):Void {
		if (motion.run(to, duration, flow) && running.indexOf(motion) < 0) running.push(motion);
		soil();
	}

	public function advance(seconds:Float):Bool {
		var moved = false;

		if (running.length > 0) {
			final many = running.length;
			var kept = 0;

			for (i in 0...many) {
				final one = running[i];
				one.advance(seconds);

				if (one.running) {
					running[kept] = one;
					kept++;
				}
			}

			var at = many;
			while (at < running.length) {
				running[kept] = running[at];
				kept++;
				at++;
			}

			running.resize(kept);
			moved = true;
			soil();
		}

		sweep();

		var at = 0;
		final many = popups.length;

		while (at < many && at < popups.length) {
			popups[at].tick(seconds);
			at++;
		}

		if (hint(seconds)) moved = true;

		return moved;
	}

	function hint(seconds:Float):Bool {
		if (capture != null || blocked) {
			if (tipUp) hideTip();
			still = 0;
			return false;
		}

		if (tipUp) {
			final held = over;
			if (held == null) return false;
			if (held.tip == tipText && held.detail == tipDetail) return false;

			tipText = held.tip;
			tipDetail = held.detail;

			if (held.tip == "") {
				hideTip();
				return false;
			}

			placeTip();
			soil();
			return true;
		}

		still += seconds;
		grace += seconds;

		final want = over;
		if (want == null || want.tip == "" || !want.visible) return false;
		if (still < STILL && grace >= GRACE) return false;

		showTip(want);
		return true;
	}

	function showTip(want:Widget):Void {
		tooltip.describe(want);
		tooltip.measure(width, height);
		if (tooltip.wantWidth <= 0) return;

		tipUp = true;
		tipText = want.tip;
		tipDetail = want.detail;
		placeTip();
		start(tooltip.fade, 1, Motion.ENTER);
	}

	function hideTip():Void {
		if (!tipUp) return;

		tipUp = false;
		grace = 0;
		start(tooltip.fade, 0, Motion.leaving(Motion.ENTER));
	}

	function placeTip():Void {
		final want = tooltip.subject;
		if (want == null) return;

		tooltip.measure(width, height);

		final clear = metrics.sizeOf(Tooltip.CLEAR);
		final wide = tooltip.wantWidth;
		final tall = tooltip.wantHeight;

		var px = want.x + clear;
		var py = want.y + want.height + clear;

		if (px + wide > width) px = width - wide - clear;
		if (px < 0) px = 0;

		if (py + tall > height) py = want.y - tall - clear;
		if (py < 0) py = 0;

		tooltip.arrange(px, py, wide, tall);
	}

	public inline function translate(key:String):String {
		return translation.of(key);
	}

	public function raise(widget:Widget):Void {
		if (sheet == widget) return;

		lower();

		sheet = widget;
		@:privateAccess widget.attach(this);

		start(scrim, 0.68, Motion.ENTER);
		hideTip();
		reshape();

		if (widget.focusable) focusOn(widget);
	}

	public function lower():Void {
		if (sheet == null) return;

		@:privateAccess sheet.attach(null);
		sheet = null;

		start(scrim, 0, Motion.leaving(Motion.ENTER));
		reshape();
		focusOn(null);
	}

	public function pop(menu:Menu, px:Float, py:Float, from:Null<Widget> = null):Void {
		@:privateAccess menu.attach(this);

		if (popups.length == 0) {
			returnFocus = focus;
			opener = from;
		}

		menu.anchor(px, py);
		menu.arrive();

		if (popups.indexOf(menu) < 0) popups.push(menu);

		place(menu);
		start(menu.fade, 1, Motion.ENTER);
		start(menu.rise, 1, Motion.ENTER);

		hideTip();
		focusOn(menu);
		soil();
	}

	public function shut(menu:Menu):Void {
		final at = popups.indexOf(menu);
		if (at < 0) return;

		var i = popups.length - 1;
		while (i >= at) {
			leave(popups[i]);
			i--;
		}

		sweep();
	}

	public function dismiss():Void {
		if (popups.length == 0) return;
		shut(popups[0]);
	}

	function leave(menu:Menu):Void {
		if (menu.closing) return;

		menu.leaving();
		start(menu.fade, 0, Motion.leaving(Motion.ENTER));
		soil();
	}

	function sweep():Void {
		if (popups.length == 0) return;

		var kept = 0;

		for (i in 0...popups.length) {
			final one = popups[i];

			if (one.closing && !one.fade.running) {
				if (focus == one) focusOn(null);
				@:privateAccess one.attach(null);
				if (one.onClose != null) one.onClose(one.fade);
				soil();
				continue;
			}

			popups[kept] = one;
			kept++;
		}

		if (kept == popups.length) return;

		popups.resize(kept);

		if (popups.length > 0) focusOn(popups[popups.length - 1]);
		else {
			focusOn(returnFocus);
			returnFocus = null;
			opener = null;
		}
	}

	function spread(widget:Widget):Void {
		widget.measure(width, height);

		final wide = widget.wantWidth > 0 ? widget.wantWidth : width * 0.5;
		final tall = widget.wantHeight > 0 ? widget.wantHeight : height * 0.6;

		final held = wide > width ? width : wide;
		final deep = tall > height ? height : tall;

		widget.arrange((width - held) * 0.5, (height - deep) * 0.5, held, deep);
	}

	function place(menu:Menu):Void {
		menu.measure(width, height);

		final wide = menu.wantWidth;
		final tall = menu.wantHeight;

		var px = menu.anchorX;
		var py = menu.anchorY;

		if (px + wide > width) px = menu.anchorX - wide;
		if (px < 0) px = 0;

		if (py + tall > height) py = height - tall;
		if (py < 0) py = 0;

		menu.arrange(px, py, wide, tall);
	}

	public function pick(px:Float, py:Float):Null<Widget> {
		var i = popups.length - 1;

		while (i >= 0) {
			final found = popups[i].hit(px, py);
			if (found != null) return found;
			i--;
		}

		if (sheet != null) {
			final found = sheet.hit(px, py);
			return found != null ? found : sheet;
		}

		return top.hit(px, py);
	}

	function owns(widget:Null<Widget>):Bool {
		if (widget == null || opener == null) return false;

		var at:Null<Widget> = widget;
		while (at != null) {
			if (at == opener) return true;
			at = at.parent;
		}
		return false;
	}

	function popped(widget:Null<Widget>):Bool {
		if (widget == null) return false;

		var at:Null<Widget> = widget;
		while (at.parent != null) at = at.parent;

		for (menu in popups) if (menu == at) return true;
		return false;
	}

	public function frame(paint:Paint):Bool {
		if (!soiled) return false;

		if (reshaped) {
			top.measure(width, height);
			top.arrange(0, 0, width, height);

			if (sheet != null) spread(sheet);

			for (menu in popups) place(menu);
			if (tipUp) placeTip();

			reshaped = false;
		}

		paint.reset();
		top.paint(paint);

		if (scrim.value > 0.004) {
			paint.rect(0, 0, width, height, theme.sink, scrim.value);
		}

		if (sheet != null) sheet.paint(paint);

		for (menu in popups) menu.paint(paint);
		if (tooltip.fade.value > 0) tooltip.paint(paint);

		paint.flush();

		top.settle();
		if (sheet != null) sheet.settle();
		for (menu in popups) menu.settle();
		tooltip.settle();

		soiled = false;
		painted++;
		return true;
	}

	public function moved(x:Float, y:Float, mods:Mod):Void {
		if (x != pointerX || y != pointerY) {
			still = 0;
			blocked = false;
		}

		pointerX = x;
		pointerY = y;
		this.mods = mods;

		if (capture != null) {
			event.pointer(Kind.PointerMove, x, y, Pointer.Left, mods);
			send(capture, event);
			return;
		}

		hover(pick(x, y));

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

		if (!tipUp) return;

		if (over != null && over.tip != "") {
			tooltip.describe(over);
			placeTip();
			soil();
		} else {
			hideTip();
		}
	}

	public function pressed(x:Float, y:Float, button:Pointer, mods:Mod, clicks:Int = 1):Void {
		pointerX = x;
		pointerY = y;
		this.mods = mods;

		blocked = true;
		hideTip();

		final under = pick(x, y);

		if (popups.length > 0 && !popped(under) && !owns(under)) {
			dismiss();
			return;
		}

		if (sheet != null && under == sheet) {
			lower();
			return;
		}

		hover(under);

		if (under == null) {
			focusOn(null);
			return;
		}

		capture = under;

		if (under.focusable && under.enabled) focusOn(under);
		else if (!popped(under)) focusOn(null);

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

		hover(pick(x, y));
	}

	public function turned(dx:Float, dy:Float, mods:Mod):Void {
		this.mods = mods;

		final under = capture != null ? capture : pick(pointerX, pointerY);
		if (under == null) return;

		event.turned(pointerX, pointerY, dx, dy, mods);
		send(under, event);
	}

	public function key(down:Bool, code:Key, mods:Mod, repeat:Bool = false):Bool {
		this.mods = mods;

		if (down) {
			blocked = true;
			hideTip();
		}

		if (down && code == Key.Escape && popups.length == 0 && sheet != null) {
			lower();
			return true;
		}

		if (down && code == Key.Tab && popups.length == 0) {
			step((mods & Mod.Shift) != 0 ? -1 : 1);
			return true;
		}

		event.keyed(down ? Kind.KeyDown : Kind.KeyUp, code, mods, repeat);

		var at = focus;
		while (at != null) {
			if (at.enabled && at.took(event)) return true;
			at = at.parent;
		}

		if (!down || onChord == null) return false;
		if (typed() && (mods & (Mod.Ctrl | Mod.Alt)) == 0) return false;

		return onChord(code, mods);
	}

	public inline function typed():Bool {
		return focus != null && focus.typing;
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
