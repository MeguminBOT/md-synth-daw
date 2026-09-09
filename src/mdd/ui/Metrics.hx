package mdd.ui;

@:unreflective

/**
	Every size the interface draws at, worked out once from one scale.

	A widget never carries a pixel number of its own: it asks here, so changing the
	density or moving to a scaled display moves the whole interface together rather
	than the parts that happened to be written in the right units.
**/
final class Metrics {
	/**
		What every design size is multiplied by.
	**/
	public var scale(default, null):Float;

	/**
		The smallest step anything is spaced by.
	**/
	public var unit(default, null):Float;

	/**
		How far in from an edge content sits.
	**/
	public var inset(default, null):Float;

	/**
		How far apart two things sit.
	**/
	public var gap(default, null):Float;

	/**
		How tall a list row is.
	**/
	public var row(default, null):Float;

	/**
		How tall an ordinary control is.
	**/
	public var control(default, null):Float;

	/**
		How tall a title band is.
	**/
	public var bar(default, null):Float;

	/**
		How tall a tab strip is.
	**/
	public var tab(default, null):Float;

	/**
		How tall a table header is.
	**/
	public var head(default, null):Float;

	/**
		How tall a timeline ruler is.
	**/
	public var ruler(default, null):Float;

	/**
		The corner radius of a small control.
	**/
	public var radiusSmall(default, null):Float;

	/**
		The corner radius of the window.
	**/
	public var radiusWindow(default, null):Float;

	/**
		The corner radius of a row.
	**/
	public var radiusRow(default, null):Float;

	/**
		The corner radius of a panel.
	**/
	public var radiusPanel(default, null):Float;

	/**
		How wide the side rail is.
	**/
	public var rail(default, null):Float;

	/**
		How wide the inspector is.
	**/
	public var inspector(default, null):Float;

	/**
		How tall the status bar is.
	**/
	public var status(default, null):Float;

	/**
		How tall the menu bar is.
	**/
	public var menu(default, null):Float;

	/**
		How tall the transport bar is.
	**/
	public var transport(default, null):Float;

	/**
		The face ordinary text is drawn in.
	**/
	public var body(default, null):Font;

	/**
		The face secondary text is drawn in.
	**/
	public var small(default, null):Font;

	/**
		The face numbers and registers are drawn in.
	**/
	public var mono(default, null):Font;

	/**
		The face headings are drawn in.
	**/
	public var large(default, null):Font;

	/**
		Builds a set of sizes at a scale, with no faces yet.

		@param scale What to multiply every design size by.
	**/
	public function new(scale:Float) {
		wear(scale);
	}

	/**
		Works every size out again at a new scale.

		@param scale The new scale.
	**/
	public function wear(scale:Float):Void {
		this.scale = scale <= 0 ? 1 : scale;

		unit = whole(4);
		inset = whole(12);
		gap = whole(8);
		row = whole(34);
		control = whole(32);
		bar = whole(32);
		tab = whole(34);
		head = whole(26);
		ruler = whole(24);

		radiusSmall = whole(4);
		radiusWindow = whole(6);
		radiusRow = whole(7);
		radiusPanel = whole(10);

		rail = whole(268);
		inspector = whole(332);
		status = whole(26);
		menu = whole(34);
		transport = whole(58);
	}

	/**
		Takes the four faces the interface draws in.

		@param body Ordinary text.
		@param small Secondary text.
		@param mono Numbers and registers.
		@param large Headings.
	**/
	public function dress(body:Font, small:Font, mono:Font, large:Font):Void {
		this.body = body;
		this.small = small;
		this.mono = mono;
		this.large = large;
	}

	/**
		@param design A size in design units.
		@return It scaled and rounded to a whole pixel, which is what a hairline needs so it does
			not vanish.
	**/
	public inline function whole(design:Float):Float {
		final scaled = design * scale;
		final rounded = Math.round(scaled);
		return rounded < 1 && design > 0 ? 1 : rounded;
	}

	/**
		@param design A size in design units.
		@return It scaled, not rounded.
	**/
	public inline function sizeOf(design:Float):Float {
		return design * scale;
	}
}
