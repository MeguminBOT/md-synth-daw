package mdd.format;

/**
	One value read out of a JSON document: nothing, a flag, a number, some text, a list
	or a table.

	Reading an absent key gives an empty node rather than null, so a document with a
	field missing reads as the default rather than faulting on the way in.
**/
final class Node {
	/**
		Shape: a null.
	**/
	public static inline final NOTHING = 0;

	/**
		Shape: true or false.
	**/
	public static inline final FLAG = 1;

	/**
		Shape: a number.
	**/
	public static inline final NUMBER = 2;

	/**
		Shape: a string.
	**/
	public static inline final TEXT = 3;

	/**
		Shape: an array.
	**/
	public static inline final LIST = 4;

	/**
		Shape: an object.
	**/
	public static inline final TABLE = 5;

	/**
		What a missing key reads as. Shared and never written to.
	**/
	public static final EMPTY:Node = new Node(NOTHING);

	/**
		Which of the six shapes this node is.
	**/
	public var shape(default, null):Int;

	/**
		Its value, for a number or a flag.
	**/
	public var number(default, null):Float = 0;

	/**
		Its value, for a string.
	**/
	public var text(default, null):String = "";

	/**
		The keys of a table, in the order the document wrote them. An array rather than a
		map because a map insertion order is preserved on some Haxe targets and not on
		hxcpp, and a project that reorders itself between saves is not byte identical.
	**/
	public final keys:Array<String> = [];

	/**
		The values of a table or the entries of a list.
	**/
	public final values:Array<Node> = [];

	/**
		Builds an empty node of a shape.

		@param shape Which of the six shapes.
	**/
	public function new(shape:Int) {
		this.shape = shape;
	}

	/**
		@param value True or false.
		@return A node holding it.
	**/
	public static function flag(value:Bool):Node {
		final node = new Node(FLAG);
		node.number = value ? 1 : 0;
		return node;
	}

	/**
		@param value A number.
		@return A node holding it.
	**/
	public static function counted(value:Float):Node {
		final node = new Node(NUMBER);
		node.number = value;
		return node;
	}

	/**
		@param value Some text.
		@return A node holding it.
	**/
	public static function words(value:String):Node {
		final node = new Node(TEXT);
		node.text = value;
		return node;
	}

	/**
		Adds a key to a table.

		@param key The key.
		@param value What it holds.
		@return This node, so calls can be chained.
	**/
	public function put(key:String, value:Node):Node {
		keys.push(key);
		values.push(value);
		return this;
	}

	/**
		Adds an entry to a list.

		@param value What to add.
		@return This node, so calls can be chained.
	**/
	public function push(value:Node):Node {
		values.push(value);
		return this;
	}

	/**
		@param key A key.
		@return Whether the table carries it.
	**/
	public function has(key:String):Bool {
		return keys.indexOf(key) >= 0;
	}

	/**
		@param key A key.
		@return What it holds, or `EMPTY` where the table does not carry it.
	**/
	public function get(key:String):Node {
		final at = keys.indexOf(key);
		return at < 0 ? EMPTY : values[at];
	}

	/**
		@param index A position in the list.
		@return The entry there, or `EMPTY` where the index is out of range.
	**/
	public function at(index:Int):Node {
		return index < 0 || index >= values.length ? EMPTY : values[index];
	}

	/**
		@return How many entries a list holds.
	**/
	public inline function length():Int {
		return values.length;
	}

	/**
		@param fallback What to answer where this is not a number.
		@return The value as a whole number.
	**/
	public function whole(fallback:Int = 0):Int {
		return shape == NUMBER || shape == FLAG ? Std.int(number) : fallback;
	}

	/**
		@param fallback What to answer where this is not a number.
		@return The value as a number.
	**/
	public function real(fallback:Float = 0):Float {
		return shape == NUMBER || shape == FLAG ? number : fallback;
	}

	/**
		@param fallback What to answer where this is not text.
		@return The value as text.
	**/
	public function saying(fallback:String = ""):String {
		return shape == TEXT ? text : fallback;
	}

	/**
		@param fallback What to answer where this is not a flag.
		@return The value as a flag.
	**/
	public function truth(fallback:Bool = false):Bool {
		return shape == FLAG || shape == NUMBER ? number != 0 : fallback;
	}
}
