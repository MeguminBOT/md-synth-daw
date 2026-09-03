typedef Contour = {
	final points:Array<Float>;
};

typedef Shape = {
	final contours:Array<Contour>;
	final evenOdd:Bool;
	final alpha:Float;
};

class Svg {
	public var width(default, null):Float = 16;
	public var height(default, null):Float = 16;

	public final shapes:Array<Shape> = [];

	static inline final STEPS = 12;

	function new() {}

	public static function read(said:String):Svg {
		final out = new Svg();

		final box = attribute(said, "viewBox");

		if (box != "") {
			final parts = split(box);
			if (parts.length == 4) {
				out.width = parts[2];
				out.height = parts[3];
			}
		}

		var at = 0;

		while (true) {
			final opens = said.indexOf("<path", at);
			if (opens < 0) break;

			var shuts = said.indexOf(">", opens);
			if (shuts < 0) break;

			final tag = said.substring(opens, shuts + 1);
			at = shuts + 1;

			final data = attribute(tag, "d");
			if (data == "") continue;

			final fill = attribute(tag, "fill");
			if (fill == "none") continue;

			final held = attribute(tag, "opacity");
			final rule = attribute(tag, "fill-rule");

			out.shapes.push({
				contours: out.traced(data),
				evenOdd: rule == "evenodd",
				alpha: held == "" ? 1.0 : Std.parseFloat(held)
			});
		}

		return out;
	}

	static function attribute(said:String, name:String):String {
		final key = name + "=\"";
		final at = said.indexOf(key);
		if (at < 0) return "";

		final from = at + key.length;
		final until = said.indexOf("\"", from);

		return until < 0 ? "" : said.substring(from, until);
	}

	static function split(said:String):Array<Float> {
		final out:Array<Float> = [];
		final held = ~/[\s,]+/g.split(StringTools.trim(said));

		for (part in held) if (part != "") out.push(Std.parseFloat(part));

		return out;
	}

	function traced(data:String):Array<Contour> {
		final out:Array<Contour> = [];
		final reader = new Steps(data);

		var points:Array<Float> = [];

		var x = 0.0;
		var y = 0.0;
		var startX = 0.0;
		var startY = 0.0;
		var lastX = 0.0;
		var lastY = 0.0;
		var wasCurve = false;
		var command = "";

		inline function begun():Void {
			if (points.length >= 6) out.push({points: points});
			points = [];
		}

		while (true) {
			final held = reader.next(command);
			if (held == "") break;

			command = held;

			final low = command.toLowerCase();
			final relative = command == low;

			switch (low) {
				case "m":
					begun();

					x = relative ? x + reader.number() : reader.number();
					y = relative ? y + reader.number() : reader.number();

					startX = x;
					startY = y;
					points.push(x);
					points.push(y);
					wasCurve = false;
					command = relative ? "l" : "L";

				case "l":
					x = relative ? x + reader.number() : reader.number();
					y = relative ? y + reader.number() : reader.number();

					points.push(x);
					points.push(y);
					wasCurve = false;

				case "h":
					x = relative ? x + reader.number() : reader.number();

					points.push(x);
					points.push(y);
					wasCurve = false;

				case "v":
					y = relative ? y + reader.number() : reader.number();

					points.push(x);
					points.push(y);
					wasCurve = false;

				case "c", "s":
					var ax = 0.0;
					var ay = 0.0;

					if (low == "c") {
						ax = relative ? x + reader.number() : reader.number();
						ay = relative ? y + reader.number() : reader.number();
					} else {
						ax = wasCurve ? x + (x - lastX) : x;
						ay = wasCurve ? y + (y - lastY) : y;
					}

					final bx = relative ? x + reader.number() : reader.number();
					final by = relative ? y + reader.number() : reader.number();
					final cx = relative ? x + reader.number() : reader.number();
					final cy = relative ? y + reader.number() : reader.number();

					curved(points, x, y, ax, ay, bx, by, cx, cy);

					lastX = bx;
					lastY = by;
					x = cx;
					y = cy;
					wasCurve = true;

				case "z":
					x = startX;
					y = startY;
					begun();
					wasCurve = false;

				case _:
					return out;
			}
		}

		begun();
		return out;
	}

	function curved(into:Array<Float>, x0:Float, y0:Float, x1:Float, y1:Float, x2:Float, y2:Float,
			x3:Float, y3:Float):Void {
		final reach = Math.abs(x1 - x0) + Math.abs(y1 - y0) + Math.abs(x2 - x1)
			+ Math.abs(y2 - y1) + Math.abs(x3 - x2) + Math.abs(y3 - y2);

		var steps = Math.ceil(reach * 2);
		if (steps < 3) steps = 3;
		if (steps > STEPS * 4) steps = STEPS * 4;

		for (step in 1...steps + 1) {
			final t = step / steps;
			final u = 1 - t;

			final a = u * u * u;
			final b = 3 * u * u * t;
			final c = 3 * u * t * t;
			final d = t * t * t;

			into.push(a * x0 + b * x1 + c * x2 + d * x3);
			into.push(a * y0 + b * y1 + c * y2 + d * y3);
		}
	}
}

private class Steps {
	final said:String;
	var at:Int = 0;

	public function new(said:String) {
		this.said = said;
	}

	public function next(repeat:String):String {
		skip();
		if (at >= said.length) return "";

		final code = said.charCodeAt(at);

		if ((code >= 'A'.code && code <= 'Z'.code) || (code >= 'a'.code && code <= 'z'.code)) {
			at++;
			return said.charAt(at - 1);
		}

		return repeat;
	}

	public function number():Float {
		skip();

		final from = at;
		var seen = false;

		if (at < said.length) {
			final sign = said.charCodeAt(at);
			if (sign == '-'.code || sign == '+'.code) at++;
		}

		while (at < said.length) {
			final code = said.charCodeAt(at);

			if (code >= '0'.code && code <= '9'.code) {
				at++;
				seen = true;
				continue;
			}

			if (code == '.'.code) {
				at++;
				continue;
			}

			if ((code == 'e'.code || code == 'E'.code) && seen) {
				at++;
				if (at < said.length) {
					final sign = said.charCodeAt(at);
					if (sign == '-'.code || sign == '+'.code) at++;
				}
				continue;
			}

			break;
		}

		return at == from ? 0 : Std.parseFloat(said.substring(from, at));
	}

	function skip():Void {
		while (at < said.length) {
			final code = said.charCodeAt(at);
			if (code != ' '.code && code != ','.code && code != '\n'.code && code != '\r'.code
				&& code != '\t'.code) break;

			at++;
		}
	}
}
