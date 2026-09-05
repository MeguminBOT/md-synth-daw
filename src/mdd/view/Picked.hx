package mdd.view;

@:generic
@:unreflective
final class Picked<T:{}> {
	public var count(get, never):Int;

	final order:Array<T> = [];
	final marks:haxe.ds.ObjectMap<T, Bool> = new haxe.ds.ObjectMap<T, Bool>();

	public function new() {}

	inline function get_count():Int {
		return order.length;
	}

	public inline function holds(item:T):Bool {
		return marks.exists(item);
	}

	public inline function at(index:Int):T {
		return order[index];
	}

	public function lead():Null<T> {
		return order.length == 0 ? null : order[order.length - 1];
	}

	public function adds(item:T):Bool {
		if (marks.exists(item)) return false;

		marks.set(item, true);
		order.push(item);

		return true;
	}

	public function drops(item:T):Bool {
		if (!marks.exists(item)) return false;

		marks.remove(item);
		order.remove(item);

		return true;
	}

	public function toggles(item:T):Bool {
		if (drops(item)) return false;

		adds(item);
		return true;
	}

	public function only(item:T):Void {
		clear();
		adds(item);
	}

	public function clear():Void {
		if (order.length == 0) return;

		order.resize(0);
		marks.clear();
	}

	public function taken():Array<T> {
		return order.copy();
	}
}
