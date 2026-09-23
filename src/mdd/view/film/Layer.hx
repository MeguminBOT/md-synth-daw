package mdd.view.film;

/**
	One thing placed on a video's picture: the lanes, one part's lane placed on its own, a picture
	read from a file, or a line of text.

	Where it sits is measured in the picture rather than in pixels, so a style drawn at 720 and at
	2160 puts everything in the same place: the centre and the size are fractions of the picture's
	width and height, and the turn is about the centre. A line of text is as tall as `tall` says
	and as wide as what it says makes it, so its `wide` is not read.
**/
@:unreflective
final class Layer {
	/**
		Kind: the scope's lanes, laid out together in a grid, every part that has no `LANE` of its
		own. A style has exactly one.
	**/
	public static inline final LANES = 0;

	/**
		Kind: a picture read from a file.
	**/
	public static inline final IMAGE = 1;

	/**
		Kind: a line of text, with placeholders `Words` fills in.
	**/
	public static inline final TEXT = 2;

	/**
		Kind: one part's lane, placed on its own rather than with the rest. A style has at most one
		for each part.
	**/
	public static inline final LANE = 3;

	/**
		How many kinds there are.
	**/
	public static inline final KINDS = 4;

	/**
		The thickest a text border may be, as a fraction of the text's height.
	**/
	public static inline final THICKEST = 0.25;

	/**
		The smallest a layer may be, as a fraction of the picture, so one can always be grabbed.
	**/
	public static inline final LEAST = 0.02;

	/**
		The largest, so one cannot be asked for a texture wider than any renderer makes.
	**/
	public static inline final MOST = 4;

	/**
		Which kind it is, `LANES` or `IMAGE`.
	**/
	public var kind:Int;

	/**
		Where its centre is, across, from nought at the left edge to one at the right.
	**/
	public var x:Float = 0.5;

	/**
		Where its centre is, down, from nought at the top to one at the bottom.
	**/
	public var y:Float = 0.5;

	/**
		How wide it is, as a fraction of the picture's width.
	**/
	public var wide:Float = 1;

	/**
		How tall it is, as a fraction of the picture's height.
	**/
	public var tall:Float = 1;

	/**
		How far it is turned about its centre, clockwise, in degrees.
	**/
	public var turn:Float = 0;

	/**
		How opaque it is, from nought to one.
	**/
	public var alpha:Float = 1;

	/**
		The picture's file, for an `IMAGE`, or an empty string.
	**/
	public var path:String = "";

	/**
		The part a `LANE` shows, by index.
	**/
	public var part:Int = 0;

	/**
		What a `TEXT` says, placeholders and all.
	**/
	public var text:String = "";

	/**
		The font file a `TEXT` is written in, or an empty string for the interface's own face.
		One that will not read is written in the interface's face too.
	**/
	public var font:String = "";

	/**
		The colour a `TEXT` is filled with, as `0xRRGGBB`.
	**/
	public var colour:Int = 0xFFFFFF;

	/**
		The colour of a `TEXT`'s border, as `0xRRGGBB`.
	**/
	public var border:Int = 0x000000;

	/**
		How thick a `TEXT`'s border is, as a fraction of its height, or nought for none.
	**/
	public var borderWidth:Float = 0;

	/**
		Builds a layer of a kind, centred and filling the picture.

		@param kind `LANES`, `IMAGE` or `TEXT`.
	**/
	public function new(kind:Int) {
		this.kind = kind < 0 || kind >= KINDS ? IMAGE : kind;
	}

	/**
		@return A layer holding everything this one does.
	**/
	public function copy():Layer {
		final out = new Layer(kind);

		out.x = x;
		out.y = y;
		out.wide = wide;
		out.tall = tall;
		out.turn = turn;
		out.alpha = alpha;
		out.path = path;
		out.part = part;
		out.text = text;
		out.font = font;
		out.colour = colour;
		out.border = border;
		out.borderWidth = borderWidth;

		return out;
	}

	/**
		Brings every field into the range it may hold: a size between `LEAST` and `MOST`, an
		opacity between nought and one, a turn from nought up to one revolution, a centre no
		further off the picture than it could be dragged, and a border no thicker than
		`THICKEST`.
	**/
	public function tidied():Void {
		wide = within(wide, LEAST, MOST, 1);
		tall = within(tall, LEAST, MOST, 1);
		alpha = within(alpha, 0, 1, 1);
		borderWidth = within(borderWidth, 0, THICKEST, 0);
		part = part < 0 || part >= mdd.song.Part.COUNT ? 0 : part;
		colour &= 0xFFFFFF;
		border &= 0xFFFFFF;
		x = within(x, -MOST, MOST + 1, 0.5);
		y = within(y, -MOST, MOST + 1, 0.5);
		turn = Math.isFinite(turn) ? (turn % 360 + 360) % 360 : 0;
	}

	static inline function within(value:Float, low:Float, high:Float, fallback:Float):Float {
		return !Math.isFinite(value) ? fallback : (value < low ? low : (value > high ? high : value));
	}
}
