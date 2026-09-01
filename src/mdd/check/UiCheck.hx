package mdd.check;

import haxe.ds.Vector;
import mdd.host.Canvas;
import mdd.host.Draw;
import mdd.host.Native;
import mdd.host.Sdl;
import mdd.host.Texture;
import mdd.host.Window;
import mdd.ui.Button;
import mdd.ui.Field;
import mdd.ui.Font;
import mdd.ui.Input;
import mdd.ui.Key;
import mdd.ui.Kind;
import mdd.ui.Mod;
import mdd.ui.Pointer;
import mdd.ui.Metrics;
import mdd.ui.Number;
import mdd.ui.Paint;
import mdd.ui.Root;
import mdd.ui.Shell;
import mdd.ui.Theme;
import mdd.ui.Knob;
import mdd.ui.Meter;
import mdd.ui.Range;
import mdd.ui.Scroll;
import mdd.ui.Sheet;
import mdd.ui.Slider;
import mdd.ui.Table;
import mdd.ui.Tabs;
import mdd.ui.Toggle;
import mdd.ui.Widget;

@:unreflective
class Marquee extends Widget {
	public final boxes:Vector<Float>;
	public final count:Int;

	public function new(count:Int) {
		super();
		this.count = count;
		boxes = new Vector<Float>(count * 4);

		var seed = 12345;
		for (i in 0...count) {
			seed = (seed * 1103515245 + 12345) & 0x3FFFFFFF;
			boxes[i * 4] = (seed % 1900) / 1.0;
			seed = (seed * 1103515245 + 12345) & 0x3FFFFFFF;
			boxes[i * 4 + 1] = (seed % 1000) / 1.0;
			boxes[i * 4 + 2] = 12;
			boxes[i * 4 + 3] = 8;
		}
	}

	public function sweep(left:Float, top:Float, right:Float, bottom:Float):Int {
		var caught = 0;
		for (i in 0...count) {
			final bx = boxes[i * 4];
			final by = boxes[i * 4 + 1];
			if (bx + boxes[i * 4 + 2] < left || bx > right) continue;
			if (by + boxes[i * 4 + 3] < top || by > bottom) continue;
			caught++;
		}
		return caught;
	}
}

@:unreflective
class UiCheck {
	static inline final SIDE = 512;

	static var failed:Int = 0;
	static var ran:Int = 0;

	public static function run(args:Array<String>):Int {
		Native.ready();
		Sys.println("  ui");

		if (Sdl.init() == 0) {
			Sys.println("    SDL would not start: " + Sdl.error());
			return 1;
		}

		final window = Sdl.createWindow("mdd gate ui", SIDE, SIDE, 0, 0);
		final renderer = Sdl.createRenderer(window, 0);
		final target = Draw.createTarget(renderer, SIDE, SIDE);

		final root = args.length > 0 ? args[0] : Gate.root;
		final face = root + "/vendor/fonts/Go-Regular.ttf";
		final monoFace = root + "/vendor/fonts/Go-Mono.ttf";

		if (!sys.FileSystem.exists(face)) {
			Sys.println("    no font at " + face + ", run: mdd setup");
			Sdl.quit();
			return 1;
		}

		routing();
		focusOrder();
		capture();
		editing();
		numbers();
		gestures();
		ranges();
		switches();
		scrolling();
		tables();
		marquee();
		shells(renderer, face, monoFace);
		quiet(renderer, target, face, monoFace);
		sheets(renderer, target, face, monoFace);

		Draw.destroyTexture(target);
		Sdl.destroyRenderer(renderer);
		Sdl.destroyWindow(window);
		Sdl.quit();

		Sys.println("    " + (ran - failed) + " of " + ran + " checks");
		if (failed > 0) {
			Sys.println("    failed");
			return 1;
		}

		Sys.println("    passed");
		return 0;
	}

