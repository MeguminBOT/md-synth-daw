package mdd.ui;

@:unreflective

/**
	The whole window: the menu bar, the transport, the side rail, the centre, the
	inspector and the status bar, and the seams between them.

	Each zone can be opened and closed and the seams dragged, and what that leaves is
	kept as a share of the window rather than a number of pixels, so resizing keeps the
	proportions the reader chose.
**/
final class Shell extends Widget {
	/**
		Zone: the menu bar across the top.
	**/
	public static inline final MENU = 0;

	/**
		Zone: the transport bar under it.
	**/
	public static inline final TRANSPORT = 1;

	/**
		Zone: the rail down the left.
	**/
	public static inline final RAIL = 2;

	/**
		Zone: the working area.
	**/
	public static inline final CENTRE = 3;

	/**
		Zone: the inspector down the right.
	**/
	public static inline final INSPECTOR = 4;

	/**
		Zone: the status bar along the bottom.
	**/
	public static inline final STATUS = 5;

	/**
		How many zones there are.
	**/
	public static inline final ZONES = 6;

	var railWide:Float = 0;
	var inspectorWide:Float = 0;

	var railOpen:Bool = true;
	var inspectorOpen:Bool = true;

	final railSize:Motion;
	final inspectorSize:Motion;

	final zones:Array<Widget> = [];

	/**
		Which seam is being dragged, or -1 for none.
	**/
	public var dragging(default, null):Int = -1;

	var grabAt:Float = 0;
	var grabSize:Float = 0;

	/**
		Builds a shell with an empty widget in every zone.
	**/
	public function new() {
		super();

		railSize = new Motion(this, 0, true, true);
		inspectorSize = new Motion(this, 0, true, true);

		for (i in 0...ZONES) {
			final zone = new Widget();
			zones.push(zone);
			add(zone);
		}
	}

	/**
		@param which A zone.
		@return The widget in it, to put contents inside.
	**/
	public function zone(which:Int):Widget {
		return zones[which];
	}

	/**
		Takes the fixed heights of the bars from the metrics.

		@param metrics The sizes to lay out at.
	**/
	public function fit(metrics:Metrics):Void {
		railWide = metrics.rail;
		inspectorWide = metrics.inspector;

		railSize.hold(railOpen ? railWide : strip(metrics));
		inspectorSize.hold(inspectorOpen ? inspectorWide : strip(metrics));
	}

	/**
		@param metrics The sizes to lay out at.
		@return How wide a seam is.
	**/
	static inline function strip(metrics:Metrics):Float {
		return metrics.whole(24);
	}

	/**
		@param which A zone.
		@return Whether it is open.
	**/
	public inline function openAt(which:Int):Bool {
		return switch (which) {
			case RAIL: railOpen;
			case INSPECTOR: inspectorOpen;
			case _: true;
		}
	}

	/**
		Opens or closes a zone, animating it.

		@param which A zone.
		@param on Whether it should be open.
	**/
	public function open(which:Int, on:Bool):Void {
		final root = root();
		if (root == null || openAt(which) == on) return;

		final metrics = root.metrics;
		if (railWide <= 0) fit(metrics);

		switch (which) {
			case RAIL:
				railOpen = on;
				root.start(railSize, on ? railWide : strip(metrics), Motion.ENTER);

			case INSPECTOR:
				inspectorOpen = on;
				root.start(inspectorSize, on ? inspectorWide : strip(metrics), Motion.ENTER);

			case _:
				return;
		}

		relayout();
	}

	/**
		@param which A zone.
		@return How much of the window it takes, 0 to 1.
	**/
	public function share(which:Int):Float {
		final root = root();
		if (root == null) return 1;

		final least = strip(root.metrics);

		return switch (which) {
			case RAIL: reach(railSize.value, least, railWide);
			case INSPECTOR: reach(inspectorSize.value, least, inspectorWide);
			case _: 1;
		}
	}

	/**
		@param value A number.
		@param least The floor.
		@param most The ceiling.
		@return It held between the two.
	**/
	static function reach(value:Float, least:Float, most:Float):Float {
		if (most <= least) return 1;

		final part = (value - least) / (most - least);
		return part < 0 ? 0 : (part > 1 ? 1 : part);
	}

