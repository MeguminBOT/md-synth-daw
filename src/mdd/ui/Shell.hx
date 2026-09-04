package mdd.ui;

@:unreflective
final class Shell extends Widget {
	public static inline final MENU = 0;
	public static inline final TRANSPORT = 1;
	public static inline final RAIL = 2;
	public static inline final CENTRE = 3;
	public static inline final INSPECTOR = 4;
	public static inline final STATUS = 5;
	public static inline final ZONES = 6;

	public var railWide:Float = 0;
	public var inspectorWide:Float = 0;

	public var railOpen:Bool = true;
	public var inspectorOpen:Bool = true;

	public final railSize:Motion;
	public final inspectorSize:Motion;

	final zones:Array<Widget> = [];

	public var dragging(default, null):Int = -1;

	var grabAt:Float = 0;
	var grabSize:Float = 0;

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

	public function zone(which:Int):Widget {
		return zones[which];
	}

	public function fit(metrics:Metrics):Void {
		railWide = metrics.rail;
		inspectorWide = metrics.inspector;

		railSize.hold(railOpen ? railWide : strip(metrics));
		inspectorSize.hold(inspectorOpen ? inspectorWide : strip(metrics));
	}

	static inline function strip(metrics:Metrics):Float {
		return metrics.whole(24);
	}

	public inline function openAt(which:Int):Bool {
		return switch (which) {
			case RAIL: railOpen;
			case INSPECTOR: inspectorOpen;
			case _: true;
		}
	}

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

	static function reach(value:Float, least:Float, most:Float):Float {
		if (most <= least) return 1;

		final part = (value - least) / (most - least);
		return part < 0 ? 0 : (part > 1 ? 1 : part);
	}

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

	function nearDivider(px:Float, py:Float):Int {
		final root = root();
		if (root == null) return -1;

		final reach = root.metrics.whole(4);
		final body = zones[RAIL];

		if (py >= body.y && py < body.y + body.height) {
			if (railOpen && Math.abs(px - divider(RAIL)) <= reach) return RAIL;
			if (inspectorOpen && Math.abs(px - divider(INSPECTOR)) <= reach) return INSPECTOR;
		}

		return -1;
	}

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

	override function hovered(on:Bool):Void {
		if (!on && overDivider >= 0) {
			overDivider = -1;
			invalidate();
		}

		super.hovered(on);
	}

	function seam(paint:Paint, theme:Theme, which:Int, at:Float, from:Float, span:Float,
			hair:Float, upright:Bool):Void {
		final lit = dragging == which || (dragging < 0 && overDivider == which);
		final colour = lit ? theme.accent : theme.frame;
		final thick = lit ? hair * 3 : hair;
		final back = lit ? at - hair : at;

		if (upright) paint.rect(back, from, thick, span, colour, lit ? 0.9 : 1);
		else paint.rect(from, back, span, thick, colour, lit ? 0.9 : 1);
	}

	static inline function hold(value:Float, least:Float, most:Float):Float {
		return value < least ? least : (value > most ? most : value);
	}

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