	static function says(name:String, ok:Bool, said:String):Void {
		ran++;
		if (!ok) failed++;
		Sys.println("    " + StringTools.rpad(name, " ", 18) + said + (ok ? "" : "   FAILED"));
	}

	static function shaped():Root {
		final top = new Widget();
		final metrics = new Metrics(1);
		return new Root(top, metrics, new Theme());
	}

	static function routing():Void {
		final root = shaped();
		root.resize(400, 300);

		final under = new Widget();
		final over = new Widget();
		root.top.add(under);
		root.top.add(over);

		root.top.arrange(0, 0, 400, 300);
		under.arrange(0, 0, 200, 200);
		over.arrange(100, 100, 200, 200);

		final inBoth = root.top.hit(150, 150);
		final inUnder = root.top.hit(50, 50);
		final outside = root.top.hit(390, 290);

		says("hit topmost", inBoth == over, "overlap resolves to the later child");
		says("hit under", inUnder == under, "outside the overlap");
		says("hit fallthrough", outside == root.top, "lands on the parent");
	}

	static function focusOrder():Void {
		final root = shaped();
		root.resize(400, 300);

		final a = new Button("a");
		final b = new Button("b");
		final c = new Button("c");
		final off = new Button("off");
		off.enabled = false;

		root.top.add(a);
		root.top.add(b);
		root.top.add(off);
		root.top.add(c);

		says("focusable count", root.focusable() == 3, "3 of 4, the disabled one excluded");

		root.step(1);
		final first = root.focus == a;
		root.step(1);
		final second = root.focus == b;
		root.step(1);
		final third = root.focus == c;
		root.step(1);
		final wrapped = root.focus == a;

		says("tab forward", first && second && third && wrapped, "a, b, c, wraps to a");

		root.step(-1);
		says("tab backward", root.focus == c, "shift tab wraps to c");
	}

	static function capture():Void {
		final root = shaped();
		root.resize(400, 300);

		final field = new Field("drag");
		root.top.add(field);
		root.top.arrange(0, 0, 400, 300);
		field.arrange(0, 0, 100, 30);

		root.pressed(20, 10, Pointer.Left, Mod.None);
		final took = root.capture == field;

		root.moved(900, 900, Mod.None);
		final held = root.capture == field;

		root.released(900, 900, Pointer.Left, Mod.None);
		final let = root.capture == null;

		says("capture", took && held && let, "held across a drag that left the widget");
	}

	static function editing():Void {
		final field = new Field("");
		final root = shaped();
		root.top.add(field);
		root.resize(400, 300);
		root.focusOn(field);

		root.said("Chemical", Mod.None);
		says("typing", field.value == "Chemical", "\"" + field.value + "\"");

		root.key(true, Key.Left, Mod.None);
		root.key(true, Key.Left, Mod.Shift);
		root.key(true, Key.Left, Mod.Shift);
		says("shift select", field.selected() == "ca", "selected \"" + field.selected() + "\"");

		root.key(true, Key.C, Mod.Ctrl);
		root.key(true, Key.End, Mod.None);
		root.key(true, Key.V, Mod.Ctrl);
		says("copy and paste", field.value == "Chemicalca", "\"" + field.value + "\"");

		root.key(true, Key.A, Mod.Ctrl);
		root.key(true, Key.X, Mod.Ctrl);
		says("select all and cut", field.value == "" && field.clipboard == "Chemicalca",
			"cleared, clipboard \"" + field.clipboard + "\"");

		root.said("Plant", Mod.None);
		root.key(true, Key.Backspace, Mod.None);
		says("backspace", field.value == "Plan", "\"" + field.value + "\"");

		root.key(true, Key.Home, Mod.None);
		root.key(true, Key.Delete, Mod.None);
		says("delete forward", field.value == "lan", "\"" + field.value + "\"");
	}