	/**
		Places every zone from the fixed heights and the shares.
	**/
	override function layout():Void {
		final root = root();
		if (root == null) return;

		final metrics = root.metrics;
		if (railWide <= 0) fit(metrics);

		final menuTall = metrics.menu;
		final transportTall = metrics.transport;

		final rail = railSize.value;
		final inspector = inspectorSize.value;
		final dock = metrics.status;

		final hair = metrics.whole(1);

		final bodyTop = y + menuTall + hair + transportTall + hair;
		var bodyTall = height - menuTall - transportTall - dock - hair * 3;
		if (bodyTall < 0) bodyTall = 0;

		var centreWide = width - rail - inspector - hair * 2;
		if (centreWide < 0) centreWide = 0;

		zones[MENU].arrange(x, y, width, menuTall);
		zones[TRANSPORT].arrange(x, y + menuTall + hair, width, transportTall);
		zones[RAIL].arrange(x, bodyTop, rail, bodyTall);
		zones[CENTRE].arrange(x + rail + hair, bodyTop, centreWide, bodyTall);
		zones[INSPECTOR].arrange(x + rail + hair + centreWide + hair, bodyTop, inspector,
			bodyTall);
		zones[STATUS].arrange(x, bodyTop + bodyTall + hair, width, dock);
	}

	/**
		Where a seam sits.

		`STATUS` is here to be drawn rather than to be dragged. The status bar is one line
		of text at a height the metrics fix, so there is nothing for a drag to give it, and
		`nearDivider` leaving it out is the answer rather than an omission.

		@param which A seam.
		@return Where it sits, or -1 for anything that is not a seam.
	**/
	public function divider(which:Int):Float {
		final root = root();
		final hair = root == null ? 1 : root.metrics.whole(1);

		final rail = zones[RAIL];
		final inspector = zones[INSPECTOR];
		final dock = zones[STATUS];

		return switch (which) {
			case RAIL: rail.x + rail.width;
			case INSPECTOR: inspector.x - hair;
			case STATUS: dock.y - hair;
			case _: -1;
		}
	}

	/**
		How far either side of a seam a press still takes hold of it, in logical pixels.

		A seam is a hairline, and nobody hits a hairline, so the band it answers to is
		wider than what is drawn. Four is where it stays: the grips say where the seam is
		and the pointer changes shape over it, and a wider band starts taking presses
		meant for the pane beside it, which is worse than a drag that missed.
	**/
	static inline final REACH = 4;

	/**
		@param px A point, across.
		@param py A point, down.
		@return Which seam is under it, or -1 for none.
	**/
	function nearDivider(px:Float, py:Float):Int {
		final root = root();
		if (root == null) return -1;

		final reach = root.metrics.whole(REACH);
		final body = zones[RAIL];

		if (py >= body.y && py < body.y + body.height) {
			if (railOpen && Math.abs(px - divider(RAIL)) <= reach) return RAIL;
			if (inspectorOpen && Math.abs(px - divider(INSPECTOR)) <= reach) return INSPECTOR;
		}

		return -1;
	}

	/**
		Says a seam can be dragged before anything has been pressed, which is the one
		signal a reader already knows to look for.

		@param px A point, across.
		@param py A point, down.
		@return The arrow across over a seam, and the ordinary arrow everywhere else.
	**/
	override public function cursorAt(px:Float, py:Float):Int {
		return nearDivider(px, py) >= 0 ? mdd.host.Sdl.CURSOR_ACROSS
			: mdd.host.Sdl.CURSOR_ARROW;
	}

	/**
		Drags a seam.

		@param event The event.
		@return Whether it was taken.
	**/
	override function took(event:Input):Bool {
		switch (event.kind) {
			case Kind.PointerDown:
				final which = nearDivider(event.x, event.y);
				if (which < 0) return false;

				dragging = which;
				grabAt = event.x;
				grabSize = which == RAIL ? railWide : inspectorWide;
				return true;

			case Kind.PointerMove:
				if (dragging < 0) {
					final near = nearDivider(event.x, event.y);
					if (near == overDivider) return false;

					overDivider = near;
					invalidate();

					return near >= 0;
				}

				final root = root();
				if (root == null) return true;

				final metrics = root.metrics;
				final least = metrics.whole(140);

				switch (dragging) {
					case RAIL:
						railWide = hold(grabSize + (event.x - grabAt), least, width * 0.5);
						railSize.hold(railWide);
					case INSPECTOR:
						inspectorWide = hold(grabSize - (event.x - grabAt), least, width * 0.5);
						inspectorSize.hold(inspectorWide);
					case _:
				}

				relayout();
				return true;

			case Kind.PointerUp:
				if (dragging < 0) return false;

				dragging = -1;
				invalidate();
				return true;

			case _:
		}
		return false;
	}

	var overDivider:Int = -1;

	/**
		Forgets which seam was under the pointer when it leaves.

		@param on Whether the pointer is over the shell.
	**/
	override function hovered(on:Bool):Void {
		if (!on && overDivider >= 0) {
			overDivider = -1;
			invalidate();
		}

		super.hovered(on);
	}

