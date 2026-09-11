package mdd.check;

import haxe.ds.Vector;
import mdd.song.Part;

@:unreflective

/**
	What one machine actually has: which parts, what they can reach, and how much a
	driver can write in a frame.

	Two ship, the Mega Drive and the Master System, because the square part is the same
	one in both. Everything that decides whether a note is possible reads this rather
	than assuming the console the application is named for.
**/
final class Profile {
	/**
		What the machine is called.
	**/
	public var name(default, null):String;

	/**
		Which parts this machine carries.
	**/
	public final has:Vector<Bool> = new Vector<Bool>(Part.COUNT);

	var fm3Special:Bool = true;

	/**
		The lowest note a square channel can reach, below which the period overflows.
	**/
	public var lowestSquare:Int = 45;
	var highestSquare:Int = 127;

	/**
		The lowest note an FM channel can reach.
	**/
	public var lowestFm:Int = 12;

	/**
		The highest.
	**/
	public var highestFm:Int = 107;

	/**
		How many bytes of samples the author has set aside, or nought for no limit.

		There is no hardware number to put here. The converter takes one byte at a
		time and one sample sounds at a time, so a figure in bytes is storage rather
		than anything the part limits, and how much storage there is depends on what
		the piece is exported as: nothing at all for a render, no bank at all for a
		VGM, an XGM's own table for an XGM, and whatever a cartridge was given for a
		cartridge.

		`ROM` is the convention it starts at rather than a fact, and
		`docs/notes/ym2612.md` records both that and the measurements behind it.
	**/
	public var sampleBytes:Int = ROM;

	/**
		A quarter of a one megabyte cartridge, which is what a piece is held to until
		an author says what their own cartridge sets aside. It is a convention rather
		than a limit of the machine, and it is stated here so that nobody has to guess
		what it was meant to be.
	**/
	public static inline final ROM = 262144;

	/**
		How many register writes a driver can make in one frame, or nought for no limit.
	**/
	public var perFrame:Int = 0;

	/**
		Builds a profile with no parts. Use `megaDrive` or `masterSystem`.

		@param name What to call the machine.
	**/
	public function new(name:String) {
		this.name = name;
		for (i in 0...Part.COUNT) has[i] = false;
	}

	/**
		@param part A part.
		@return Whether this machine has it.
	**/
	public inline function carries(part:Part):Bool {
		return has[part.index()];
	}

	/**
		@return How many parts it has.
	**/
	public function counted():Int {
		var many = 0;
		for (i in 0...Part.COUNT) if (has[i]) many++;
		return many;
	}

	/**
		@return How many notes can sound at once across every part.
	**/
	public function voices():Int {
		var many = 0;
		for (i in 0...6) if (has[i]) many++;
		return many;
	}

	/**
		@return The Mega Drive: six FM channels, three squares, the noise and the sample channel.
	**/
	public static function megaDrive():Profile {
		final profile = new Profile("Mega Drive");
		for (i in 0...Part.COUNT) profile.has[i] = true;

		profile.perFrame = mdd.play.Driver.PER_FRAME;
		return profile;
	}

	/**
		@return The Master System: the same square part and nothing else.
	**/
	public static function masterSystem():Profile {
		final profile = new Profile("Master System");

		for (i in 6...10) profile.has[i] = true;
		profile.fm3Special = false;
		profile.sampleBytes = 0;

		return profile;
	}

	/**
		@param half Which half of the FM register file.
		@param at The register address within it.
		@return Whether this machine has the channel that register belongs to.
	**/
	public function holds(half:Int, at:Int):Bool {
		if (at < 0x20) return false;

		if (half == 0 && at < 0x30) {
			return switch (at) {
				case 0x22, 0x24, 0x25, 0x26, 0x27, 0x28: carries(Part.Fm1);
				case 0x2A, 0x2B: carries(Part.Dac);
				case _: false;
			}
		}

		if (at >= 0x30 && at < 0xA0) {
			if ((at & 3) == 3) return false;
			return carries(half * 3 + (at & 3));
		}

		if (at >= 0xA8 && at <= 0xAE && half == 0) return fm3Special && carries(Part.Fm3);

		if (at >= 0xA0 && at < 0xB8) {
			if ((at & 3) == 3) return false;
			return carries(half * 3 + (at & 3));
		}

		return false;
	}

	/**
		@param select A byte written to the key on register.
		@return Whether it names a channel this machine has.
	**/
	public function keyed(select:Int):Bool {
		final within = select & 3;
		if (within == 3) return false;

		final index = within + ((select & 4) != 0 ? 3 : 0);
		return carries(index);
	}
}
