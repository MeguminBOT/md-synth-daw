package mdd.song;

import haxe.ds.Vector;

@:unreflective
final class Sample {
	public var name:String;
	public var rate:Int;
	public var root:Int;
	public var loop:Int;

	public var bytes(default, null):Vector<Int>;

	public function new(name:String, rate:Int = 8000, root:Int = 60) {
		this.name = name;
		this.rate = rate;
		this.root = root;
		this.loop = -1;
		bytes = new Vector<Int>(0);
	}

	public function hold(bytes:Vector<Int>):Void {
		this.bytes = bytes;
	}

	public inline function length():Int {
		return bytes.length;
	}

	public function copy():Sample {
		final out = new Sample(name, rate, root);
		out.loop = loop;

		final held = new Vector<Int>(bytes.length);
		Vector.blit(bytes, 0, held, 0, bytes.length);
		out.hold(held);

		return out;
	}
}
