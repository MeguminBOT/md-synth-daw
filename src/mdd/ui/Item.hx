package mdd.ui;

/**
	One row of a tree or a list: a label, a colour, an icon, and whatever hangs under
	it.

	It is the model a `Tree` draws rather than a widget of its own, so a tree of a
	thousand rows is a thousand of these and not a thousand widgets.
**/
@:unreflective
class Item {
	/**
		What the row says.
	**/
	public var label:String;

	/**
		Its colour, or -1 for the theme.
	**/
	public var tint:Int = -1;

	/**
		Which icon it carries, or -1 for none.
	**/
	public var icon:Int = -1;

	/**
		Whether its children are shown.
	**/
	public var open:Bool = true;

	/**
		A second line under the label, where there is one.
	**/
	public var note:String = "";

	/**
		What its tooltip says.
	**/
	public var says:String = "";

	/**
		Whether it can be chosen.
	**/
	public var enabled:Bool = true;

	/**
		How far down the tree it sits.
	**/
	public var depth(default, null):Int = 0;

	/**
		What it hangs under, or null at the top.
	**/
	public var parent(default, null):Null<Item> = null;

	/**
		What hangs under it.
	**/
	public final children:Array<Item> = [];

	/**
		Builds a row with nothing under it.

		@param label What it says.
		@param tint Its colour, or -1 for the theme.
	**/
	public function new(label:String, tint:Int = -1) {
		this.label = label;
		this.tint = tint;
	}

	/**
		Hangs a row under this one, taking it off whatever held it before.

		@param child The row to add.
		@return The same row.
	**/
	public function add(child:Item):Item {
		if (child.parent != null) child.parent.children.remove(child);
		child.parent = this;
		child.deepen(depth + 1);
		children.push(child);
		return child;
	}

	/**
		Sets the depth of this row and everything under it.

		@param to The depth this row now sits at.
	**/
	function deepen(to:Int):Void {
		depth = to;
		for (child in children) child.deepen(to + 1);
	}

	/**
		@return Whether anything hangs under it.
	**/
	public inline function branch():Bool {
		return children.length > 0;
	}

	/**
		@return How many rows there are here and below, whether or not they are shown.
	**/
	public function count():Int {
		var total = 1;
		for (child in children) total += child.count();
		return total;
	}
}
