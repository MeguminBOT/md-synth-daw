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

	public function alters(order:Array<T>, anchor:Null<T>, lead:T, shift:Bool,
			ctrl:Bool):Void {
		if (shift) {
			ranges(order, anchor, lead);
			return;
		}

		if (ctrl) {
			toggles(lead);
			return;
		}

		if (!holds(lead)) only(lead);
	}

	public function ranges(order:Array<T>, anchor:Null<T>, lead:T):Void {
		final from = anchor == null ? -1 : order.indexOf(anchor);
		final to = order.indexOf(lead);

		if (from < 0 || to < 0) {
			only(lead);
			return;
		}

		clear();

		final head = from < to ? from : to;
		final tail = from < to ? to : from;

		for (index in head...tail + 1) adds(order[index]);
	}

	public function taken():Array<T> {
		return order.copy();
	}
}
