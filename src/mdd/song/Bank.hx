package mdd.song;

@:unreflective
final class Bank {
	public var name:String;
	public var kept:Bool;

	public final instruments:Array<Int> = [];

	public function new(name:String, kept:Bool = true) {
		this.name = name;
		this.kept = kept;
	}

	public function add(index:Int):Void {
		if (instruments.indexOf(index) >= 0) return;
		instruments.push(index);
	}

	public function remove(index:Int):Bool {
		return instruments.remove(index);
	}

	public inline function holds(index:Int):Bool {
		return instruments.indexOf(index) >= 0;
	}
}
