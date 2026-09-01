package mdd.ui;

@:unreflective
final class Shell extends Widget {
	public static inline final MENU = 0;
	public static inline final TRANSPORT = 1;
	public static inline final RAIL = 2;
	public static inline final CENTRE = 3;
	public static inline final INSPECTOR = 4;
	public static inline final DOCK = 5;
	public static inline final ZONES = 6;

	public var railWide:Float = 0;
	public var inspectorWide:Float = 0;
	public var dockTall:Float = 0;

	public var railOpen:Bool = true;
	public var inspectorOpen:Bool = true;
	public var dockOpen:Bool = true;

	public final railSize:Motion;
	public final inspectorSize:Motion;
	public final dockSize:Motion;

	final zones:Array<Widget> = [];

	public var dragging(default, null):Int = -1;

	var grabAt:Float = 0;
	var grabSize:Float = 0;

	public function new() {
		super();

		railSize = new Motion(this, 0, true, true);
		inspectorSize = new Motion(this, 0, true, true);
		dockSize = new Motion(this, 0, true, true);

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
		dockTall = metrics.dock;

		railSize.hold(railOpen ? railWide : strip(metrics));
		inspectorSize.hold(inspectorOpen ? inspectorWide : strip(metrics));
		dockSize.hold(dockOpen ? dockTall : metrics.bar);
	}

	static inline function strip(metrics:Metrics):Float {
		return metrics.whole(24);
	}

	public inline function openAt(which:Int):Bool {
		return switch (which) {
			case RAIL: railOpen;
			case INSPECTOR: inspectorOpen;
			case DOCK: dockOpen;
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

			case DOCK:
				dockOpen = on;
				root.start(dockSize, on ? dockTall : metrics.bar, Motion.ENTER);

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
			case DOCK: reach(dockSize.value, root.metrics.bar, dockTall);
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
		final dock = dockSize.value;

		final bodyTop = y + menuTall + transportTall;
		var bodyTall = height - menuTall - transportTall - dock;
		if (bodyTall < 0) bodyTall = 0;

		var centreWide = width - rail - inspector;
		if (centreWide < 0) centreWide = 0;

		zones[MENU].arrange(x, y, width, menuTall);
		zones[TRANSPORT].arrange(x, y + menuTall, width, transportTall);
		zones[RAIL].arrange(x, bodyTop, rail, bodyTall);
		zones[CENTRE].arrange(x + rail, bodyTop, centreWide, bodyTall);
		zones[INSPECTOR].arrange(x + rail + centreWide, bodyTop, inspector, bodyTall);
		zones[DOCK].arrange(x, bodyTop + bodyTall, width, dock);
	}

	public function divider(which:Int):Float {
		final rail = zones[RAIL];
		final inspector = zones[INSPECTOR];
		final dock = zones[DOCK];

		return switch (which) {
			case RAIL: rail.x + rail.width;
			case INSPECTOR: inspector.x;
			case DOCK: dock.y;
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

		if (dockOpen && Math.abs(py - divider(DOCK)) <= reach) return DOCK;
		return -1;
	}

	override function took(event:Input):Bool {
		switch (event.kind) {
			case Kind.PointerDown:
				final which = nearDivider(event.x, event.y);
				if (which < 0) return false;

				dragging = which;
				grabAt = which == DOCK ? event.y : event.x;
				grabSize = which == RAIL ? railWide
					: (which == INSPECTOR ? inspectorWide : dockTall);
				return true;

			case Kind.PointerMove:
				if (dragging < 0) return false;

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
					case DOCK:
						dockTall = hold(grabSize - (event.y - grabAt), metrics.bar, height * 0.6);
						dockSize.hold(dockTall);
					case _:
				}

				relayout();
				return true;

			case Kind.PointerUp:
				if (dragging < 0) return false;
				dragging = -1;
				return true;

			case _:
		}
		return false;
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
		paint.rect(zones[DOCK].x, zones[DOCK].y, zones[DOCK].width, zones[DOCK].height,
			theme.panel);

		paint.rect(x, zones[TRANSPORT].y, width, hair, theme.frame);
		paint.rect(x, zones[RAIL].y, width, hair, theme.frame);
		paint.rect(divider(RAIL) - hair, zones[RAIL].y, hair, zones[RAIL].height, theme.frame);
		paint.rect(divider(INSPECTOR), zones[RAIL].y, hair, zones[RAIL].height, theme.frame);
		paint.rect(x, divider(DOCK), width, hair, theme.frame);

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
