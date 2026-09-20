package mdd.format;

import mdd.song.Instrument;
import mdd.song.Sample;

/**
	A bank of presets as one file holds it: what the bank is called, the presets in it, and the
	recording each converter preset plays, in the same order.

	A bank with no name of its own is a reader's own presets sitting loose in a folder, which the
	folder names instead.
**/
@:unreflective
final class Banked {
	/**
		What the bank is called, or an empty string where the file names none.
	**/
	public var name:String = "";

	/**
		The presets it holds.
	**/
	public final presets:Array<Instrument> = [];

	/**
		What each of them plays, by the same index, or null where it plays no recording.
	**/
	public final samples:Array<Null<Sample>> = [];

	public function new() {}

	/**
		Puts a preset in.

		@param instrument The preset.
		@param sample The recording it plays, or null.
	**/
	public function add(instrument:Instrument, sample:Null<Sample>):Void {
		presets.push(instrument);
		samples.push(sample);
	}
}