	/**
		Draws one seam, brighter while it is hovered or dragged.

		@param paint What to draw with.
		@param theme The colours to draw in.
		@param which Which seam.
		@param at Where it sits.
		@param from Where it starts along its length.
		@param span How long it is.
		@param hair How thick the seam line is.
		@param upright Whether it runs down rather than across.
	**/
	function seam(paint:Paint, theme:Theme, which:Int, at:Float, from:Float, span:Float,
			hair:Float, upright:Bool):Void {
		final lit = dragging == which || (dragging < 0 && overDivider == which);
		final colour = lit ? theme.accent : theme.frame;
		final thick = lit ? hair * 3 : hair;
		final back = lit ? at - hair : at;

		if (upright) paint.rect(back, from, thick, span, colour, lit ? 0.9 : 1);
		else paint.rect(from, back, span, thick, colour, lit ? 0.9 : 1);

		gripped(paint, theme, lit, at, from, span, hair, upright);
	}

	/**
		How many marks sit in the middle of a seam.
	**/
	static inline final GRIPS = 5;

	/**
		Draws the marks that say a seam can be taken hold of.

		A seam at rest is a hairline the width of every other border in the window, so
		nothing about it says it is the one line that moves, and the brightening it does
		under the pointer is only found by somebody already on it. The marks are there
		before the pointer is, which is the whole point of them.

		@param paint What to draw with.
		@param theme The colours to draw in.
		@param lit Whether the seam is hovered or being dragged.
		@param at Where the seam sits across its own thickness.
		@param from Where it starts along its length.
		@param span How long it is.
		@param hair How thick the seam line is.
		@param upright Whether it runs down rather than across.
	**/
	function gripped(paint:Paint, theme:Theme, lit:Bool, at:Float, from:Float, span:Float,
			hair:Float, upright:Bool):Void {
		final dot = hair * 2;
		final step = dot * 2;
		final run = (GRIPS * 2 - 1) * dot;

		if (span < run * 3) return;

		final start = from + (span - run) * 0.5;
		final across = at + hair * 0.5 - dot * 0.5;
		final colour = lit ? theme.accent : theme.dim;
		final alpha = lit ? 1.0 : 0.85;

		for (index in 0...GRIPS) {
			final along = start + index * step;

			if (upright) paint.rect(across, along, dot, dot, colour, alpha);
			else paint.rect(along, across, dot, dot, colour, alpha);
		}
	}

	/**
		@param value A number.
		@param least The floor.
		@param most The ceiling.
		@return It held between the two.
	**/
	static inline function hold(value:Float, least:Float, most:Float):Float {
		return value < least ? least : (value > most ? most : value);
	}

	/**
		Draws every open zone and the seams between them.

		@param paint What to draw with.
	**/
	override function paint(paint:Paint):Void {
		final root = root();
		if (root == null) return;

		final theme = root.theme;
		final metrics = root.metrics;
		final hair = metrics.whole(1);

		paint.rect(x, y, width, height, theme.ground);
		paint.rect(zones[MENU].x, zones[MENU].y, zones[MENU].width, zones[MENU].height, theme.bar);
		paint.rect(zones[TRANSPORT].x, zones[TRANSPORT].y, zones[TRANSPORT].width,
			zones[TRANSPORT].height, theme.bar);
		paint.rect(zones[RAIL].x, zones[RAIL].y, zones[RAIL].width, zones[RAIL].height,
			theme.panel);
		paint.rect(zones[INSPECTOR].x, zones[INSPECTOR].y, zones[INSPECTOR].width,
			zones[INSPECTOR].height, theme.panel);
		paint.rect(zones[STATUS].x, zones[STATUS].y, zones[STATUS].width, zones[STATUS].height,
			theme.panel);

		paint.rect(x, zones[TRANSPORT].y - hair, width, hair, theme.frame);
		paint.rect(x, zones[RAIL].y - hair, width, hair, theme.frame);
		seam(paint, theme, RAIL, divider(RAIL), zones[RAIL].y, zones[RAIL].height, hair, true);
		seam(paint, theme, INSPECTOR, divider(INSPECTOR), zones[RAIL].y, zones[RAIL].height,
			hair, true);
		paint.rect(x, divider(STATUS), width, hair, theme.frame);

		for (which in 0...ZONES) {
			final zone = zones[which];
			if (!zone.visible) continue;

			final showing = share(which);
			if (showing <= 0.004) continue;

			if (showing >= 1) {
				zone.paint(paint);
				continue;
			}

			paint.pushOpacity(showing);
			zone.paint(paint);
			paint.popOpacity();
		}
	}
}
