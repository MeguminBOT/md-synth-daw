package mdd.ui;

@:unreflective
final class Input {
	public var kind:Kind = None;
	public var x:Float = 0;
	public var y:Float = 0;
	public var dx:Float = 0;
	public var dy:Float = 0;
	public var button:Pointer = Nothing;
	public var clicks:Int = 0;
	public var mods:Mod = None;
	public var code:Key = A;
	public var repeat:Bool = false;
	public var said:String = "";
	public var handled:Bool = false;

	public function new() {}

	public inline function shift():Bool return (mods & Mod.Shift) != 0;

	public inline function ctrl():Bool return (mods & Mod.Ctrl) != 0;

	public inline function alt():Bool return (mods & Mod.Alt) != 0;

	public inline function plain():Bool {
		return (mods & (Mod.Shift | Mod.Ctrl | Mod.Alt)) == 0;
	}

	public inline function take():Void {
		handled = true;
	}

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

	public function turned(x:Float, y:Float, dx:Float, dy:Float, mods:Mod):Void {
		kind = Wheel;
		this.x = x;
		this.y = y;
		this.dx = dx;
		this.dy = dy;
		this.mods = mods;
		handled = false;
	}

	public function keyed(kind:Kind, code:Key, mods:Mod, repeat:Bool):Void {
		this.kind = kind;
		this.code = code;
		this.mods = mods;
		this.repeat = repeat;
		handled = false;
	}

	public function typed(said:String, mods:Mod):Void {
		kind = Text;
		this.said = said;
		this.mods = mods;
		handled = false;
	}
}
