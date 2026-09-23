package mdd.view.film;

import haxe.ds.Vector;
import mdd.format.Json;
import mdd.format.Node;
import mdd.song.Part;
import mdd.view.monitor.Scope;
import mdd.view.monitor.Windowing;

/**
	How a video looks: what is behind everything, what is placed on it and in what order, and how
	the lanes are drawn.

	`plain` is the look a video had before styles: black, with the lanes filling the picture, each
	named, in its part's colour, with a hairline between them. A style is read from and written to
	a small JSON document, and reading one that is damaged or written by hand gives a style every
	field of which is in range.
**/
@:unreflective
final class Style {
	/**
		Ground: one colour.
	**/
	public static inline final PLAIN = 0;

	/**
		Ground: a gradient from one colour to another.
	**/
	public static inline final GRADIENT = 1;

	/**
		The most layers a style holds.
	**/
	public static inline final LAYERS = 64;

	/**
		What the style is called, or an empty string.
	**/
	public var name:String = "";

	/**
		What the ground is, `PLAIN` or `GRADIENT`.
	**/
	public var ground:Int = PLAIN;

	/**
		The ground's colour, or where its gradient starts, as `0xRRGGBB`.
	**/
	public var groundColour:Int = 0x000000;

	/**
		Where the ground's gradient ends, as `0xRRGGBB`.
	**/
	public var groundTo:Int = 0x000000;

	/**
		Which way the gradient runs, clockwise: nought runs left to right, ninety top to bottom.
	**/
	public var groundTurn:Float = 90;

	/**
		A picture filling the ground over its colour, cropped rather than stretched, or an empty
		string for none.
	**/
	public var groundImage:String = "";

	/**
		How opaque that picture is, from nought to one.
	**/
	public var groundAlpha:Float = 1;

	/**
		What is placed on the ground, drawn in this order, the first underneath. Exactly one of
		them is the lanes.
	**/
	public final layers:Array<Layer> = [];

	/**
		The colour each part's lane is drawn in, by part, or -1 for the part's own.
	**/
	public final colours:Vector<Int> = new Vector<Int>(Part.COUNT);

	/**
		Whether each lane is labelled with its part's name.
	**/
	public var names:Bool = true;

	/**
		Whether a hairline is drawn between lanes.
	**/
	public var grid:Bool = true;

	/**
		How thick a trace is, in the sizes the picture is drawn at.
	**/
	public var weight:Float = 2;

	/**
		The shape a spectrum's samples are weighed by, one of `Windowing`'s.
	**/
	public var windowing:Int = Windowing.NONE;

	/**
		The shape a waveform is smoothed with, one of `Windowing`'s.
	**/
	public var smoothing:Int = Windowing.NONE;

	/**
		How many samples the smoothing spans.
	**/
	public var smoothingWidth:Int = 9;

	/**
		Builds a style with no layers. `plain` is the one to start from.
	**/
	public function new() {
		for (part in 0...Part.COUNT) colours[part] = -1;
	}

	/**
		@return The look a video had before styles: black, the lanes filling the picture.
	**/
	public static function plain():Style {
		final out = new Style();
		out.layers.push(new Layer(Layer.LANES));
		return out;
	}

	/**
		@return The lanes' layer. A style read or built here always has one.
	**/
	public function lanes():Layer {
		for (layer in layers) if (layer.kind == Layer.LANES) return layer;

		final made = new Layer(Layer.LANES);
		layers.unshift(made);

		return made;
	}

	/**
		Sets a scope up to draw its lanes the way this style says.

		@param scope The scope a video or its preview draws with.
	**/
	public function dresses(scope:Scope):Void {
		for (part in 0...Part.COUNT) scope.filmColours[part] = colours[part];

		scope.filmNames = names;
		scope.filmGrid = grid;
		scope.filmWeight = weight;
		scope.windows(windowing);
		scope.smoothsWith(smoothing, smoothingWidth);
	}

	/**
		@return A style holding everything this one does, its layers copied rather than shared.
	**/
	public function copy():Style {
		final out = new Style();

		out.name = name;
		out.ground = ground;
		out.groundColour = groundColour;
		out.groundTo = groundTo;
		out.groundTurn = groundTurn;
		out.groundImage = groundImage;
		out.groundAlpha = groundAlpha;

		for (layer in layers) out.layers.push(layer.copy());
		for (part in 0...Part.COUNT) out.colours[part] = colours[part];

		out.names = names;
		out.grid = grid;
		out.weight = weight;
		out.windowing = windowing;
		out.smoothing = smoothing;
		out.smoothingWidth = smoothingWidth;

		return out;
	}

