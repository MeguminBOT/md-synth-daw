package mdd.ui;

import mdd.ui.control.Menu;
import mdd.ui.control.Tooltip;
@:unreflective

/**
	The top of the widget tree: what has the keyboard, what is under the pointer, what
	is animating, and every layer drawn over the interface.

	There are three layers above the tree and they are not the same slot. `sheet` holds
	one modal, and raising anything there lowers whatever was in it. `band` is a second
	slot painted after the sheet, the popups and the tooltip, and hit tested before all
	three: `raise` and `lower` never touch it, which is what a progress bar needs. Menus
	are their own stack on top of the sheet.

	It draws only when something says it changed. Presenting a frame that was not drawn
	shows the buffer from two presents ago, so the idle path sleeps rather than
	presenting nothing.
**/
final class Root {
	static inline final STILL = 0.450;
	static inline final GRACE = 0.250;

	/**
		The widget the whole interface hangs from.
	**/
	public var top(default, null):Widget;

	/**
		The sizes everything draws at.
	**/
	public var metrics(default, null):Metrics;

	/**
		The colours everything draws in.
	**/
	public var theme(default, null):Theme;

	/**
		The icon atlas, where one is loaded.
	**/
	public var icons:Null<Icons> = null;

	/**
		How much motion is allowed. `None` makes every animation jump, which is what a
		check wants.
	**/
	public var flow:Flow = Flow.Full;

	/**
		Called with a chord the focus chain declined, so the application can act on it. This
		is what lets a chord reach past a field being typed into while a plain key does not.
	**/
	public var onShortcut:Null<(Key, Mod) -> Bool> = null;

	/**
		Called when the interface starts or stops wanting typed text.
	**/
	public var onTyping:Null<Bool -> Void> = null;

	var typingNow:Bool = false;

	/**
		What has the keyboard, or null for nothing.
	**/
	public var focus(default, null):Null<Widget> = null;

	/**
		What has taken the pointer for a drag, so every move reaches it until the button
		comes up.
	**/
	public var capture(default, null):Null<Widget> = null;

	/**
		What the pointer is over.
	**/
	public var over(default, null):Null<Widget> = null;

	var pointerX(default, null):Float = 0;
	var pointerY(default, null):Float = 0;

	/**
		Which modifiers were last held.
	**/
	public var mods(default, null):Mod = Mod.None;

	/**
		How wide the interface is.
	**/
	public var width(default, null):Float = 0;

	/**
		How tall it is.
	**/
	public var height(default, null):Float = 0;

	/**
		How many frames have been drawn.
	**/
	public var painted(default, null):Int = 0;

	/**
		The menus that are open, innermost last.
	**/
	public final popups:Array<Menu> = [];

	/**
		The one tooltip.
	**/
	public final tooltip:Tooltip = new Tooltip();

	/**
		Where every string the interface shows comes from.
	**/
	public final translation:Translation = new Translation();

	/**
		The one modal layer. Raising anything here lowers whatever was in it.
	**/
	public var sheet(default, null):Null<Widget> = null;

	/**
		A second layer nothing else can claim, for a widget that has to be seen: `raise`
		and `lower` never reach it, and it is painted last and hit tested first.
	**/
	public var band(default, null):Null<Widget> = null;

	/**
		How dark the sheet layer dims what is behind it.
	**/
	public final scrim:Motion;

	/**
		Whether the tooltip is showing.
	**/
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

	/**
		Builds a root over a widget tree.

		@param top The widget everything hangs from.
		@param metrics The sizes to draw at.
		@param theme The colours to draw in.
	**/
	public function new(top:Widget, metrics:Metrics, theme:Theme) {
		this.top = top;
		this.metrics = metrics;
		this.theme = theme;
		@:privateAccess top.attach(this);
		@:privateAccess tooltip.attach(this);

		scrim = new Motion(null, 0, false);
	}

	/**
		Says the next frame has to be drawn.
	**/
	public function soil():Void {
		soiled = true;
	}

	/**
		Says the next frame has to be laid out as well.
	**/
	public function reshape():Void {
		reshaped = true;
		soiled = true;
	}

	/**
		@return Whether anything has changed since the last frame, so a frame is worth drawing at
			all.
	**/
	public inline function stale():Bool {
		return soiled;
	}

	/**
		Resizes the interface and lays it out again.

		@param width How wide.
		@param height How tall.
	**/
	public function resize(width:Float, height:Float):Void {
		if (this.width == width && this.height == height) return;
		this.width = width;
		this.height = height;
		reshape();
	}

	/**
		Changes the density every size is worked out from.

		@param scale The new scale.
	**/
	public function rescale(scale:Float):Void {
		if (metrics.scale == scale) return;
		metrics.wear(scale);
		reshape();
	}

