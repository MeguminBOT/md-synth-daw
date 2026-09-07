package mdd.ui.control;

@:unreflective
class Choice {
	public var label:String;
	public var shortcut:String = "";
	public var reason:String = "";
	public var enabled:Bool = true;
	public var submenu:Null<Menu> = null;

	public var onFire:Null<Choice -> Void> = null;

	public var divides(default, null):Bool = false;

	public function new(label:String, shortcut:String = "") {
		this.label = label;
		this.shortcut = shortcut;
	}

	public static function divider():Choice {
		final one = new Choice("");
		one.divides = true;
		one.enabled = false;
		return one;
	}

	public inline function opens():Bool {
		return submenu != null;
	}

	public inline function pickable():Bool {
		return !divides && enabled;
	}
}
