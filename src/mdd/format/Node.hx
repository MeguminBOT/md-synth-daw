package mdd.format;

final class Node {
	public static inline final NOTHING = 0;
	public static inline final FLAG = 1;
	public static inline final NUMBER = 2;
	public static inline final TEXT = 3;
	public static inline final LIST = 4;
	public static inline final TABLE = 5;

	public static final EMPTY:Node = new Node(NOTHING);

	public var shape(default, null):Int;
	public var number(default, null):Float = 0;
	public var text(default, null):String = "";

	public final keys:Array<String> = [];
	public final values:Array<Node> = [];

	public function new(shape:Int) {
		this.shape = shape;
	}

	public static function flag(value:Bool):Node {
		final node = new Node(FLAG);
		node.number = value ? 1 : 0;
		return node;
	}

	public static function counted(value:Float):Node {
		final node = new Node(NUMBER);
		node.number = value;
		return node;
	}

	public static function words(value:String):Node {
		final node = new Node(TEXT);
		node.text = value;
		return node;
	}

	public function put(key:String, value:Node):Node {
		keys.push(key);
		values.push(value);
		return this;
	}

	public function push(value:Node):Node {
		values.push(value);
		return this;
	}

	public function has(key:String):Bool {
		return keys.indexOf(key) >= 0;
	}

	public function get(key:String):Node {
		final at = keys.indexOf(key);
		return at < 0 ? EMPTY : values[at];
	}

	public function at(index:Int):Node {
		return index < 0 || index >= values.length ? EMPTY : values[index];
	}

	public inline function length():Int {
		return values.length;
	}

	public function whole(fallback:Int = 0):Int {
		return shape == NUMBER || shape == FLAG ? Std.int(number) : fallback;
	}

	public function real(fallback:Float = 0):Float {
		return shape == NUMBER || shape == FLAG ? number : fallback;
	}

	public function saying(fallback:String = ""):String {
		return shape == TEXT ? text : fallback;
	}

	public function truth(fallback:Bool = false):Bool {
		return shape == FLAG || shape == NUMBER ? number != 0 : fallback;
	}
}