	/**
		@return How many motions are running, so a caller knows whether to keep drawing.
	**/
	public inline function animating():Int {
		return running.length;
	}

	/**
		Starts a motion under this root, so it is advanced every frame while it runs.

		@param motion The motion to run.
		@param to Where it should go.
		@param duration How long to take.
	**/
	public function start(motion:Motion, to:Float, duration:Float):Void {
		if (motion.run(to, duration, flow) && running.indexOf(motion) < 0) running.push(motion);
		soil();
	}

	/**
		Moves every running motion on, and decides whether the tooltip should appear.
		Call once a frame.

		@param seconds How long since the last call.
		@return Whether anything changed.
	**/
	public function advance(seconds:Float):Bool {
		var moved = false;

		reports();

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

	/**
		Counts down to the tooltip and shows or hides it.

		@param seconds How long since the last call.
		@return Whether anything changed.
	**/
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

	/**
		Shows the tooltip for a widget.

		@param want The widget it is about.
	**/
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

	/**
		Hides the tooltip.
	**/
	function hideTip():Void {
		if (!tipUp) return;

		tipUp = false;
		grace = 0;
		start(tooltip.fade, 0, Motion.leaving(Motion.ENTER));
	}

	/**
		Puts the tooltip where it fits, which is under the pointer unless that would
		put it off the edge.

		It follows the pointer rather than the widget it is about, because a widget
		is often the whole roll or the whole rack and its corner is nowhere near
		what is being described. Several of them say something different for every
		point inside them, which a corner cannot answer at all.
	**/
	function placeTip():Void {
		if (tooltip.subject == null) return;

		tooltip.measure(width, height);

		final clear = metrics.sizeOf(Tooltip.CLEAR);
		final below = metrics.sizeOf(Tooltip.BELOW);
		final wide = tooltip.wantWidth;
		final tall = tooltip.wantHeight;

		var px = pointerX + clear;
		var py = pointerY + below;

		if (px + wide > width) px = pointerX - wide - clear;
		if (px + wide > width) px = width - wide;
		if (px < 0) px = 0;

		if (py + tall > height) py = pointerY - tall - clear;
		if (py + tall > height) py = height - tall;
		if (py < 0) py = 0;

		tooltip.arrange(px, py, wide, tall);
	}

	/**
		@param key A string key.
		@return What it says in the language in force.
	**/
	public inline function translate(key:Int):String {
		return translation.of(key);
	}

	/**
		Puts a widget in the band layer, or clears it. This is the only way in or out
		of that layer.

		@param widget The widget, or null to clear it.
	**/
	public function bands(widget:Null<Widget>):Void {
		if (band == widget) return;

		final was = band;

		if (was != null) {
			@:privateAccess was.attach(null);
			band = null;
			if (focus == was) focusOn(null);
		}

		band = widget;

		if (band != null) {
			@:privateAccess band.attach(this);
			spread(band);
			hideTip();
			if (band.focusable) focusOn(band);
		}

		reshape();
	}

	/**
		Puts a widget in the sheet layer, lowering whatever was there and dimming what
		is behind it.

		@param widget The widget to raise.
	**/
	public function raise(widget:Widget):Void {
		if (sheet == widget) return;

		lower();

		sheet = widget;
		@:privateAccess widget.attach(this);

		spread(widget);
		start(scrim, 0.68, Motion.ENTER);
		hideTip();
		reshape();

		if (widget.focusable) focusOn(widget);
	}

	/**
		Takes the sheet down and lets the scrim fade.
	**/
	public function lower():Void {
		if (sheet == null) return;

		@:privateAccess sheet.attach(null);
		sheet = null;

		start(scrim, 0, Motion.leaving(Motion.ENTER));
		reshape();
		focusOn(null);
	}

	/**
		Opens a menu at a point, nested under whichever is already open where it came
		from one.

		@param menu The menu to open.
		@param px Where it goes, across.
		@param py Where it goes, down.
		@param from The widget it came from, or null.
	**/
	public function pop(menu:Menu, px:Float, py:Float, from:Null<Widget> = null):Void {
		if (popups.indexOf(menu) < 0 && !nested(menu)) dismiss();

		@:privateAccess menu.attach(this);

		if (opened() == 0) {
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

	/**
		Closes a menu and everything nested under it.

		@param menu The menu to close.
	**/
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

	/**
		Closes every open menu.
	**/
	public function dismiss():Void {
		if (popups.length == 0) return;
		shut(popups[0]);
	}

	/**
		@return How many menus are open.
	**/
	public function opened():Int {
		var many = 0;
		for (held in popups) if (!held.closing) many++;

		return many;
	}

	/**
		@param menu A menu.
		@return Whether it was opened from another one.
	**/
	function nested(menu:Menu):Bool {
		for (held in popups) if (!held.closing && held.opened == menu) return true;

		return false;
	}

	/**
		Takes a menu out of the stack and lets go of what it held.

		@param menu The menu.
	**/
	function leave(menu:Menu):Void {
		if (menu.closing) return;

		menu.leaving();
		start(menu.fade, 0, Motion.leaving(Motion.ENTER));
		soil();
	}

	/**
		Lays the whole interface out again, from the top down.
	**/
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

	/**
		Lays one layer out inside the window, centred where it asked to be smaller.

		@param widget The widget to lay out.
	**/
	function spread(widget:Widget):Void {
		widget.measure(width, height);

		final wide = widget.wantWidth > 0 ? widget.wantWidth : width * 0.5;
		final tall = widget.wantHeight > 0 ? widget.wantHeight : height * 0.6;

		final held = wide > width ? width : wide;
		final deep = tall > height ? height : tall;

		widget.arrange((width - held) * 0.5, (height - deep) * 0.5, held, deep);
	}

	/**
		Puts a menu where it fits, flipping it where it would go off the edge.

		@param menu The menu.
	**/
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

	/**
		Finds what a point belongs to, layer by layer: the band first, then the menus,
		then the sheet, then the tree.

		@param px A point, across.
		@param py A point, down.
		@return The widget there, or null.
	**/
	public function pick(px:Float, py:Float):Null<Widget> {
		if (band != null) {
			final caught = band.hit(px, py);
			return caught != null ? caught : band;
		}

		var i = popups.length - 1;

		while (i >= 0) {
			if (popups[i].closing) {
				i--;
				continue;
			}

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

	/**
		@param widget A widget, or null.
		@return Whether it is inside the sheet, so a press on it does not close the sheet.
	**/
	function owns(widget:Null<Widget>):Bool {
		if (widget == null || opener == null || !opener.drives) return false;

		var at:Null<Widget> = widget;
		while (at != null) {
			if (at == opener) return true;
			at = at.parent;
		}
		return false;
	}

	/**
		@param widget A widget, or null.
		@return Whether it is inside an open menu.
	**/
	function popped(widget:Null<Widget>):Bool {
		if (widget == null) return false;

		var at:Null<Widget> = widget;
		while (at.parent != null) at = at.parent;

		for (menu in popups) if (menu == at) return true;
		return false;
	}

	/**
		Lays out where it has to and draws one frame: the tree, the scrim, the sheet,
		the menus, the tooltip, then the band.

		@param paint What to draw with.
		@return False where nothing had changed and nothing was drawn, in which case the caller must
			not present either.
	**/
	public function frame(paint:Paint):Bool {
		if (!soiled) return false;

		if (reshaped) {
			top.measure(width, height);
			top.arrange(0, 0, width, height);

			if (sheet != null) spread(sheet);
			if (band != null) spread(band);

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

		if (band != null) {
			paint.rect(0, 0, width, height, theme.sink, 0.68);
			band.paint(paint);
		}

		paint.flush();

		top.settle();
		if (sheet != null) sheet.settle();
		for (menu in popups) menu.settle();
		tooltip.settle();

		soiled = false;
		painted++;
		return true;
	}

	/**
		Takes a pointer move, keeping it with whatever captured the pointer.

		@param x Where, across.
		@param y Where, down.
		@param mods Which modifier keys are held.
	**/
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
			shapes(x, y);
			return;
		}

		hover(pick(x, y));

		if (over != null) {
			event.pointer(Kind.PointerMove, x, y, Pointer.Nothing, mods);
			send(over, event);
		}

		shapes(x, y);
	}

	/**
		Puts the cursor the widget under the pointer asks for on the window. A
		widget holding a drag keeps answering, so the shape does not flicker back
		the moment a drag leaves the thing it started on.

		@param x Where the pointer is, across.
		@param y Where it is, down.
	**/
	function shapes(x:Float, y:Float):Void {
		final held = capture != null ? capture : over;

		mdd.host.Sdl.cursor(held == null
			? mdd.host.Sdl.CURSOR_ARROW : held.cursorAt(x, y));
	}

	/**
		Moves the hover from one widget to another, telling both.

		@param next What is under the pointer now, or null.
	**/
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

	/**
		Takes a pointer press. A press outside an open menu closes it, and a press
		outside the sheet lowers it.

		@param x Where, across.
		@param y Where, down.
		@param button Which button.
		@param mods Which modifier keys are held.
		@param clicks How many clicks in quick succession.
	**/
	public function pressed(x:Float, y:Float, button:Pointer, mods:Mod, clicks:Int = 1):Void {
		pointerX = x;
		pointerY = y;
		this.mods = mods;

		blocked = true;
		hideTip();

		final under = pick(x, y);

		if (opened() > 0 && !popped(under) && !owns(under)) {
			dismiss();
			return;
		}

		if (sheet != null && !sheet.sealed && !sheet.modal && !sheet.accepts(x, y)) {
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

	/**
		Takes a pointer release and gives up the capture.

		@param x Where, across.
		@param y Where, down.
		@param button Which button.
		@param mods Which modifier keys are held.
	**/
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

	/**
		Takes a wheel turn, to whatever is under the pointer.

		@param dx How far, across.
		@param dy How far, down.
		@param mods Which modifier keys are held.
	**/
	public function turned(dx:Float, dy:Float, mods:Mod):Void {
		this.mods = mods;

		final under = capture != null ? capture : pick(pointerX, pointerY);
		if (under == null) return;

		event.turned(pointerX, pointerY, dx, dy, mods);
		send(under, event);
	}

	/**
		Takes a key. It goes to the focus first, then up the chain, and only then to
		`onShortcut`, which is what lets a field keep its plain keys while a chord
		still reaches past it.

		@param down Whether the key went down.
		@param code Which key.
		@param mods Which modifier keys are held.
		@param repeat Whether it is repeating.
		@return Whether anything took it.
	**/
	public function key(down:Bool, code:Key, mods:Mod, repeat:Bool = false):Bool {
		this.mods = mods;

		if (down) {
			blocked = true;
			hideTip();
		}

		if (down && code == Key.Escape && popups.length == 0 && sheet != null) {
			if (!sheet.sealed) lower();
			return true;
		}

		event.keyed(down ? Kind.KeyDown : Kind.KeyUp, code, mods, repeat);

		var at = focus;
		while (at != null) {
			if (at.enabled && at.took(event)) return true;
			at = at.parent;
		}

		if (down && code == Key.Tab && popups.length == 0) {
			step((mods & Mod.Shift) != 0 ? -1 : 1);
			return true;
		}

		if (!down || onShortcut == null) return false;
		if (typed() && (mods & (Mod.Ctrl | Mod.Alt)) == 0) return false;

		return onShortcut(code, mods);
	}

	/**
		Tells the application whether the keyboard is wanted, where that changed.
	**/
	public function reports():Void {
		final want = typed();
		if (want == typingNow) return;

		typingNow = want;
		if (onTyping != null) onTyping(want);
	}

	/**
		@return Whether whatever has the keyboard is taking typed text.
	**/
	public inline function typed():Bool {
		return focus != null && focus.typing;
	}

	/**
		@return What an editing command should go to, which is the focus unless a menu is open over
			it.
	**/
	function acting():Null<Widget> {
		return popups.length > 0 && returnFocus != null ? returnFocus : focus;
	}

	/**
		Sends an editing command to whatever should have it.

		@param what One of the `Edit` values.
		@return Whether anything took it.
	**/
	public function edits(what:Int):Bool {
		if (typed()) return false;

		var at = acting();

		while (at != null) {
			if (at.enabled && at.edited(what)) return true;
			at = at.parent;
		}

		return false;
	}

	/**
		Sends typed text to the focus.

		@param text The text.
		@param mods Which modifier keys are held.
		@return Whether it was taken.
	**/
	public function said(text:String, mods:Mod):Bool {
		if (focus == null) return false;

		event.typed(text, mods);
		return focus.enabled && focus.took(event);
	}

	/**
		Sends an event to a widget and then up its chain until something takes it.

		@param to Where to start.
		@param event The event.
	**/
	function send(to:Widget, event:Input):Void {
		var at:Null<Widget> = to;

		while (at != null) {
			if (at.enabled && at.took(event)) return;
			if (event.handled) return;
			at = at.parent;
		}
	}

	/**
		Moves the keyboard to a widget, telling both it and whatever had it.

		@param next The widget, or null for nothing.
	**/
	public function focusOn(next:Null<Widget>):Void {
		if (next == focus) return;

		if (focus != null) focus.focused(false);
		focus = next != null && next.focusable && next.enabled ? next : null;
		if (focus != null) focus.focused(true);

		soil();
	}

	/**
		Moves the keyboard to the next or previous widget that can take it, wrapping at
		the ends.

		@param by One forwards, minus one backwards.
	**/
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

	/**
		@return How many widgets can take the keyboard now.
	**/
	public function focusable():Int {
		order.resize(0);
		top.walk(order);
		return order.length;
	}
}
