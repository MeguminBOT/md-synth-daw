package mdd.play;

import haxe.atomic.AtomicInt;
import haxe.ds.Vector;

/**
	A lock free ring of register writes, from the main thread to the render thread.

	One writer and one reader, each owning one end, which is what lets it be lock free.
	A write is packed into a single machine word so the ring can be a `Vector<Int>` and
	nothing has to be allocated to put one in.
**/
@:unreflective
final class Queue {
	/**
		@param kind Which part, `Stream.YM` or `Stream.PSG`.
		@param port The bus port.
		@param value The byte to write.
		@return The three packed into one word.
	**/
	public static inline function packed(kind:Int, port:Int, value:Int):Int {
		return ((kind & 0xFF) << 16) | ((port & 0xFF) << 8) | (value & 0xFF);
	}

	/**
		@param word A packed write.
		@return Which part it is for.
	**/
	public static inline function kindOf(word:Int):Int {
		return (word >> 16) & 0xFF;
	}

	/**
		@param word A packed write.
		@return The bus port it goes to.
	**/
	public static inline function portOf(word:Int):Int {
		return (word >> 8) & 0xFF;
	}

	/**
		@param word A packed write.
		@return The byte it carries.
	**/
	public static inline function valueOf(word:Int):Int {
		return word & 0xFF;
	}

	/**
		How many writes the ring holds. Rounded up to a power of two so the wrap is a mask.
	**/
	public var capacity(default, null):Int;

	/**
		How many writes were refused because the ring was full. Anything but nought means
		the render thread is not draining fast enough, and it is heard as a missed note
		rather than as a glitch.
	**/
	public var dropped(default, null):Int = 0;

	final words:Vector<Int>;
	final mask:Int;
	final head:AtomicInt = new AtomicInt(0);
	final tail:AtomicInt = new AtomicInt(0);

	/**
		Builds a ring.

		@param capacity How many writes it should hold. Rounded up to a power of two.
	**/
	public function new(capacity:Int = 4096) {
		var room = 2;
		while (room < capacity) room = room << 1;

		this.capacity = room;
		mask = room - 1;
		words = new Vector<Int>(room);
	}

	/**
		Adds one write. Called from the main thread only.

		@param kind Which part, `Stream.YM` or `Stream.PSG`.
		@param port The bus port.
		@param value The byte to write.
		@return False where the ring was full, which also counts the write in `dropped`.
	**/
	public function push(kind:Int, port:Int, value:Int):Bool {
		final at = head.load();

		if (at - tail.load() >= capacity) {
			dropped++;
			return false;
		}

		words[at & mask] = packed(kind, port, value);
		head.store(at + 1);
		return true;
	}

	/**
		@return How many writes are in the ring now.
	**/
	public inline function waiting():Int {
		return head.load() - tail.load();
	}

	/**
		Takes the oldest write. Called from the render thread only.

		@return The packed write, or -1 where the ring is empty.
	**/
	public function pull():Int {
		final at = tail.load();
		if (at == head.load()) return -1;

		final word = words[at & mask];
		tail.store(at + 1);
		return word;
	}

	/**
		Throws away everything waiting and forgets the dropped count.
	**/
	public function clear():Void {
		tail.store(head.load());
		dropped = 0;
	}
}
