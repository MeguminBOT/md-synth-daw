package mdd.ui.control;

@:unreflective

/**
	One entry in a menu: a label, a shortcut, and what happens when it is chosen.

	It is a plain object rather than a widget, so a menu of forty entries is forty of
	these and one widget.
**/
class Choice {
	/**
		What it says.
	**/
	public var label:String;

	/**
		The chord shown beside it, or an empty string.
	**/
	public var shortcut:String = "";

	/**
		Why it is disabled, shown where it is. An entry that is off for a reason should say
		the reason rather than only being grey.
	**/
	public var reason:String = "";

	/**
		Whether it can be chosen.
	**/
	public var enabled:Bool = true;

	/**
		Whether it is on, for an entry that turns something on or picks one of several. A tick is
		drawn beside it in a menu that is `ticking`.
	**/
	public var ticked:Bool = false;

	/**
		What opens from it, where anything does.
	**/
	public var submenu:Null<Menu> = null;

	/**
		What to do when it is chosen.
	**/
	public var onFire:Null<Choice -> Void> = null;

	/**
		Whether this is a line between groups rather than an entry.
	**/
	public var divides(default, null):Bool = false;

	/**
		Builds an entry.

		@param label What it says.
		@param shortcut The chord to show beside it.
	**/
	public function new(label:String, shortcut:String = "") {
		this.label = label;
		this.shortcut = shortcut;
	}

	/**
		@return A line between groups, which cannot be chosen.
	**/
	public static function divider():Choice {
		final one = new Choice("");
		one.divides = true;
		one.enabled = false;
		return one;
	}

	/**
		@return Whether it opens a menu of its own.
	**/
	public inline function opens():Bool {
		return submenu != null;
	}

	/**
		@return Whether it can be chosen: enabled, and not a divider.
	**/
	public inline function pickable():Bool {
		return !divides && enabled;
	}
}
