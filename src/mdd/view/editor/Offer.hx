package mdd.view.editor;

import mdd.song.Instrument;
import mdd.song.Sample;

@:unreflective

/**
	One preset the browser offers, and where it is offered from: a bank of the library, or the
	piece's own. The browser keeps a pool of these and fills them again each time it builds its
	rows, so a keystroke in the search allocates none.
**/
final class Offer {
	/**
		Where it comes from: the bank the application is built with.
	**/
	public static inline final DEFAULT = 0;

	/**
		Where it comes from: a bank that ships beside the application.
	**/
	public static inline final SHIPPED = 1;

	/**
		Where it comes from: the reader's presets folder.
	**/
	public static inline final MINE = 2;

	/**
		Where it comes from: the piece that is open, which carries it because it plays it.
	**/
	public static inline final PROJECT = 3;

	/**
		The preset.
	**/
	public var preset:Instrument;

	/**
		What it plays, for a converter preset, or null.
	**/
	public var sample:Null<Sample> = null;

	/**
		The bank it is listed under.
	**/
	public var bank:String = "";

	/**
		Where it comes from, `DEFAULT` to `PROJECT`.
	**/
	public var source:Int = DEFAULT;

	/**
		The preset by index into the piece, for one the piece carries, or -1.
	**/
	public var index:Int = -1;

	/**
		The bank it sits in by position in the library, for one the library holds, or -1.
	**/
	public var shelf:Int = -1;

	/**
		Where it was gathered, which is the order its bank lists it in.
	**/
	public var order:Int = 0;

	/**
		When it was added, in seconds since 1970, or nought for one that ships.
	**/
	public var time:Float = 0;

	/**
		How alike it is to what the chosen part plays, as a fraction of one, worked out once a build
		rather than once a comparison.
	**/
	public var alike:Float = 0;

	/**
		Whether this build has counted it already, since a preset can sit in several groups.
	**/
	public var counted:Bool = false;

	/**
		Builds one.

		@param preset The preset.
	**/
	public function new(preset:Instrument) {
		this.preset = preset;
	}

	/**
		Fills it in again.

		@param preset The preset.
		@param sample What it plays, or null.
		@param bank The bank it is listed under.
		@param source Where it comes from.
		@param index Its index into the piece, or -1.
		@param shelf Its bank's position in the library, or -1.
	**/
	public function holds(preset:Instrument, sample:Null<Sample>, bank:String, source:Int, index:Int,
			shelf:Int):Void {
		this.preset = preset;
		this.sample = sample;
		this.bank = bank;
		this.source = source;
		this.index = index;
		this.shelf = shelf;

		order = 0;
		time = 0;
		alike = 0;
		counted = false;
	}

	/**
		@return Whether the piece carries it, which is what an edit to it changes.
	**/
	public inline function owned():Bool {
		return source == PROJECT;
	}
}
