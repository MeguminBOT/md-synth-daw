package mdd.check;

import haxe.ds.Vector;
import mdd.song.Part;

@:unreflective
final class Profile {
	public var name(default, null):String;

	public final has:Vector<Bool> = new Vector<Bool>(Part.COUNT);

	public var fm3Special:Bool = true;
	public var lowestSquare:Int = 45;
	public var highestSquare:Int = 127;
	public var lowestFm:Int = 12;
	public var highestFm:Int = 107;
	public var sampleBytes:Int = 262144;
	public var perFrame:Int = 0;

	public function new(name:String) {
		this.name = name;
		for (i in 0...Part.COUNT) has[i] = false;
	}

	public inline function carries(part:Part):Bool {
		return has[part.index()];
	}

	public function counted():Int {
		var many = 0;
		for (i in 0...Part.COUNT) if (has[i]) many++;
		return many;
	}

	public function voices():Int {
		var many = 0;
		for (i in 0...6) if (has[i]) many++;
		return many;
	}

	public static function megaDrive():Profile {
		final profile = new Profile("Mega Drive");
		for (i in 0...Part.COUNT) profile.has[i] = true;

		profile.perFrame = mdd.play.Driver.PER_FRAME;
		return profile;
	}

	public static function masterSystem():Profile {
		final profile = new Profile("Master System");

		for (i in 6...10) profile.has[i] = true;
		profile.fm3Special = false;
		profile.sampleBytes = 0;

		return profile;
	}

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

	public function keyed(select:Int):Bool {
		final within = select & 3;
		if (within == 3) return false;

		final index = within + ((select & 4) != 0 ? 3 : 0);
		return carries(index);
	}
}
