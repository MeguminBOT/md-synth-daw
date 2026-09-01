package mdd.ui;

@:unreflective
final class Metrics {
	public var scale(default, null):Float;

	public var unit(default, null):Float;
	public var inset(default, null):Float;
	public var gap(default, null):Float;
	public var row(default, null):Float;
	public var control(default, null):Float;
	public var bar(default, null):Float;
	public var tab(default, null):Float;

	public var radiusSmall(default, null):Float;
	public var radiusWindow(default, null):Float;
	public var radiusRow(default, null):Float;
	public var radiusPanel(default, null):Float;

	public var rail(default, null):Float;
	public var inspector(default, null):Float;
	public var dock(default, null):Float;
	public var menu(default, null):Float;
	public var transport(default, null):Float;

	public var body(default, null):Font;
	public var small(default, null):Font;
	public var mono(default, null):Font;
	public var large(default, null):Font;

	public function new(scale:Float) {
		wear(scale);
	}

	public function wear(scale:Float):Void {
		this.scale = scale <= 0 ? 1 : scale;

		unit = whole(4);
		inset = whole(12);
		gap = whole(8);
		row = whole(30);
		control = whole(30);
		bar = whole(29);
		tab = whole(30);

		radiusSmall = whole(4);
		radiusWindow = whole(6);
		radiusRow = whole(7);
		radiusPanel = whole(10);

		rail = whole(250);
		inspector = whole(314);
		dock = whole(132);
		menu = whole(30);
		transport = whole(52);
	}

	public function dress(body:Font, small:Font, mono:Font, large:Font):Void {
		this.body = body;
		this.small = small;
		this.mono = mono;
		this.large = large;
	}

	public inline function whole(design:Float):Float {
		final scaled = design * scale;
		final rounded = Math.round(scaled);
		return rounded < 1 && design > 0 ? 1 : rounded;
	}

	public inline function sizeOf(design:Float):Float {
		return design * scale;
	}
}
