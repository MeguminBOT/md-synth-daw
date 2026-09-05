package mdd.ui;

@:unreflective
class Item {
	public var label:String;
	public var tint:Int = -1;
	public var icon:Int = -1;
	public var open:Bool = true;
	public var note:String = "";
	public var says:String = "";
	public var enabled:Bool = true;

	public var depth(default, null):Int = 0;
	public var parent(default, null):Null<Item> = null;
	public final children:Array<Item> = [];

	public function new(label:String, tint:Int = -1) {
		this.label = label;
		this.tint = tint;
	}

	public function add(child:Item):Item {
		if (child.parent != null) child.parent.children.remove(child);
		child.parent = this;
		child.deepen(depth + 1);
		children.push(child);
		return child;
	}

	function deepen(to:Int):Void {
		depth = to;
		for (child in children) child.deepen(to + 1);
	}

	public inline function branch():Bool {
		return children.length > 0;
	}

	public function count():Int {
		var total = 1;
		for (child in children) total += child.count();
		return total;
	}
}
