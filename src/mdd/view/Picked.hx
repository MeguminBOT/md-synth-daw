package mdd.view;

@:generic
@:unreflective

/**
	What is selected, whatever it is selected from: notes, clips, points or rows.

	It is one class rather than one per editor, because click, shift click and control
	click have to mean the same thing everywhere or the interface is a guess.
**/
final class Picked<T:{}> {
	/**
		How many things are selected.
	**/
	public var count(get, never):Int;

	final order:Array<T> = [];
	final marks:haxe.ds.ObjectMap<T, Bool> = new haxe.ds.ObjectMap<T, Bool>();

	/**
		Builds an empty selection.
	**/
	public function new() {}

	inline function get_count():Int {
		return order.length;
	}

	/**
		@param item A thing.
		@return Whether it is selected.
	**/
	public inline function holds(item:T):Bool {
		return marks.exists(item);
	}

	/**
		@param index A position in the selection.
		@return What is there.
	**/
	public inline function at(index:Int):T {
		return order[index];
	}

	/**
		@return The last thing added, which is what a shift click ranges from.
	**/
	public function lead():Null<T> {
		return order.length == 0 ? null : order[order.length - 1];
	}

	/**
		Adds one thing.

		@param item The thing.
		@return False where it was already selected.
	**/
	public function adds(item:T):Bool {
		if (marks.exists(item)) return false;

		marks.set(item, true);
		order.push(item);

		return true;
	}

	/**
		Takes one thing out.

		@param item The thing.
		@return False where it was not selected.
	**/
	public function drops(item:T):Bool {
		if (!marks.exists(item)) return false;

		marks.remove(item);
		order.remove(item);

		return true;
	}

	/**
		Adds a thing or takes it out, which is what a control click does.

		@param item The thing.
		@return Whether it is selected now.
	**/
	public function toggles(item:T):Bool {
		if (drops(item)) return false;

		adds(item);
		return true;
	}

	/**
		Selects one thing and nothing else.

		@param item The thing.
	**/
	public function only(item:T):Void {
		clear();
		adds(item);
	}

	/**
		Selects nothing.
	**/
	public function clear():Void {
		if (order.length == 0) return;

		order.resize(0);
		marks.clear();
	}

	/**
		Applies one click: plain selects only what was clicked, control adds or removes
		it, and shift takes everything between the anchor and it.

		@param order Everything selectable, in the order it is laid out.
		@param anchor What a range should start from, or null.
		@param lead What was clicked.
		@param shift Whether shift was held.
		@param ctrl Whether control was held.
	**/
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

	/**
		Selects everything between two things.

		@param order Everything selectable, in the order it is laid out.
		@param anchor One end, or null for the current lead.
		@param lead The other end.
	**/
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

	/**
		@return A copy of the selection, safe to hold while it changes.
	**/
	public function taken():Array<T> {
		return order.copy();
	}
}
