package mdd.ui;

@:unreflective

/**
	One input event, on its way down the widget tree.

	There is one of these and it is filled in again for each event rather than
	allocated, because events arrive on every pointer move and nothing in a frame
	should have to be collected.
**/
final class Input {
	/**
		What kind of event it is.
	**/
	public var kind:Kind = None;

	/**
		Where it happened, across.
	**/
	public var x:Float = 0;

	/**
		Where it happened, down.
	**/
	public var y:Float = 0;

	/**
		How far a wheel or a drag moved, across.
	**/
	public var dx:Float = 0;

	/**
		How far it moved, down.
	**/
	public var dy:Float = 0;

	/**
		Which pointer button, for a pointer event.
	**/
	public var button:Pointer = Nothing;

	/**
		How many clicks in quick succession this is.
	**/
	public var clicks:Int = 0;

	/**
		Which modifier keys were held.
	**/
	public var mods:Mod = None;

	/**
		Which key, for a key event.
	**/
	public var code:Key = A;

	/**
		Whether the key is repeating rather than newly down.
	**/
	public var repeat:Bool = false;

	/**
		The text, for a typing event.
	**/
	public var said:String = "";

	/**
		Whether something has taken it. Once set, nothing further down or up the chain acts
		on it.
	**/
	public var handled:Bool = false;

	/**
		Builds an empty event to fill in.
	**/
	public function new() {}

	/**
		@return Whether shift was held.
	**/
	public inline function shift():Bool return (mods & Mod.Shift) != 0;

	/**
		@return Whether control was held.
	**/
	public inline function ctrl():Bool return (mods & Mod.Ctrl) != 0;

	/**
		@return Whether alt was held.
	**/
	public inline function alt():Bool return (mods & Mod.Alt) != 0;

	/**
		@return Whether no modifier was held, which is what separates a key a field should swallow
			from a chord that must reach past it.
	**/
	public inline function plain():Bool {
		return (mods & (Mod.Shift | Mod.Ctrl | Mod.Alt)) == 0;
	}

	/**
		Marks the event handled.
	**/
	public inline function take():Void {
		handled = true;
	}

	/**
		Fills this in as a pointer event.

		@param kind Down, up or move.
		@param x Where, across.
		@param y Where, down.
		@param button Which button.
		@param mods Which modifiers were held.
		@param clicks How many clicks in quick succession.
	**/
	public function pointer(kind:Kind, x:Float, y:Float, button:Pointer, mods:Mod,
			clicks:Int = 1):Void {
		this.kind = kind;
		this.x = x;
		this.y = y;
		this.button = button;
		this.mods = mods;
		this.clicks = clicks;
		this.dx = 0;
		this.dy = 0;
		handled = false;
	}

	/**
		Fills this in as a wheel event.

		@param x Where, across.
		@param y Where, down.
		@param dx How far it turned, across.
		@param dy How far it turned, down.
		@param mods Which modifiers were held.
	**/
	public function turned(x:Float, y:Float, dx:Float, dy:Float, mods:Mod):Void {
		kind = Wheel;
		this.x = x;
		this.y = y;
		this.dx = dx;
		this.dy = dy;
		this.mods = mods;
		handled = false;
	}

	/**
		Fills this in as a key event.

		@param kind Down or up.
		@param code Which key.
		@param mods Which modifiers were held.
		@param repeat Whether it is repeating.
	**/
	public function keyed(kind:Kind, code:Key, mods:Mod, repeat:Bool):Void {
		this.kind = kind;
		this.code = code;
		this.mods = mods;
		this.repeat = repeat;
		handled = false;
	}

	/**
		Fills this in as a typing event.

		@param said The text.
		@param mods Which modifiers were held.
	**/
	public function typed(said:String, mods:Mod):Void {
		kind = Text;
		this.said = said;
		this.mods = mods;
		handled = false;
	}
}