	static function numbers():Void {
		final root = shaped();
		final number = new Number("TL", 23, 0, 127);
		root.top.add(number);
		root.resize(400, 300);
		root.top.arrange(0, 0, 400, 300);
		number.arrange(0, 0, 90, 40);

		root.pressed(20, 20, Pointer.Left, Mod.None);
		root.moved(20, 0, Mod.None);
		final coarse = number.value;
		root.released(20, 0, Pointer.Left, Mod.None);

		number.set(23);
		root.pressed(20, 20, Pointer.Left, Mod.Ctrl);
		root.moved(20, 0, Mod.Ctrl);
		final fine = number.value;
		root.released(20, 0, Pointer.Left, Mod.Ctrl);

		says("drag a number", coarse == 33 && fine == 25,
			"coarse +" + (coarse - 23) + ", ctrl fine +" + (fine - 23));

		number.set(120);
		number.set(400);
		says("clamped", number.value == 127, "held at " + number.value + " of 127");
	}

	static function gestures():Void {
		final root = shaped();
		final number = new Number("AR", 16, 0, 31);
		root.top.add(number);
		root.resize(400, 300);
		root.top.arrange(0, 0, 400, 300);
		number.arrange(0, 0, 90, 40);

		root.moved(20, 20, Mod.None);
		root.turned(0, 1, Mod.None);
		final coarse = number.value;

		root.turned(0, 1, Mod.Ctrl);
		final fine = number.value;

		says("wheel", coarse == 20 && fine == 21,
			"plain +4, ctrl +1");

		final field = new Field("word");
		root.top.add(field);
		field.arrange(0, 100, 100, 30);
		root.pressed(20, 110, Pointer.Left, Mod.None, 2);
		says("double click", field.selected() == "word", "selects all of \"" + field.selected() + "\"");
	}

	static function ranges():Void {
		final held:Array<Range> = [new Number("TL", 0, 0, 127), new Slider(0, 0, 127),
			new Knob("FB", 0, 0, 127)];
		final names = ["Number", "Slider", "Knob"];

		var complaint = "";
		for (i in 0...held.length) {
			final one = held[i];

			one.set(64);
			if (one.value != 64) complaint += names[i] + " set 64 gave " + one.value + " ";
			if (one.span() != 127) complaint += names[i] + " span " + one.span() + " ";
			if (Math.abs(one.share() - 64 / 127) > 0.0001) {
				complaint += names[i] + " share " + one.share() + " ";
			}

			one.set(-40);
			if (one.value != 0) complaint += names[i] + " floor gave " + one.value + " ";

			one.set(900);
			if (one.value != 127) complaint += names[i] + " ceiling gave " + one.value + " ";
		}

		says("range interface", complaint == "",
			complaint == "" ? "Number, Slider and Knob agree on set, span and share" : complaint);

		final root = shaped();
		final slider = new Slider(0, 0, 100);
		root.top.add(slider);
		root.resize(400, 300);
		root.top.arrange(0, 0, 400, 300);
		slider.arrange(0, 0, 200, 24);

		root.pressed(150, 12, Pointer.Left, Mod.None);
		root.released(150, 12, Pointer.Left, Mod.None);
		says("slider jumps", slider.value == 75, "clicked three quarters along, got " + slider.value);

		final knob = new Knob("FB", 50, 0, 100);
		root.top.add(knob);
		knob.arrange(0, 40, 44, 56);
		root.pressed(20, 60, Pointer.Left, Mod.None);
		root.moved(20, 60 - 64, Mod.None);
		final coarse = knob.value;
		root.released(20, 0, Pointer.Left, Mod.None);
		says("knob drag", coarse == 100, "half the travel is the whole range, got " + coarse);
	}

