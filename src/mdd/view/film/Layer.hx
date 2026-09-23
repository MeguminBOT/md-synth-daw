package mdd.view.film;

/**
	One thing placed on a video's picture: the lanes, or a picture read from a file.

	Where it sits is measured in the picture rather than in pixels, so a style drawn at 720 and at
	2160 puts everything in the same place: the centre and the size are fractions of the picture's
	width and height, and the turn is about the centre.
**/
@:unreflective
final class Layer {
	/**
		Kind: the scope's lanes. A style has exactly one.
	**/
	public static inline final LANES = 0;

	/**
		Kind: a picture read from a file.
	**/
	public static inline final IMAGE = 1;

	/**
		How many kinds there are.
	**/
	public static inline final KINDS = 2;

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
		Builds a layer of a kind, centred and filling the picture.

		@param kind `LANES` or `IMAGE`.
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

		return out;
	}

	/**
		Brings every field into the range it may hold: a size between `LEAST` and `MOST`, an
		opacity between nought and one, a turn within one revolution, and a centre no further off
		the picture than it could be dragged.
	**/
	public function tidied():Void {
		wide = within(wide, LEAST, MOST, 1);
		tall = within(tall, LEAST, MOST, 1);
		alpha = within(alpha, 0, 1, 1);
		x = within(x, -MOST, MOST + 1, 0.5);
		y = within(y, -MOST, MOST + 1, 0.5);
		turn = Math.isFinite(turn) ? turn % 360 : 0;
	}

	static inline function within(value:Float, low:Float, high:Float, fallback:Float):Float {
		return !Math.isFinite(value) ? fallback : (value < low ? low : (value > high ? high : value));
	}
}
