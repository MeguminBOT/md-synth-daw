package mdd.format;

import mdd.song.Sample;

@:unreflective

/**
	One recording on its way into a kit: where it came from, what it will be called,
	which key it will sit on, and what was measured about it.

	The measurements are here because a name that says what a hit is, is not evidence of
	which one it is. A kit downloaded from anywhere can have its open and closed hats the
	wrong way round, and its toms numbered in an order that has nothing to do with their
	pitch. What a hit is can be read from the sound, and `Kit.detects` does. A name that
	spells a note is different: it says where the hit goes, and is taken at its word.
**/
final class Slot {
	/**
		The file it was read from.
	**/
	public final path:String;

	/**
		What the hit will be called in the bank.
	**/
	public var name:String;

	/**
		Which key it sits on, or -1 until one is worked out.
	**/
	public var root:Int = -1;

	/**
		Which icon it carries, or -1 for none.
	**/
	public var icon:Int = -1;

	/**
		Whether it goes into the kit at all.
	**/
	public var taken:Bool = true;

	/**
		The rate this hit is converted at, or nought to take the kit's.
	**/
	public var rate:Int = 0;

	/**
		The longest this hit may be, in seconds, or nought for as long as it is.
	**/
	public var cap:Float = 0;

	/**
		The rate the recording is at.
	**/
	public var was:Int = 0;

	/**
		How long the recording is, in seconds.
	**/
	public var seconds:Float = 0;

	/**
		Where the hit sits, in hertz, from the first quarter second of it. Nought where
		nothing was measured.
	**/
	public var pitch:Float = 0;

	/**
		How long it takes to fall thirty decibels, in seconds, which is what separates a
		hat that chokes from one that rings.
	**/
	public var rings:Float = 0;

	/**
		How loud the recording is at its loudest, from nought to one.
	**/
	public var peak:Float = 0;

	/**
		What it became, or null until it is converted.
	**/
	public var made:Null<Sample> = null;

	/**
		Builds a slot for a file, with nothing measured yet.

		@param path The file.
		@param name What to call it.
	**/
	public function new(path:String, name:String) {
		this.path = path;
		this.name = name;
	}

	/**
		@return How many bytes it comes to, or nought where it has not been converted or
			is not being taken.
	**/
	public function bytes():Int {
		final held = made;
		return !taken || held == null ? 0 : held.length();
	}
}