	static function switches():Void {
		final root = shaped();
		final toggle = new Toggle("Loop");
		final tabs = new Tabs(["Piano roll", "Scope", "Samples", "Tracker"]);

		root.top.add(toggle);
		root.top.add(tabs);
		root.resize(600, 300);
		root.top.arrange(0, 0, 600, 300);
		toggle.arrange(0, 0, 120, 24);
		tabs.arrange(0, 40, 600, 30);

		var fired = 0;
		toggle.onChange = function(one:Toggle):Void fired++;

		root.pressed(10, 12, Pointer.Left, Mod.None);
		root.released(10, 12, Pointer.Left, Mod.None);
		final on = toggle.on;

		root.key(true, Key.Space, Mod.None);
		says("toggle", on && !toggle.on && fired == 2,
			"click on, space off, " + fired + " changes");

		var chose = -1;
		tabs.onChoose = function(which:Int):Void chose = which;
		tabs.choose(2);
		root.focusOn(tabs);
		root.key(true, Key.Left, Mod.None);

		says("tabs", chose == 1 && tabs.chosen == 1,
			"chose 2 then left arrow, landed on " + tabs.chosen);
	}

	static function scrolling():Void {
		final root = shaped();
		final scroll = new Scroll();
		root.top.add(scroll);
		root.resize(400, 300);
		root.top.arrange(0, 0, 400, 300);
		scroll.arrange(0, 0, 200, 100);
		scroll.contentHeight = 1000;

		root.moved(50, 50, Mod.None);
		root.turned(0, -3, Mod.None);
		final down = scroll.offsetY;

		root.turned(0, 60, Mod.None);
		final top = scroll.offsetY;

		root.turned(0, -600, Mod.None);
		final bottom = scroll.offsetY;

		says("scroll", down > 0 && top == 0 && bottom == 900,
			"down " + down + ", clamped to 0 and to " + bottom + " of 900");
	}

	static function tables():Void {
		final root = shaped();
		final table = new Table(3);
		root.top.add(table);
		root.resize(600, 400);
		root.top.arrange(0, 0, 600, 400);
		table.arrange(0, 0, 600, 180);
		table.rowHeight = 18;
		table.read = function(row:Int, column:Int):String return row + ":" + column;
		table.hold(1000000);

		says("table holds", table.contentHeight == 18000000.0,
			"1,000,000 rows is " + table.contentHeight + " tall");

		table.choose(500);
		root.focusOn(table);
		root.key(true, Key.Down, Mod.None);
		says("table keys", table.chosen == 501, "chose 500, down arrow to " + table.chosen);

		table.scrollTo(9000);
		says("table scrolls", table.offsetY == 9000, "at " + table.offsetY);
	}

	static function marquee():Void {
		final sheet = new Marquee(5000);

		var caught = 0;
		final began = Sdl.ticks();
		for (pass in 0...10) caught = sheet.sweep(200, 200, 900, 700);
		final each = (Sdl.ticks() - began) * 1000 / 10;

		says("marquee 5000", each < 1.0,
			Math.round(each * 1000) / 1000 + " ms, " + caught + " caught");
	}

