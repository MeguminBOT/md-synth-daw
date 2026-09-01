package mdd.play;

import haxe.atomic.AtomicInt;
import haxe.ds.Vector;

@:unreflective
final class Queue {
	public static inline final YM = 0;
	public static inline final PSG = 1;

	public static inline function packed(kind:Int, port:Int, value:Int):Int {
		return ((kind & 0xFF) << 16) | ((port & 0xFF) << 8) | (value & 0xFF);
	}

	public static inline function kindOf(word:Int):Int {
		return (word >> 16) & 0xFF;
	}

	public static inline function portOf(word:Int):Int {
		return (word >> 8) & 0xFF;
	}

	public static inline function valueOf(word:Int):Int {
		return word & 0xFF;
	}

	public var capacity(default, null):Int;
	public var dropped(default, null):Int = 0;

	final words:Vector<Int>;
	final mask:Int;
	final head:AtomicInt = new AtomicInt(0);
	final tail:AtomicInt = new AtomicInt(0);

	public function new(capacity:Int = 4096) {
		var room = 2;
		while (room < capacity) room = room << 1;

		this.capacity = room;
		mask = room - 1;
		words = new Vector<Int>(room);
	}

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

	public inline function waiting():Int {
		return head.load() - tail.load();
	}

	public function pull():Int {
		final at = tail.load();
		if (at == head.load()) return -1;

		final word = words[at & mask];
		tail.store(at + 1);
		return word;
	}

	public function clear():Void {
		tail.store(head.load());
		dropped = 0;
	}
}