	/**
		@return The style as a JSON document.
	**/
	public function spelt():String {
		final out = new Json();

		out.open();
		out.key("name");
		out.text(name);

		out.key("ground");
		out.open();
		out.key("kind");
		out.whole(ground);
		out.key("colour");
		out.text(hex(groundColour));
		out.key("to");
		out.text(hex(groundTo));
		out.key("turn");
		out.number(groundTurn);
		out.key("image");
		out.text(groundImage);
		out.key("alpha");
		out.number(groundAlpha);
		out.close();

		out.key("lanes");
		out.open();
		out.key("colours");
		out.list();
		for (part in 0...Part.COUNT) out.text(colours[part] < 0 ? "" : hex(colours[part]));
		out.ends();
		out.key("names");
		out.flag(names);
		out.key("grid");
		out.flag(grid);
		out.key("weight");
		out.number(weight);
		out.key("windowing");
		out.whole(windowing);
		out.key("smoothing");
		out.whole(smoothing);
		out.key("smoothingWidth");
		out.whole(smoothingWidth);
		out.close();

		out.key("layers");
		out.list();

		for (layer in layers) {
			out.open();
			out.key("kind");
			out.whole(layer.kind);
			out.key("x");
			out.number(layer.x);
			out.key("y");
			out.number(layer.y);
			out.key("wide");
			out.number(layer.wide);
			out.key("tall");
			out.number(layer.tall);
			out.key("turn");
			out.number(layer.turn);
			out.key("alpha");
			out.number(layer.alpha);
			out.key("path");
			out.text(layer.path);
			out.close();
		}

		out.ends();
		out.close();

		return out.toString();
	}

	/**
		Reads a style back from its JSON document. Anything missing takes the plain style's
		value, anything out of range is brought into it, and a document with no lanes gets them
		back underneath everything else.

		@param said The document.
		@return The style.
	**/
	public static function read(said:String):Style {
		final out = new Style();
		final node = Json.parse(said);

		out.name = node.get("name").saying("");

		final ground = node.get("ground");
		out.ground = ground.get("kind").whole(PLAIN) == GRADIENT ? GRADIENT : PLAIN;
		out.groundColour = colourOf(ground.get("colour").saying(""), 0x000000);
		out.groundTo = colourOf(ground.get("to").saying(""), 0x000000);
		out.groundTurn = finite(ground.get("turn").real(90), 90) % 360;
		out.groundImage = ground.get("image").saying("");
		out.groundAlpha = clamped(ground.get("alpha").real(1), 0, 1);

		final lanes = node.get("lanes");
		final colours = lanes.get("colours");

		for (part in 0...Part.COUNT) out.colours[part] = colourOf(colours.at(part).saying(""), -1);

		out.names = lanes.get("names").truth(true);
		out.grid = lanes.get("grid").truth(true);
		out.weight = clamped(lanes.get("weight").real(2), 0.5, 16);
		out.windowing = kindOf(lanes.get("windowing").whole(Windowing.NONE));
		out.smoothing = kindOf(lanes.get("smoothing").whole(Windowing.NONE));
		out.smoothingWidth = Windowing.spanned(lanes.get("smoothingWidth").whole(9));

		final layers = node.get("layers");
		var hasLanes = false;

		for (index in 0...layers.length()) {
			if (out.layers.length >= LAYERS) break;

			final held = layers.at(index);
			final kind = held.get("kind").whole(Layer.IMAGE);

			if (kind == Layer.LANES && hasLanes) continue;

			final layer = new Layer(kind);

			layer.x = held.get("x").real(0.5);
			layer.y = held.get("y").real(0.5);
			layer.wide = held.get("wide").real(1);
			layer.tall = held.get("tall").real(1);
			layer.turn = held.get("turn").real(0);
			layer.alpha = held.get("alpha").real(1);
			layer.path = held.get("path").saying("");
			layer.tidied();

			if (layer.kind == Layer.LANES) hasLanes = true;
			out.layers.push(layer);
		}

		if (!hasLanes) out.layers.unshift(new Layer(Layer.LANES));

		return out;
	}

	/**
		@param colour A colour as `0xRRGGBB`.
		@return It as `#RRGGBB`.
	**/
	public static function hex(colour:Int):String {
		return "#" + StringTools.hex(colour & 0xFFFFFF, 6);
	}

	/**
		@param said A colour as `#RRGGBB`, or anything else.
		@param fallback What to answer where it is not one.
		@return The colour as `0xRRGGBB`, or the fallback.
	**/
	public static function colourOf(said:String, fallback:Int):Int {
		if (said.length != 7 || said.charAt(0) != "#") return fallback;

		final value = Std.parseInt("0x" + said.substr(1));
		return value == null ? fallback : value & 0xFFFFFF;
	}

	static inline function kindOf(kind:Int):Int {
		return kind < 0 || kind >= Windowing.KINDS ? Windowing.NONE : kind;
	}

	static inline function finite(value:Float, fallback:Float):Float {
		return Math.isFinite(value) ? value : fallback;
	}

	static inline function clamped(value:Float, low:Float, high:Float):Float {
		return !Math.isFinite(value) ? high : (value < low ? low : (value > high ? high : value));
	}
}
