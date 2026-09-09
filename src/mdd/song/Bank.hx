package mdd.song;

/**
	A named group of instruments, by index into the song's own list.

	A bank holds indices rather than instruments so two banks can offer the same
	instrument without either owning it.
**/
@:unreflective
final class Bank {
	/**
		What the bank is called.
	**/
	public var name:String;

	/**
		Whether it is saved with the song. A bank built from the shipped library is not.
	**/
	public var kept:Bool;

	/**
		Which instruments are in it, by index into the song.
	**/
	public final instruments:Array<Int> = [];

	/**
		Builds an empty bank.

		@param name What to call it.
		@param kept Whether it is saved with the song.
	**/
	public function new(name:String, kept:Bool = true) {
		this.name = name;
		this.kept = kept;
	}

	/**
		Puts an instrument in, unless it is already there.

		@param index The instrument, by index into the song.
	**/
	public function add(index:Int):Void {
		if (instruments.indexOf(index) >= 0) return;
		instruments.push(index);
	}

	/**
		Takes an instrument out.

		@param index The instrument, by index into the song.
		@return False where it was not in this bank.
	**/
	public function remove(index:Int):Bool {
		return instruments.remove(index);
	}

	/**
		@param index The instrument, by index into the song.
		@return Whether it is in this bank.
	**/
	public inline function holds(index:Int):Bool {
		return instruments.indexOf(index) >= 0;
	}
}
