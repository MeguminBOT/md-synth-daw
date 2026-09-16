package mdd.host;

@:unreflective

/**
	An integer that more than one thread reads and writes, each change made in one step that
	no other thread sees halfway.

	**`haxe.atomic.AtomicInt` is not safe to keep in a field on hxcpp.** It is a bare pointer
	into a one element array that nothing else refers to, and the collector does not mark a
	pointer, so the array is freed at the first collection that finds it unreferenced and its
	memory handed to the next allocation. From then on a load reads whatever was written
	there and a store writes into another object. 256 of them, churned through 800000
	allocations and 40 collections, came back with one changed from 106 to 2, on every run.
	The updater keeps its state in one, so an updater that was idle could read as waiting
	for an answer and raise the notice with no release behind it.

	The value here lives in a vector held by a field, which the collector does mark, and it
	never moves, because the collector does not move objects. Every operation is inline and
	allocates nothing, so it is as safe on the render thread as what it replaces.
**/
final class Atomic {
	final room:haxe.ds.Vector<Int>;

	/**
		@param value What it holds to begin with.
	**/
	public function new(value:Int) {
		room = new haxe.ds.Vector<Int>(1);
		room[0] = value;
	}

	/**
		@return What it holds now.
	**/
	public inline function load():Int {
		return untyped __cpp__("_hx_atomic_load(({0})->Pointer())", room);
	}

	/**
		@param value What it holds from now on.
		@return The value stored.
	**/
	public inline function store(value:Int):Int {
		return untyped __cpp__("_hx_atomic_store(({0})->Pointer(), {1})", room, value);
	}

	/**
		@param by How much to add, which may be negative.
		@return What it held before the addition, which is what `haxe.atomic.AtomicInt` answers
			too.
	**/
	public inline function add(by:Int):Int {
		return untyped __cpp__("_hx_atomic_add(({0})->Pointer(), {1})", room, by);
	}

	/**
		@param value What it holds from now on.
		@return What it held before, read and replaced in the one step.
	**/
	public inline function exchange(value:Int):Int {
		return untyped __cpp__("_hx_atomic_exchange(({0})->Pointer(), {1})", room, value);
	}
}