	static function shells(renderer:cpp.Star<Canvas>, face:String, monoFace:String):Void {
		for (scale in [1.0, 1.25, 1.5, 2.0]) {
			final metrics = new Metrics(scale);
			final shell = new Shell();
			final root = new Root(shell, metrics, new Theme());

			root.resize(1400 * scale, 900 * scale);
			shell.fit(metrics);
			shell.measure(root.width, root.height);
			shell.arrange(0, 0, root.width, root.height);

			var sane = true;
			var said = "";

			for (which in 0...Shell.ZONES) {
				final zone = shell.zone(which);
				if (zone.width < 0 || zone.height < 0) {
					sane = false;
					said = "zone " + which + " is negative";
				}
			}

			final rail = shell.zone(Shell.RAIL);
			final centre = shell.zone(Shell.CENTRE);
			final inspector = shell.zone(Shell.INSPECTOR);
			final dock = shell.zone(Shell.DOCK);

			if (Math.abs((rail.x + rail.width) - centre.x) > 0.51) {
				sane = false;
				said = "rail and centre overlap";
			}
			if (Math.abs((centre.x + centre.width) - inspector.x) > 0.51) {
				sane = false;
				said = "centre and inspector overlap";
			}
			if (Math.abs((rail.y + rail.height) - dock.y) > 0.51) {
				sane = false;
				said = "body and dock overlap";
			}
			if (Math.abs((inspector.x + inspector.width) - root.width) > 0.51) {
				sane = false;
				said = "the shell does not fill its width";
			}

			says("shell at " + scale, sane, said != "" ? said
				: "rail " + rail.width + ", centre " + centre.width + ", inspector "
				+ inspector.width + ", dock " + dock.height);
		}

		final metrics = new Metrics(1);
		final shell = new Shell();
		final root = new Root(shell, metrics, new Theme());
		root.resize(1400, 900);
		shell.fit(metrics);
		shell.arrange(0, 0, 1400, 900);

		final was = shell.zone(Shell.CENTRE).width;
		final at = shell.divider(Shell.RAIL);

		root.pressed(at, 400, Pointer.Left, Mod.None);
		root.moved(at + 60, 400, Mod.None);
		root.released(at + 60, 400, Pointer.Left, Mod.None);

		shell.arrange(0, 0, 1400, 900);
		final now = shell.zone(Shell.CENTRE).width;

		says("drag a divider", Math.abs((was - now) - 60) < 1.5,
			"rail grew 60, centre lost " + Math.round(was - now));
	}

	static function sheets(renderer:cpp.Star<Canvas>, target:cpp.Star<Texture>, face:String,
			monoFace:String):Void {
		final body = Font.bake(renderer, face, 13);
		if (body == null) {
			says("sheet caching", false, "the font would not bake");
			return;
		}

		final metrics = new Metrics(1);
		metrics.dress(body, body, body, body);

		final sheet = new Sheet();
		final root = new Root(sheet, metrics, new Theme());
		root.resize(200, 120);

		final paint = Paint.on(renderer, body);

		Draw.setTarget(renderer, target);
		Sdl.renderClear(renderer, 0, 0, 0, 1);

		root.frame(paint);
		final firstBaked = sheet.baked;

		sheet.invalidate();
		root.frame(paint);
		final twiceBaked = sheet.baked;

		root.soil();
		root.frame(paint);
		final stillTwice = sheet.baked;
		final blits = sheet.blitted;

		Draw.setTarget(renderer, null);

		says("sheet caching", firstBaked == 1 && twiceBaked == 2 && stillTwice == 2 && blits == 3,
			"baked " + stillTwice + " times across " + blits + " frames");

		sheet.shut();
		body.shut();
	}

	static function quiet(renderer:cpp.Star<Canvas>, target:cpp.Star<Texture>, face:String,
			monoFace:String):Void {
		final body = Font.bake(renderer, face, 13);
		final mono = Font.bake(renderer, monoFace, 12);

		if (body == null || mono == null) {
			says("settled frame", false, "the fonts would not bake");
			return;
		}

		final metrics = new Metrics(1);
		metrics.dress(body, body, mono, mono);

		final shell = new Shell();
		final root = new Root(shell, metrics, new Theme());
		root.resize(SIDE, SIDE);

		final button = new Button("Play");
		shell.zone(Shell.TRANSPORT).add(button);

		final paint = Paint.on(renderer, body);

		Draw.setTarget(renderer, target);
		Sdl.renderClear(renderer, 0, 0, 0, 1);

		final first = root.frame(paint);

		Draw.resetCalls();
		final second = root.frame(paint);
		final quietCalls = Draw.calls();

		button.invalidate();
		Draw.resetCalls();
		final third = root.frame(paint);
		final wokeCalls = Draw.calls();

		Draw.setTarget(renderer, null);

		says("first frame", first, "painted");
		says("settled frame", !second && quietCalls == 0,
			quietCalls + " draw calls when nothing changed");
		says("woken frame", third && wokeCalls >= 1,
			wokeCalls + " draw call after one widget invalidated");

		body.shut();
		mono.shut();
	}
}
