package mdd.gate;

import haxe.ds.Vector;
import mdd.host.Canvas;
import mdd.host.Draw;
import mdd.host.Native;
import mdd.host.Sdl;
import mdd.host.Texture;
import mdd.host.Window;
import mdd.ui.control.Button;
import mdd.ui.control.Choice;
import mdd.ui.control.Field;
import mdd.ui.Flow;
import mdd.ui.Font;
import mdd.ui.Input;
import mdd.ui.Key;
import mdd.ui.Item;
import mdd.ui.Kind;
import mdd.ui.control.Menu;
import mdd.ui.control.MenuBar;
import mdd.ui.Mod;
import mdd.ui.Motion;
import mdd.ui.Pointer;
import mdd.ui.Metrics;
import mdd.ui.control.Number;
import mdd.ui.Paint;
import mdd.ui.Root;
import mdd.ui.Shell;
import mdd.ui.Theme;
import mdd.ui.control.Knob;
import mdd.ui.control.Meter;
import mdd.ui.Range;
import mdd.ui.Scroll;
import mdd.ui.Sheet;
import mdd.ui.control.Slider;
import mdd.ui.control.Table;
import mdd.ui.control.Tabs;
import mdd.ui.control.Toggle;
import mdd.ui.control.Tooltip;
import mdd.ui.control.Tree;
import mdd.ui.Widget;
import mdd.ui.Translation;
import mdd.view.editor.Samples;
import mdd.view.editor.Tracker;
import mdd.view.monitor.Scope;

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
		final renderer = Sdl.createRenderer(window, 0, mdd.App.PINNED);
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
		asked();
		used();
		editing();
		numbers();
		gestures();
		ranges();
		switches();
		scrolling();
		tables();
		marquee();
		motions();
		trees();
		menus(renderer, target, face, monoFace);
		tooltips(renderer, face, monoFace);
		bars(renderer, face, monoFace);
		shortcuts();
		saying();
		modal();
		banded();
		notices();
		remembers();
		updates();
		shells(renderer, face, monoFace);
		collapse();
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
		Sys.println("    " + StringTools.rpad(name, " ", 34) + said + (ok ? "" : "   FAILED"));
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

	static function used():Void {
		mdd.host.Usage.start();

		final cpu = mdd.host.Usage.cpu();
		final ram = mdd.host.Usage.ram();
		final gpu = mdd.host.Usage.gpu();

		mdd.host.Usage.stop();

		final sane = cpu >= 0 && cpu <= 100 && ram > 0 && ram < 65536 && gpu >= -1
			&& gpu <= 100;

		says("the host reports its own usage", sane,
			"cpu " + round(cpu, 1) + " per cent, ram " + Math.round(ram) + " MB, gpu "
			+ (gpu < 0 ? "not counted" : round(gpu, 1) + " per cent"));
	}

	static function asked():Void {
		final field = new Field("");
		final number = new mdd.ui.control.Number("BPM", 120, 20, 400);

		final root = shaped();

		root.top.add(field);
		root.top.add(number);

		root.resize(400, 300);

		var told:Array<Bool> = [];
		root.onTyping = function(on:Bool):Void told.push(on);

		root.focusOn(field);
		field.typing = true;
		root.advance(0.016);

		final started = told.length == 1 && told[0];

		field.typing = false;
		root.focusOn(null);
		root.advance(0.016);

		final stopped = told.length == 2 && !told[1];

		number.arrange(0, 0, 80, 30);
		root.focusOn(number);

		final press = new mdd.ui.Input();
		press.pointer(Kind.PointerDown, 40, 15, Pointer.Left, Mod.None, 2);
		number.took(press);

		root.advance(0.016);

		final again = told.length == 3 && told[2];

		says("the host is told when a widget wants characters", started && stopped && again,
			"a field asked for text and gave it back, and a double click on a number asked "
			+ "again, " + told.length + " changes in all");
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

		says("a slider jumps to where the track was clicked",
			slider.value > 70 && slider.value < 80,
			"clicked three quarters along, got " + slider.value);

		var carried = "";

		for (want in [0, 17, 50, 83, 100]) {
			slider.set(want);

			final held = slider.grip();
			final middle = slider.x + (slider.width - held) * slider.share()
				+ held * 0.5;

			root.pressed(middle, 12, Pointer.Left, Mod.None);
			root.released(middle, 12, Pointer.Left, Mod.None);

			if (slider.value != want) {
				carried += want + " came back as " + slider.value + " ";
			}
		}

		says("and taking hold of its grip does not move it", carried == "",
			carried == ""
				? "pressing on the middle of the grip leaves all of 0, 17, 50, 83 and 100"
					+ " where they were"
				: carried);

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

		scroll.scrollTo(0);

		final bar = scroll.x + scroll.width - 4;
		final low = scroll.y + scroll.height - 6;

		root.pressed(bar, low, Pointer.Left, Mod.None);
		root.released(bar, low, Pointer.Left, Mod.None);

		final jumped = scroll.offsetY;

		says("and a press on the empty track moves the thumb there",
			jumped > 700,
			"a press near the bottom of the bar went to " + Math.round(jumped)
			+ " of 900, where it used to sit still until the pointer moved");

		scroll.scrollTo(450);

		final held = scroll.offsetY;
		final onIt = scroll.thumbAt() + scroll.thumb() * 0.5;

		root.pressed(bar, onIt, Pointer.Left, Mod.None);
		final onThumb = scroll.offsetY;
		root.released(bar, onIt, Pointer.Left, Mod.None);

		says("and a press on the thumb itself leaves it alone",
			onThumb == held,
			"the view stayed at " + Math.round(onThumb)
			+ " when the thumb was taken hold of where it stood");
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
			final dock = shell.zone(Shell.STATUS);

			final hair = metrics.whole(1);

			if (Math.abs(centre.x - (rail.x + rail.width) - hair) > 0.51) {
				sane = false;
				said = "the rail and the centre do not leave one seam";
			}
			if (Math.abs(inspector.x - (centre.x + centre.width) - hair) > 0.51) {
				sane = false;
				said = "the centre and the inspector do not leave one seam";
			}
			if (Math.abs(dock.y - (rail.y + rail.height) - hair) > 0.51) {
				sane = false;
				said = "the body and the status strip do not leave one seam";
			}
			if (Math.abs((inspector.x + inspector.width) - root.width) > 0.51) {
				sane = false;
				said = "the shell does not fill its width";
			}

			says("shell at " + scale, sane, said != "" ? said
				: "rail " + rail.width + ", centre " + centre.width + ", inspector "
				+ inspector.width + ", status " + dock.height);
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

	static inline function round(value:Float, places:Int):Float {
		final scale = Math.pow(10, places);
		return Math.round(value * scale) / scale;
	}

	static function shortcuts():Void {
		final root = shaped();
		root.resize(400, 300);

		final field = new Field("name");
		root.top.add(field);
		root.top.arrange(0, 0, 400, 300);
		field.arrange(0, 0, 200, 30);

		var heard = "";

		root.onShortcut = function(code:Key, mods:Mod):Bool {
			heard = code.shortcut(mods);
			return true;
		};

		root.focusOn(null);
		root.key(true, Key.Space, Mod.None);
		final loose = heard;

		heard = "";
		root.key(true, Key.S, Mod.Ctrl);
		final saved = heard;

		says("a shortcut reaches the session", loose == "Space" && saved == "Ctrl+S",
			"with nothing focused the session heard \"" + loose + "\" and \"" + saved + "\"");

		heard = "";
		root.focusOn(field);
		root.key(true, Key.Space, Mod.None);
		final whileTyping = heard;

		says("and the field keeps its space", whileTyping == "" && root.typed(),
			"a focused text field takes the space rather than the transport");

		heard = "";
		root.key(true, Key.S, Mod.Ctrl);

		says("but not the shortcut", heard == "Ctrl+S",
			"a modified shortcut still reaches the session past a focused field");
	}

	static function remembers():Void {
		final path = Gate.root + "/export/settings.txt";
		if (sys.FileSystem.exists(path)) sys.FileSystem.deleteFile(path);

		final settings = new mdd.host.Settings(path);
		final missing = settings.load();

		says("nothing to remember yet", !missing && settings.count() == 0,
			"a settings file that is not there loads as nothing rather than as a fault");

		settings.whole("theme", 2);
		settings.whole("density", 0);
		settings.flag("ghosts", false);
		settings.number("gain", 0.75);
		settings.put("song", "R:/a song.mdsyn");

		says("and it writes", settings.save() && sys.FileSystem.exists(path),
			settings.count() + " settings written to " + path.substr(path.length - 12));

		final back = new mdd.host.Settings(path);
		back.load();

		says("and reads back", back.asWhole("theme") == 2 && back.asWhole("density") == 0
			&& !back.asFlag("ghosts", true) && back.asNumber("gain") == 0.75
			&& back.of("song") == "R:/a song.mdsyn",
			back.read + " settings come back with their types, including a path with a space");

		says("and an absent one falls back", back.asWhole("nothing", 7) == 7
			&& back.of("nothing", "held") == "held",
			"a key that was never written gives what the caller asked for instead");
	}

	static function updates():Void {
		var right = true;

		for (pair in [["0.2.0", "0.1.9"], ["1.0.0", "0.9.9"], ["0.1.10", "0.1.9"],
				["1.2.3", "1.2.2"]]) {
			if (!mdd.app.Update.newer(pair[0], pair[1])) right = false;
		}

		for (pair in [["0.1.0", "0.1.0"], ["0.1.0", "0.2.0"], ["0.9.9", "1.0.0"],
				["1.2.2", "1.2.3"]]) {
			if (mdd.app.Update.newer(pair[0], pair[1])) right = false;
		}

		says("a version is compared in parts", right,
			"0.1.10 is newer than 0.1.9 and 0.9.9 is not newer than 1.0.0, which string order "
			+ "gets wrong both ways");

		final quiet = new mdd.app.Update("", "0.1.0", "windows");

		says("no repository means no looking", !quiet.possible() && !quiet.look()
			&& quiet.state() == mdd.app.Update.IDLE,
			"an updater with no repository configured never reaches the network");

		final held = new mdd.app.Update("MeguminBOT/md-synth-daw", "0.1.0", "windows",
			"x86_64", false);

		says("it reads github releases", held.checkAt()
			== "https://api.github.com/repos/MeguminBOT/md-synth-daw/releases/latest",
			held.checkAt());

		held.read('{"tag_name":"v0.3.1","html_url":"https://example/rel",'
			+ '"body":"Faster import\nand other things","assets":['
			+ '{"name":"mdd-0.3.1-linux.tar.gz","browser_download_url":"https://example/linux"},'
			+ '{"name":"mdd-0.3.1-windows-portable.zip","browser_download_url":"https://example/zip"},'
			+ '{"name":"mdd-0.3.1-setup.exe","browser_download_url":"https://example/setup"}]}');

		says("and picks its own platform", held.offered == "0.3.1" && held.assets == 3
			&& held.saidAt == "https://example/setup",
			"tag v0.3.1 reads as " + held.offered + ", and of " + held.assets
			+ " assets it took the windows installer");

		says("and takes the first line of the notes", held.notes == "Faster import",
			"the release body's first line is what the notice shows: " + held.notes);

		final split = '{"tag_name":"v0.4.0","html_url":"https://example/rel","assets":['
			+ '{"name":"mdd-0.4.0-linux-x86_64-portable.tar.gz","browser_download_url":"https://example/lx64p"},'
			+ '{"name":"mdd-0.4.0-linux-arm64-portable.tar.gz","browser_download_url":"https://example/larmp"},'
			+ '{"name":"mdd-0.4.0-linux-x86_64-installer.tar.gz","browser_download_url":"https://example/lx64i"},'
			+ '{"name":"mdd-0.4.0-linux-arm64-installer.tar.gz","browser_download_url":"https://example/larmi"},'
			+ '{"name":"mdd-0.4.0-windows-x86_64-setup.exe","browser_download_url":"https://example/wx64"},'
			+ '{"name":"mdd-0.4.0-mac-arm64.dmg","browser_download_url":"https://example/marm"},'
			+ '{"name":"mdd-0.4.0-mac-x86_64.dmg","browser_download_url":"https://example/mx64"}]}';

		final armed = new mdd.app.Update("owner/name", "0.1.0", "linux", "arm64", false);
		armed.read(split);

		final wide = new mdd.app.Update("owner/name", "0.1.0", "linux", "x86_64", false);
		wide.read(split);

		final apple = new mdd.app.Update("owner/name", "0.1.0", "mac", "arm64", false);
		apple.read(split);

		says("a release with both architectures gives each its own",
			armed.saidAt == "https://example/larmi"
			&& wide.saidAt == "https://example/lx64i"
			&& apple.saidAt == "https://example/marm",
			"of 7 assets linux arm64 took " + armed.saidAt.split("/").pop()
			+ ", linux x86_64 took " + wide.saidAt.split("/").pop()
			+ " and mac arm64 took " + apple.saidAt.split("/").pop());

		says("and the other architecture is never offered",
			armed.suits("mdd-0.4.0-linux-x86_64-installer.tar.gz") == 0
			&& wide.suits("mdd-0.4.0-linux-arm64-installer.tar.gz") == 0
			&& apple.suits("mdd-0.4.0-mac-x86_64.dmg") == 0,
			"an asset naming the wrong architecture scores nothing at all, so it"
			+ " cannot win on any other part of its name");

		final both = '{"tag_name":"v0.5.0","html_url":"https://example/rel","assets":['
			+ '{"name":"mdd-0.5.0-windows-x86_64-portable.zip","browser_download_url":"https://example/winzip"},'
			+ '{"name":"mdd-0.5.0-windows-x86_64-setup.exe","browser_download_url":"https://example/winexe"},'
			+ '{"name":"mdd-0.5.0-linux-x86_64-portable.tar.gz","browser_download_url":"https://example/lintar"},'
			+ '{"name":"mdd-0.5.0-linux-x86_64-installer.tar.gz","browser_download_url":"https://example/lininst"},'
			+ '{"name":"mdd-0.5.0-mac-x86_64-portable.tar.gz","browser_download_url":"https://example/mactar"},'
			+ '{"name":"mdd-0.5.0-mac-x86_64.dmg","browser_download_url":"https://example/macdmg"}]}';

		final kinds:Array<{name:String, portable:Bool, wanted:String}> = [
			{name: "windows", portable: true, wanted: "winzip"},
			{name: "windows", portable: false, wanted: "winexe"},
			{name: "linux", portable: true, wanted: "lintar"},
			{name: "linux", portable: false, wanted: "lininst"},
			{name: "mac", portable: true, wanted: "mactar"},
			{name: "mac", portable: false, wanted: "macdmg"}
		];

		var missed = 0;
		var told = "";

		for (kind in kinds) {
			final one = new mdd.app.Update("owner/name", "0.1.0", kind.name, "x86_64",
				kind.portable);

			one.read(both);

			final took = one.saidAt.split("/").pop();
			if (took != kind.wanted) {
				missed++;
				if (told != "") told += ", ";
				told += kind.name + (kind.portable ? " portable" : " installed")
					+ " took " + took + " rather than " + kind.wanted;
			}
		}

		says("a copy is offered the kind it already is", missed == 0, missed == 0
			? "a portable copy is offered the archive and an installed one the"
				+ " installer, on all three platforms"
			: missed + " of 6 chose wrong: " + told);

		final bare = new mdd.app.Update("owner/name", "0.1.0", "mac");
		bare.read('{"tag_name":"0.2.0","html_url":"https://example/page","assets":[]}');

		says("and falls back to the release page", bare.offered == "0.2.0"
			&& bare.saidAt == "https://example/page" && bare.assets == 0,
			"a release with no assets sends the reader to the page instead");
	}

	static function banded():Void {
		final root = shaped();
		root.resize(800, 600);
		root.flow = Flow.None;

		final progress = new Widget();
		progress.focusable = true;
		progress.opaque = true;

		root.bands(progress);
		progress.arrange(250, 250, 300, 100);

		says("a band is a slot of its own", root.band == progress && root.sheet == null,
			"what has to be seen is not where the sheets go");

		final sheet = new Widget();
		sheet.focusable = true;
		sheet.opaque = true;

		root.raise(sheet);
		sheet.arrange(100, 100, 600, 400);

		says("raising a sheet leaves it up", root.band == progress && root.sheet == sheet,
			"both are up at once");

		says("and it is picked before the sheet", root.pick(400, 300) == progress,
			"a point inside the band reaches the band and not what covers it");

		root.lower();

		says("lowering the sheet leaves it up", root.band == progress && root.sheet == null,
			"lower never reaches the band");

		root.raise(sheet);
		root.key(true, Key.Escape, Mod.None);

		says("and escape does not reach it either", root.band == progress,
			"the progress bar cannot be closed by a keypress meant for a sheet");

		root.raise(sheet);
		root.bands(null);

		says("only bands(null) takes it down", root.band == null && root.sheet == sheet,
			"cleared on purpose, with the sheet still where it was");
	}

	static function notices():Void {
		final root = shaped();
		root.resize(800, 600);
		root.flow = Flow.None;

		final session = new mdd.app.Session(new mdd.song.Song());
		final update = new mdd.app.Update("owner/name", "0.1.0", "windows",
			"x86_64", false);

		update.read('{"tag_name":"v0.9.0","html_url":"https://example/rel","assets":['
			+ '{"name":"mdd-0.9.0-windows-x86_64-setup.exe",'
			+ '"browser_download_url":"https://example/setup"}]}');

		final notice = new mdd.view.overlay.Notice(session);
		notice.update = update;

		var took = 0;
		notice.onTake = function():Void took++;

		root.raise(notice);
		notice.arrive();
		notice.arrange(180, 200, 440, 190);

		says("the update notice is the sheet", root.sheet == notice && root.focus == notice,
			"raised and focused, so the keyboard reaches it");

		root.advance(1);
		root.advance(1);

		says("and it fades all the way in", notice.fade.value > 0.99
			&& notice.rise.value > 0.99,
			"fade " + round(notice.fade.value, 2) + ", rise "
			+ round(notice.rise.value, 2));

		final wide = (440 - root.metrics.inset * 2 - root.metrics.gap * 2) / 3;
		final tall = root.metrics.whole(32);
		final middle = 200 + 190 - root.metrics.inset - tall * 0.5;

		final first = notice.buttonAt(180 + root.metrics.inset + wide * 0.5, middle);
		final last = notice.buttonAt(180 + 440 - root.metrics.inset - wide * 0.5, middle);
		final above = notice.buttonAt(400, 220);

		says("its three buttons are where it draws them",
			first == 0 && last == 2 && above < 0,
			"take, later and never, and nothing above the row");

		notice.press(0);

		says("taking the update asks for it and closes", took == 1 && root.sheet == null,
			"one request, and the notice is down");

		root.raise(notice);
		notice.press(mdd.view.overlay.Notice.LATER);

		says("and leaving it stops the updater asking again",
			update.state() == mdd.app.Update.CURRENT && root.sheet == null,
			"nothing is downloaded and nothing asks twice");
	}

	static function saying():Void {
		final words = new Translation();

		final taken = words.read("# a comment\n"
			+ "menu.file = File\n"
			+ "  menu.edit  =  Edit  \n"
			+ "\n"
			+ "broken line without a mark\n"
			+ "theme.rack = Rack\n");

		says("a table reads", taken == 3 && words.count() == 3
			&& words.named("menu.edit") == "Edit",
			taken + " lines taken, a comment and a line with no mark skipped");

		words.forget();
		final absent = words.of(words.count() + 5);

		says("an id past the end says nothing", absent == "" && words.missing == 1,
			"a key the catalogue has no string for comes back empty and is counted, "
			+ words.missing + " missing");

		final again = new Translation();
		again.read(words.write());

		says("a table writes what it read", again.count() == words.count()
			&& again.named("theme.rack") == "Rack",
			again.count() + " keys survive being written and read back");

	}

	static function modal():Void {
		final root = shaped();
		root.resize(800, 600);
		root.flow = Flow.None;

		final under = new Button("under");
		root.top.add(under);
		root.top.arrange(0, 0, 800, 600);
		under.arrange(0, 0, 800, 600);

		final sheet = new Widget();
		sheet.focusable = true;
		sheet.opaque = true;

		root.raise(sheet);
		sheet.arrange(200, 120, 400, 360);

		says("a sheet takes the room", root.sheet == sheet && root.focus == sheet
			&& root.scrim.value > 0.6,
			"raised, focused, and the scrim behind it is at "
			+ round(root.scrim.value * 100, 0) + " per cent");

		final inside = root.pick(400, 300);
		final outside = root.pick(10, 10);

		says("and nothing under it is reachable", inside == sheet && outside == sheet,
			"every point picks the sheet rather than what it covers");

		root.key(true, Key.Escape, Mod.None);

		says("escape lowers it", root.sheet == null && root.scrim.value == 0,
			"the sheet is gone and the scrim with it");

		root.raise(sheet);
		sheet.arrange(200, 120, 400, 360);
		root.pressed(400, 300, Pointer.Left, Mod.None);
		root.released(400, 300, Pointer.Left, Mod.None);

		says("and a press inside it is the sheet's", root.sheet == sheet,
			"a press on the sheet reaches it rather than closing it");

		root.pressed(10, 10, Pointer.Left, Mod.None);

		says("and a press outside lowers it", root.sheet == null,
			"clicking the scrim closes the one modal the application has");
	}

	static function motions():Void {
		final start = Motion.ease(0);
		final half = Motion.ease(0.5);
		final end = Motion.ease(1);

		says("ease out cubic", Math.abs(start) < 1e-6 && Math.abs(half - 0.875) < 1e-6
			&& Math.abs(end - 1) < 1e-6,
			"0, " + round(half, 3) + " half way, 1");

		says("leaving is faster", Math.abs(Motion.leaving(Motion.ENTER) - 0.126) < 1e-6,
			"enters in " + Math.round(Motion.ENTER * 1000) + " ms, leaves in "
			+ Math.round(Motion.leaving(Motion.ENTER) * 1000));

		final root = shaped();
		root.resize(400, 300);

		final fade = new Motion(null, 0, false);
		root.start(fade, 1, Motion.ENTER);
		final began = root.animating();

		root.advance(0.090);
		final midway = fade.value;

		root.advance(0.090);
		final landed = fade.value;
		final left = root.animating();

		says("motion runs", began == 1 && Math.abs(midway - 0.875) < 1e-6 && landed == 1
			&& left == 0,
			"at half the time " + round(midway, 3) + ", landed on " + landed + ", "
			+ left + " running");

		final none = shaped();
		none.flow = Flow.None;

		final jump = new Motion(null, 0, false);
		none.start(jump, 1, Motion.ENTER);

		says("motion none", jump.value == 1 && !jump.running && none.animating() == 0,
			"jumped to 1 with nothing left running");

		final less = shaped();
		less.flow = Flow.Reduced;

		final slide = new Motion(null, 0, true);
		final dim = new Motion(null, 0, false);
		less.start(slide, 1, Motion.ENTER);
		less.start(dim, 1, Motion.ENTER);

		says("motion reduced", slide.value == 1 && !slide.running && dim.running
			&& less.animating() == 1,
			"movement jumped, opacity still running");
	}

	static function trees():Void {
		final root = shaped();
		root.resize(300, 400);

		final tree = new Tree();
		tree.rowHeight = 20;
		root.top.add(tree);
		root.top.arrange(0, 0, 300, 400);
		tree.arrange(0, 0, 300, 400);

		final bank = new Item("Sonic The Hedgehog");
		bank.add(new Item("Lead", Theme.FM1));
		bank.add(new Item("Bass", Theme.FM5));
		bank.add(new Item("Brass", Theme.FM3));

		final later = new Item("Sonic The Hedgehog 2");
		later.add(new Item("Organ", Theme.FM2));

		tree.plant(bank);
		tree.plant(later);

		final opened = tree.rows();
		tree.fold(bank, false);
		final folded = tree.rows();

		says("tree folds", opened == 6 && folded == 3,
			opened + " rows with both banks open, " + folded + " with one shut");

		says("tree height", tree.contentHeight == folded * 20,
			"content is " + tree.contentHeight + " tall for " + folded + " rows of 20");

		root.pressed(6, 10, Pointer.Left, Mod.None);
		root.released(6, 10, Pointer.Left, Mod.None);

		says("tree chevron", bank.open && tree.rows() == 6,
			"a click on the chevron reopened the bank");

		root.focusOn(tree);
		tree.choose(bank);

		root.key(true, Key.Down, Mod.None);
		final onLead = tree.chosen != null && tree.chosen.label == "Lead";

		root.key(true, Key.Left, Mod.None);
		final onBank = tree.chosen == bank;

		root.key(true, Key.Left, Mod.None);

		says("tree keys", onLead && onBank && !bank.open,
			"down to a preset, left to its bank, left again shuts it");
	}

	static function menus(renderer:cpp.Star<Canvas>, target:cpp.Star<Texture>, face:String,
			monoFace:String):Void {
		final body = Font.bake(renderer, face, 13);
		final mono = Font.bake(renderer, monoFace, 12);

		if (body == null || mono == null) {
			says("menu opens", false, "the fonts would not bake");
			return;
		}

		final metrics = new Metrics(1);
		metrics.dress(body, body, mono, mono);

		final top = new Widget();
		final root = new Root(top, metrics, new Theme());
		root.flow = Flow.None;
		root.resize(400, 300);
		top.arrange(0, 0, 400, 300);

		final velocity = new Menu();
		velocity.offer(new Choice("Set to 100"));
		velocity.offer(new Choice("Randomise"));

		final menu = new Menu();
		menu.offer(new Choice("Cut", "Ctrl+X"));
		menu.offer(new Choice("Copy", "Ctrl+C"));
		menu.offer(new Choice("Paste", "Ctrl+V"));
		menu.divide();

		final deeper = menu.offer(new Choice("Velocity"));
		deeper.submenu = velocity;

		final off = menu.offer(new Choice("Quantise", "Ctrl+Q"));
		off.enabled = false;
		off.reason = "no notes are selected";

		menu.divide();
		menu.offer(new Choice("Explain the warning"));

		var chosen = "";
		menu.onChoose = function(choice:Choice):Void chosen = choice.label;

		root.pop(menu, 20, 20);

		says("menu opens", root.popups.length == 1 && root.focus == menu,
			"one popup, focused, " + menu.commands() + " commands");

		says("menu ceiling", !menu.crowded() && menu.commands() == 6,
			menu.commands() + " commands of " + Menu.CEILING + ", separators excluded");

		final tallRow = menu.topOf(6) - menu.topOf(5);
		says("menu reason", tallRow == metrics.row + metrics.whole(16) && !off.pickable(),
			"the disabled row is " + tallRow + " tall, carrying its reason");

		menu.fire(5);
		says("menu disabled", chosen == "", "a disabled command does not fire");

		final rowY = menu.y + menu.topOf(4) + 4;
		root.moved(menu.x + 20, rowY, Mod.None);

		root.advance(0.150);
		final early = root.popups.length;

		root.advance(0.100);
		final late = root.popups.length;

		says("submenu dwell", early == 1 && late == 2,
			early + " popup at 150 ms, " + late + " at 250");

		final paint = Paint.on(renderer, body);
		Draw.setTarget(renderer, target);
		Sdl.renderClear(renderer, 0, 0, 0, 1);
		Draw.resetCalls();
		root.frame(paint);
		final drawn = Draw.calls();
		Draw.setTarget(renderer, null);

		says("menu paints", drawn >= 1, drawn + " draw calls with two menus open");

		root.dismiss();
		root.pop(menu, 20, 20);

		root.key(true, Key.Down, Mod.None);
		final first = menu.hoverAt;

		root.key(true, Key.Down, Mod.None);
		root.key(true, Key.Down, Mod.None);
		root.key(true, Key.Down, Mod.None);
		final past = menu.hoverAt;

		root.key(true, Key.Down, Mod.None);
		final skipped = menu.hoverAt;

		says("menu keys", first == 0 && past == 4 && skipped == 7,
			"down lands on " + first + ", then " + past + " past the divider, then "
			+ skipped + " past the disabled one");

		root.key(true, Key.Return, Mod.None);
		says("menu fires", chosen == "Explain the warning" && root.popups.length == 0,
			"chose it and closed " + root.popups.length + " popups");

		root.pop(menu, 395, 10);
		says("menu flips", menu.x + menu.width <= 400.5 && menu.x < 395,
			"anchored at 395 of 400, drawn from " + menu.x + " to " + (menu.x + menu.width));

		root.pressed(2, 290, Pointer.Left, Mod.None);
		says("menu dismissed", root.popups.length == 0, "a press outside closes it");

		body.shut();
		mono.shut();
	}

	static function tooltips(renderer:cpp.Star<Canvas>, face:String, monoFace:String):Void {
		final body = Font.bake(renderer, face, 13);
		final mono = Font.bake(renderer, monoFace, 12);

		if (body == null || mono == null) {
			says("tooltip delay", false, "the fonts would not bake");
			return;
		}

		final metrics = new Metrics(1);
		metrics.dress(body, body, mono, mono);

		final top = new Widget();
		final root = new Root(top, metrics, new Theme());
		root.flow = Flow.None;
		root.resize(400, 300);
		top.arrange(0, 0, 400, 300);

		final play = new Button("");
		play.tip = "Play";
		play.shortcut = "Space";
		top.add(play);
		play.arrange(20, 20, 40, 30);

		final level = new Button("");
		level.tip = "Total level";
		level.detail = "register 4A, value 23, minus 17.25 dB";
		top.add(level);
		level.arrange(20, 240, 40, 30);

		final bare = new Button("");
		top.add(bare);
		bare.arrange(200, 20, 40, 30);

		root.moved(30, 30, Mod.None);
		root.advance(0.400);
		final early = root.tipUp;

		root.advance(0.100);

		says("tooltip delay", !early && root.tipUp,
			"nothing at 400 ms of stillness, shown at 500");

		says("tooltip below", root.tooltip.y >= play.y + play.height && root.tooltip.x >= play.x,
			"below and right of the control, at " + root.tooltip.x + ", " + root.tooltip.y);

		root.pressed(30, 30, Pointer.Left, Mod.None);
		final afterPress = root.tipUp;
		root.released(30, 30, Pointer.Left, Mod.None);

		root.moved(210, 30, Mod.None);
		root.advance(1.0);

		says("tooltip dismissed", !afterPress && !root.tipUp,
			"a press closes it, and a control with no tip never opens one");

		root.moved(30, 30, Mod.None);
		root.advance(0.500);
		final again = root.tipUp;

		root.moved(210, 30, Mod.None);
		final closed = !root.tipUp;

		root.moved(30, 250, Mod.None);
		root.advance(0.050);

		says("tooltip grace", again && closed && root.tipUp,
			"the next one inside 250 ms shows without waiting again");

		says("tooltip flips", root.tooltip.y + root.tooltip.height <= level.y,
			"flipped above the control at the bottom edge, at " + root.tooltip.y);

		root.pressed(30, 250, Pointer.Left, Mod.None);
		root.moved(35, 255, Mod.None);
		root.advance(1.0);

		says("tooltip drag", !root.tipUp, "none while a drag holds the pointer");

		body.shut();
		mono.shut();
	}

	static function collapse():Void {
		final metrics = new Metrics(1);
		final shell = new Shell();
		final root = new Root(shell, metrics, new Theme());

		root.resize(1400, 900);
		shell.fit(metrics);
		shell.arrange(0, 0, 1400, 900);

		final wide = shell.zone(Shell.RAIL).width;

		shell.open(Shell.RAIL, false);
		root.advance(0.090);
		shell.arrange(0, 0, 1400, 900);

		final midway = shell.zone(Shell.RAIL).width;
		final fading = shell.share(Shell.RAIL);

		root.advance(0.090);
		shell.arrange(0, 0, 1400, 900);

		final shut = shell.zone(Shell.RAIL).width;

		says("zone collapses", wide == 268 && midway > 24 && midway < wide && shut == 24
			&& fading > 0 && fading < 1,
			wide + " wide, " + midway + " half way through, " + shut + " shut");

		says("zone fades", Math.abs(fading - 0.125) < 1e-6 && shell.share(Shell.RAIL) == 0,
			"contents at " + round(fading, 3) + " half way, 0 when shut");

		shell.open(Shell.RAIL, true);
		root.advance(1.0);
		shell.arrange(0, 0, 1400, 900);

		says("zone reopens", shell.zone(Shell.RAIL).width == 268 && shell.share(Shell.RAIL) == 1
			&& root.animating() == 0,
			"back to " + shell.zone(Shell.RAIL).width + " with nothing left running");

		final still = new Shell();
		final quiet = new Root(still, new Metrics(1), new Theme());
		quiet.flow = Flow.Reduced;
		quiet.resize(1400, 900);
		still.fit(quiet.metrics);
		still.arrange(0, 0, 1400, 900);

		still.open(Shell.RAIL, false);
		still.arrange(0, 0, 1400, 900);

		says("zone reduced", still.zone(Shell.RAIL).width == 24 && quiet.animating() == 0,
			"snaps to " + still.zone(Shell.RAIL).width + " with motion reduced");
	}

	static function bars(renderer:cpp.Star<Canvas>, face:String, monoFace:String):Void {
		final body = Font.bake(renderer, face, 13);
		final mono = Font.bake(renderer, monoFace, 12);

		if (body == null || mono == null) {
			says("bar opens", false, "the fonts would not bake");
			return;
		}

		final metrics = new Metrics(1);
		metrics.dress(body, body, mono, mono);

		final top = new Widget();
		final root = new Root(top, metrics, new Theme());
		root.flow = Flow.None;
		root.resize(600, 400);
		top.arrange(0, 0, 600, 400);

		final bar = new MenuBar();
		top.add(bar);
		bar.arrange(0, 0, 600, 30);

		final file = new Menu();
		file.offer(new Choice("New", "Ctrl+N"));
		file.offer(new Choice("Open", "Ctrl+O"));

		final edit = new Menu();
		edit.offer(new Choice("Undo", "Ctrl+Z"));

		bar.offer("File", file);
		bar.offer("Edit", edit);

		final fileAt = bar.penOf(0) + 4;
		final editAt = bar.penOf(1) + 4;

		root.pressed(fileAt, 15, Pointer.Left, Mod.None);
		root.released(fileAt, 15, Pointer.Left, Mod.None);

		says("bar opens", bar.openAt == 0 && root.popups.length == 1
			&& root.popups[0] == file,
			"clicking File opened its menu under it at " + root.popups[0].x);

		root.pressed(editAt, 15, Pointer.Left, Mod.None);
		root.released(editAt, 15, Pointer.Left, Mod.None);

		says("bar switches", bar.openAt == 1 && root.popups.length == 1
			&& root.popups[0] == edit,
			"one click on Edit swapped the open menu");

		root.pressed(editAt, 15, Pointer.Left, Mod.None);
		root.released(editAt, 15, Pointer.Left, Mod.None);

		says("bar closes", bar.openAt == -1 && root.popups.length == 0,
			"clicking the open title again closed it");

		root.pressed(fileAt, 15, Pointer.Left, Mod.None);
		root.released(fileAt, 15, Pointer.Left, Mod.None);
		root.moved(editAt, 15, Mod.None);

		says("bar hovers", bar.openAt == 1 && root.popups[0] == edit,
			"moving along the bar with one open follows the pointer");

		root.pressed(300, 300, Pointer.Left, Mod.None);

		says("bar released", bar.openAt == -1 && root.popups.length == 0,
			"a press in the body closed it and cleared the bar");

		body.shut();
		mono.shut();
	}
}
