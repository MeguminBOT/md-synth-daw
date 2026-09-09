package mdd.song;

import haxe.ds.Vector;

/**
	One recording for the sample channel: unsigned bytes, the rate they were written
	at, and the note they sound at that rate.
**/
@:unreflective
final class Sample {
	/**
		What it is called.
	**/
	public var name:String;

	/**
		The rate the bytes were written at, in hertz. Taken from the gaps between converter
		writes with real pauses left out, not from the run measured end to end.
	**/
	public var rate:Int;

	/**
		The MIDI note the sample sounds at its own rate.
	**/
	public var root:Int;

	/**
		Which byte to return to, or -1 to play once.
	**/
	public var loop:Int;

	/**
		The samples, unsigned, one byte each, as the converter takes them.
	**/
	public var bytes(default, null):Vector<Int>;

	/**
		Builds an empty sample.

		@param name What to call it.
		@param rate The rate its bytes are written at.
		@param root The MIDI note it sounds at that rate.
	**/
	public function new(name:String, rate:Int = 8000, root:Int = 60) {
		this.name = name;
		this.rate = rate;
		this.root = root;
		this.loop = -1;
		bytes = new Vector<Int>(0);
	}

	/**
		Takes the bytes, without copying them.

		@param bytes The samples, unsigned.
	**/
	public function hold(bytes:Vector<Int>):Void {
		this.bytes = bytes;
	}

	/**
		@return How many bytes it holds.
	**/
	public inline function length():Int {
		return bytes.length;
	}

	/**
		@return A new sample with its own copy of the bytes.
	**/
	public function copy():Sample {
		final out = new Sample(name, rate, root);
		out.loop = loop;

		final held = new Vector<Int>(bytes.length);
		Vector.blit(bytes, 0, held, 0, bytes.length);
		out.hold(held);

		return out;
	}
}
