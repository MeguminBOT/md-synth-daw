package mdd.song;

import haxe.ds.Vector;

@:unreflective
final class Pattern {
	public var name:String;
	public var colour:Int;
	public var length:Int;
	public var part:Int = -1;

	public final lanes:Vector<Lane> = new Vector<Lane>(Part.COUNT);

	public function new(name:String, length:Int, colour:Int = -1) {
		this.name = name;
		this.length = length;
		this.colour = colour;

		for (i in 0...Part.COUNT) lanes[i] = new Lane(i);
	}

	public inline function lane(part:Part):Lane {
		return lanes[part.index()];
	}

	public function notes():Int {
		var total = 0;
		for (i in 0...Part.COUNT) total += lanes[i].notes.length;
		return total;
	}

	public function used(part:Part):Bool {
		return lanes[part.index()].notes.length > 0;
	}

	public function longest():Int {
		var most = 0;
		for (i in 0...Part.COUNT) {
			final ends = lanes[i].longest();
			if (ends > most) most = ends;
		}
		return most;
	}
}
