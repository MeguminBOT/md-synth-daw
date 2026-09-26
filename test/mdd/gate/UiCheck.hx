package mdd.gate;

import haxe.ds.Vector;
import mdd.host.Canvas;
import mdd.host.Draw;
import mdd.host.Native;
import mdd.host.Sdl;
import mdd.host.Texture;
import mdd.ui.control.Button;
import mdd.ui.control.Choice;
import mdd.ui.control.Dropdown;
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
import mdd.ui.Range;
import mdd.ui.Scroll;
import mdd.ui.Sheet;
import mdd.ui.control.Slider;
import mdd.ui.control.Table;
import mdd.ui.control.Tabs;
import mdd.ui.control.Toggle;
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
		stuck();
		asked();
		used();
		editing();
		numbers();
		gestures();
		united();
		slotted();
		ranges();
		switches();
		scrolling();
		tables();
		marquee();
		motions();
		trees();
		shrunk();
		slowed();
		menus(renderer, target, face, monoFace);
		dropdowns(renderer, face, monoFace);
		refilled();
		tooltips(renderer, face, monoFace);
		bars(renderer, face, monoFace);
		shortcuts();
		saying();
		modal();
		dimmed();
		questions();
		banded();
		notices();
		remembers();
		updates();
		shells(renderer, face, monoFace);
		collapse();
		quiet(renderer, target, face, monoFace);
		sheets(renderer, target, face, monoFace);
		chooses();
		crowded(renderer, face, monoFace);
		envelopes();
		exports();

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

	/**
		The import sheet takes what is chosen on it.

		Every part of a row is worked out from where it was pressed rather than from a
		widget that knows where it is, so the arithmetic is the thing worth driving.
	**/
	static function chooses():Void {
		final root = shaped();
		root.resize(800, 600);
		root.flow = Flow.None;
		root.top.arrange(0, 0, 800, 600);

		final sheet = new mdd.view.overlay.Importing();
		final strands:Array<mdd.format.Strand> = [];

		for (channel in 0...3) {
			final strand = new mdd.format.Strand(channel, channel);

			strand.name = "strand " + channel;
			strand.part = channel;
			strand.counts(60, 96);

			strands.push(strand);
		}

		var took:Array<mdd.format.Strand> = [];
		sheet.onImport = function(held:Array<mdd.format.Strand>):Void took = held;

		root.raise(sheet);
		sheet.ask("held.mid", strands);
		sheet.arrange(80, 60, 640, 400);

		final metrics = root.metrics;
		final row = sheet.y + sheet.head() + sheet.bandTall() + sheet.rowTall() * 0.5;
		final chooser = sheet.chooserAt(metrics);

		poked(root, sheet.x + 5, row);

		says("a press anywhere on a row turns that row off",
			!strands[0].taken && strands[1].taken && sheet.taking() == 2,
			"the first strand is left behind and " + sheet.taking() + " are still taken");

		poked(root, sheet.x + 5, row);
		poked(root, chooser + metrics.whole(mdd.view.overlay.Importing.CHOOSER) - 4, row);

		final up = strands[0].part;

		poked(root, chooser + 4, row);
		poked(root, chooser + 4, row);

		says("and the chooser steps the part either way",
			up == 1 && strands[0].part == mdd.song.Part.COUNT - 1,
			"it went up to " + up + " and then down past nought to " + strands[0].part);

		final second = sheet.y + sheet.head() + sheet.bandTall()
			+ sheet.rowTall() * 1.5;

		poked(root, sheet.x + 5, second);

		says("and a row is told apart from the one under it",
			!strands[1].taken && strands[2].taken,
			"the second row turned off and the third was left alone");

		poked(root, sheet.x + sheet.width - metrics.inset - 10,
			sheet.y + sheet.head() + sheet.bandTall() * 0.5);

		says("and where it lands is its own row",
			sheet.lands == mdd.view.overlay.Importing.INSTEAD,
			"the far side of the band chose a piece of its own");

		for (strand in strands) strand.taken = false;
		poked(root, sheet.go.x + sheet.go.width * 0.5,
			sheet.go.y + sheet.go.height * 0.5);

		says("and nothing is imported where nothing is taken", took.length == 0,
			"the button did nothing with every row turned off");

		strands[2].taken = true;
		poked(root, sheet.go.x + sheet.go.width * 0.5,
			sheet.go.y + sheet.go.height * 0.5);

		says("and what was taken reaches the import", took.length == 3
			&& took[2].taken && !took[0].taken,
			"the sheet handed over all three rows with the one that was ticked marked");
	}

	/**
		Presses and releases at a point, which is what a click is.

		@param root The root to send it through.
		@param px Where, across.
		@param py Where, down.
	**/
	static function poked(root:Root, px:Float, py:Float):Void {
		root.pressed(px, py, Pointer.Left, Mod.None);
		root.released(px, py, Pointer.Left, Mod.None);
	}

	/**
		A menu with more in it than the window is tall stays inside the window and every
		entry can still be reached.

		The icon chooser is the one that bites: it offers every icon there is, which is
		longer than any window, and a menu that simply drew them all ran off the bottom
		with no way to get at what was down there.

		@param renderer What to bake the faces with.
		@param face The text face.
		@param monoFace The fixed width face.
	**/
	static function crowded(renderer:cpp.Star<Canvas>, face:String,
			monoFace:String):Void {
		final body = Font.bake(renderer, face, 13);
		final mono = Font.bake(renderer, monoFace, 12);

		if (body == null || mono == null) {
			says("a long menu stays in the window", false, "the fonts would not bake");
			return;
		}

		final metrics = new Metrics(1);
		metrics.dress(body, body, mono, mono, body);

		final top = new Widget();
		final root = new Root(top, metrics, new Theme());

		root.flow = Flow.None;
		root.resize(400, 300);
		top.arrange(0, 0, 400, 300);

		final menu = new Menu();
		final many = 60;

		for (index in 0...many) menu.offer(new Choice("entry " + index));

		root.pop(menu, 10, 10);

		says("a menu longer than the window stays inside it",
			menu.height <= 300 && menu.y >= 0 && menu.y + menu.height <= 300,
			"sixty entries draw " + Math.round(menu.height) + " tall at " + Math.round(menu.y)
			+ " in a window of 300");

		final first = menu.rowAt(menu.y + metrics.unit + metrics.row * 0.5);

		root.moved(menu.x + 10, menu.y + 10, Mod.None);
		root.turned(0, -1, Mod.None);

		final after = menu.rowAt(menu.y + metrics.unit + metrics.row * 0.5);

		says("and the wheel moves it", first == 0 && after > 0,
			"the top entry was " + first + " and is " + after + " after one turn");

		var guard = 0;

		while (menu.rowAt(menu.y + menu.height - metrics.row * 0.5) < many - 1
				&& guard < 200) {
			root.turned(0, -1, Mod.None);
			guard++;
		}

		final last = menu.rowAt(menu.y + menu.height - metrics.row * 0.5);

		says("and the last entry can be reached", last == many - 1,
			"the bottom of the menu reads entry " + last + " of " + (many - 1)
			+ " after " + guard + " turns");

		final outside = menu.rowAt(menu.y + menu.height + 20);

		says("and nothing below it answers", outside == -1,
			"a point under the menu belongs to no entry");

		root.dismiss();
	}

	/**
		An operator's envelope is drawn inside its own box, at every end of every range the editor
		lets a field reach. The line has a thickness of its own, so a patch loud enough to reach the
		top of the box would draw half that line above it, and a release rate past what the chip
		takes would draw its release backwards and pull the rest of the curve out of the box.
	**/
	static function envelopes():Void {
		final root = shaped();
		root.resize(1280, 720);

		final session = new mdd.app.Session(new mdd.song.Song());
		final editor = new mdd.view.editor.FmEditor(session);

		root.top.add(editor);
		editor.arrange(0, 0, 520, 700);

		final patch = new mdd.song.Patch();
		final box = new Vector<Float>(4);
		final points = new Vector<Float>(10);
		final hair = root.metrics.whole(2) * 0.5;

		patch.algorithm = 7;

		var outside = 0;
		var worst = 0.0;
		var stopped = -1;

		for (pass in 0...3) {
			final loudest = pass != 1;

			for (slot in 0...mdd.song.Patch.SLOTS) {
				for (row in 0...mdd.song.Patch.ROWS) {
					final most = mdd.song.Patch.mostOf(row);
					final slowest = pass == 2 && (row == 2 || row == 4);

					patch.writes(slot, row, slowest || loudest == (row == 0) ? 0 : most + 1);
				}
			}

			if (pass == 0) stopped = patch.release[0];

			for (slot in 0...mdd.song.Patch.SLOTS) {
				editor.boxAt(slot, box);
				editor.envelopeAt(slot, patch, points);

				for (index in 0...5) {
					final px = points[index * 2];
					final py = points[index * 2 + 1];

					final over = [box[0] - (px - hair), (px + hair) - (box[0] + box[2]),
						box[1] - (py - hair), (py + hair) - (box[1] + box[3])];

					for (much in over) {
						if (much <= 0.001) continue;

						outside++;
						if (much > worst) worst = much;
					}
				}
			}
		}

		says("an envelope stays in its box", outside == 0 && stopped == 15,
			outside == 0 ? "every point of all 12 envelopes drawn, with every field pushed past both ends"
			+ " of its range and with both decays slowest under the fastest release, sits inside its"
			+ " box with room for the line's thickness, and a release rate stops at " + stopped
			: outside + " points reach past it, the worst by " + round(worst, 2));
	}

	/**
		The export sheets fit a screen no larger than the ones people still work on. The rows
		scroll where they do not, so a longer list than this one still reaches its buttons.
	**/
	static function exports():Void {
		final session = new mdd.app.Session(new mdd.song.Song());
		var tight = 0;
		var said = "";

		for (video in [false, true]) {
			for (screen in [[1280.0, 720.0], [1366.0, 768.0]]) {
				final root = shaped();
				root.resize(screen[0], screen[1]);

				final sheet = new mdd.view.overlay.Export(session, video);
				root.raise(sheet);
				sheet.ask();
				sheet.measure(screen[0], screen[1]);

				final wide = sheet.wantWidth;
				final tall = sheet.wantHeight;

				sheet.arrange((screen[0] - wide) * 0.5, (screen[1] - tall) * 0.5, wide, tall);
				sheet.scrollTo(1000000);

				final reaches = sheet.content() <= sheet.room() + 0.5
					|| sheet.room() + sheet.scrolled() >= sheet.content() - 0.5;

				if (tall > screen[1] - root.metrics.whole(48) || wide > screen[0] || !reaches) tight++;

				said += (video ? "video" : "audio") + " " + Math.round(screen[0]) + "x"
					+ Math.round(screen[1]) + " wants " + Math.round(tall) + " tall"
					+ (sheet.content() > sheet.room() ? " and scrolls" : "") + "; ";
			}
		}

		says("an export sheet fits a small screen", tight == 0, said);
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

	static function stuck():Void {
		final root = shaped();
		root.resize(400, 300);

		final field = new Field("drag");
		root.top.add(field);
		root.top.arrange(0, 0, 400, 300);
		field.arrange(0, 0, 100, 30);

		final leftHeld = 1;

		root.pressed(20, 10, Pointer.Left, Mod.None);
		root.moved(60, 10, Mod.None, leftHeld);
		final going = root.capture == field;

		root.moved(80, 10, Mod.None, 0);
		final ended = root.capture == null;

		root.pressed(20, 10, Pointer.Left, Mod.None);
		root.moved(60, 10, Mod.None, Root.UNKNOWN_BUTTONS);
		final again = root.capture == field;

		root.lets();
		final let = root.capture == null;

		says("a release that never arrives", going && ended && again && let,
			"a move with no button held ends the drag, and so does losing the focus");
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

		number.typed = function(said:String):Null<Int> {
			final read = Std.parseFloat(said);
			return Math.isNaN(read) ? null : Math.round(read * 20);
		};

		number.set(0);

		root.focusOn(number);
		root.pressed(20, 20, Pointer.Left, Mod.None, 2);
		root.released(20, 20, Pointer.Left, Mod.None);

		root.said("2", Mod.None);
		root.key(true, Key.Return, Mod.None);

		says("a number is typed in what it is shown in", number.value == 40,
			"a field held in twentieths of a second reads a typed 2 as " + number.value
			+ ", which is two seconds, rather than as a tenth of one");

		root.pressed(20, 20, Pointer.Left, Mod.None, 2);
		root.released(20, 20, Pointer.Left, Mod.None);
		root.said("3", Mod.None);

		final other = new Number("", 0, 0, 10);
		root.top.add(other);
		other.arrange(120, 0, 90, 40);
		root.focusOn(other);

		says("and typing ends when the keyboard goes elsewhere",
			number.value == 60,
			"the 3 that was typed landed as " + number.value
			+ ", where 40 would mean the caret was left sitting in the field");
	}

	/**
		A number shows its unit after its value, and a number that words its own value shows only
		those words.
	**/
	static function united():Void {
		final plain = new Number("Turn", 45, 0, 359);
		final turned = new Number("Turn", 45, 0, 359);
		final worded = new Number("Turn", 45, 0, 359);

		turned.unit = "°";
		worded.unit = " px";
		worded.derived = function(value:Int):String return value + " px";

		says("a number shows its unit", plain.shown() == "45" && turned.shown() == "45°"
			&& worded.shown() == "45 px",
			"45 reads '" + plain.shown() + "' with no unit, '" + turned.shown() + "' in degrees and '"
			+ worded.shown() + "' where it words itself");
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

		final moved = shell.divider(Shell.RAIL);

		says("and the pointer says it can be", shell.cursorAt(moved, 400)
			== mdd.host.Sdl.CURSOR_ACROSS
			&& shell.cursorAt(moved + 40, 400) == mdd.host.Sdl.CURSOR_ARROW,
			"the arrow across over the seam and the ordinary one a pane away from it");

		says("and the band beats the hairline",
			shell.cursorAt(moved - 3, 400) == mdd.host.Sdl.CURSOR_ACROSS
			&& shell.cursorAt(moved + 3, 400) == mdd.host.Sdl.CURSOR_ACROSS,
			"a hairline nobody can hit answers to three pixels either side of itself");
	}

	static function sheets(renderer:cpp.Star<Canvas>, target:cpp.Star<Texture>, face:String,
			monoFace:String):Void {
		final body = Font.bake(renderer, face, 13);
		if (body == null) {
			says("sheet caching", false, "the font would not bake");
			return;
		}

		final metrics = new Metrics(1);
		metrics.dress(body, body, body, body, body);

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
		metrics.dress(body, body, mono, mono, body);

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
		settings.put("song", "C:/music/a song.mdsyn");

		says("and it writes", settings.save() && sys.FileSystem.exists(path),
			settings.count() + " settings written to " + path.substr(path.length - 12));

		final back = new mdd.host.Settings(path);
		back.load();

		says("and reads back", back.asWhole("theme") == 2 && back.asWhole("density") == 0
			&& !back.asFlag("ghosts", true) && back.asNumber("gain") == 0.75
			&& back.of("song") == "C:/music/a song.mdsyn",
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

		final ours = "MeguminBOT/md-synth-daw";

		held.read('{"tag_name":"v0.3.1","html_url":"https://example/rel",'
			+ '"body":"Faster import\nand other things","assets":['
			+ released(ours, "v0.3.1", "mdd-0.3.1-linux.tar.gz") + ","
			+ released(ours, "v0.3.1", "mdd-0.3.1-windows-portable.zip") + ","
			+ released(ours, "v0.3.1", "mdd-0.3.1-setup.exe") + "]}");

		says("and picks its own platform", held.offered == "0.3.1" && held.assets == 3
			&& held.saidAt == releasedAt(ours, "v0.3.1", "mdd-0.3.1-setup.exe"),
			"tag v0.3.1 reads as " + held.offered + ", and of " + held.assets
			+ " assets it took the windows installer");

		says("and takes the first line of the notes", held.notes == "Faster import",
			"the release body's first line is what the notice shows: " + held.notes);

		final split = '{"tag_name":"v0.4.0","html_url":"https://example/rel","assets":['
			+ [for (name in ["mdd-0.4.0-linux-x86_64-portable.tar.gz",
				"mdd-0.4.0-linux-arm64-portable.tar.gz", "mdd-0.4.0-linux-x86_64-installer.tar.gz",
				"mdd-0.4.0-linux-arm64-installer.tar.gz", "mdd-0.4.0-windows-x86_64-setup.exe",
				"mdd-0.4.0-mac-arm64.dmg", "mdd-0.4.0-mac-x86_64.dmg"])
				released("owner/name", "v0.4.0", name)].join(",") + "]}";

		final armed = new mdd.app.Update("owner/name", "0.1.0", "linux", "arm64", false);
		armed.read(split);

		final wide = new mdd.app.Update("owner/name", "0.1.0", "linux", "x86_64", false);
		wide.read(split);

		final apple = new mdd.app.Update("owner/name", "0.1.0", "mac", "arm64", false);
		apple.read(split);

		says("a release with both architectures gives each its own",
			armed.saidAt == releasedAt("owner/name", "v0.4.0", "mdd-0.4.0-linux-arm64-installer.tar.gz")
			&& wide.saidAt == releasedAt("owner/name", "v0.4.0", "mdd-0.4.0-linux-x86_64-installer.tar.gz")
			&& apple.saidAt == releasedAt("owner/name", "v0.4.0", "mdd-0.4.0-mac-arm64.dmg"),
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
			+ [for (name in ["mdd-0.5.0-windows-x86_64-portable.zip",
				"mdd-0.5.0-windows-x86_64-setup.exe", "mdd-0.5.0-linux-x86_64-portable.tar.gz",
				"mdd-0.5.0-linux-x86_64-installer.tar.gz", "mdd-0.5.0-mac-x86_64-portable.tar.gz",
				"mdd-0.5.0-mac-x86_64.dmg"])
				released("owner/name", "v0.5.0", name)].join(",") + "]}";

		final kinds:Array<{name:String, portable:Bool, wanted:String}> = [
			{name: "windows", portable: true, wanted: "mdd-0.5.0-windows-x86_64-portable.zip"},
			{name: "windows", portable: false, wanted: "mdd-0.5.0-windows-x86_64-setup.exe"},
			{name: "linux", portable: true, wanted: "mdd-0.5.0-linux-x86_64-portable.tar.gz"},
			{name: "linux", portable: false, wanted: "mdd-0.5.0-linux-x86_64-installer.tar.gz"},
			{name: "mac", portable: true, wanted: "mdd-0.5.0-mac-x86_64-portable.tar.gz"},
			{name: "mac", portable: false, wanted: "mdd-0.5.0-mac-x86_64.dmg"}
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

		says("and offers no page for a file", bare.offered == "0.2.0"
			&& bare.saidAt == "" && bare.assets == 0,
			"a release with no assets has nothing to download, so not even its page is"
			+ " offered in place of one");
	}

	/**
		@param repository The owner and the repository.
		@param tag The release's tag.
		@param name What the release calls a file.
		@return The file as a release document lists it, at the address GitHub serves it from.
	**/
	static function released(repository:String, tag:String, name:String):String {
		return '{"name":"' + name + '","browser_download_url":"' + releasedAt(repository, tag, name)
			+ '"}';
	}

	/**
		@param repository The owner and the repository.
		@param tag The release's tag.
		@param name What the release calls a file.
		@return Where GitHub serves that file from.
	**/
	static function releasedAt(repository:String, tag:String, name:String):String {
		return "https://github.com/" + repository + "/releases/download/" + tag + "/" + name;
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

	/**
		One sheet slot, and what that costs anything opening a dialog from a sheet.

		Raising a sheet puts away whatever sheet was there. Acting on most dialog
		answers raises the progress bar, so a sheet that opens a dialog and has to
		still be there afterwards, which is what the kit sheet is, needs its answer
		acted on without one. `Files.instant` is that list.
	**/
	static function slotted():Void {
		final root = new Root(new Shell(), new Metrics(1), new Theme());
		root.resize(900, 700);

		final first = new Widget();
		final second = new Widget();

		first.focusable = true;
		first.opaque = true;
		second.focusable = true;
		second.opaque = true;

		root.raise(first);
		root.raise(second);

		says("a second sheet puts the first away", root.sheet == second,
			"one slot, so what was there is gone rather than behind it");

		root.lower();

		says("and lowering it leaves nothing, not the first", root.sheet == null,
			"the one it replaced is not brought back");

		final held = [mdd.app.Files.READ_HIT, mdd.app.Files.READ_KIT];
		final rest = [mdd.app.Files.OPEN, mdd.app.Files.SAVE, mdd.app.Files.READ_MIDI,
			mdd.app.Files.READ_VGM, mdd.app.Files.READ_WAV];

		var kept = true;
		for (what in held) if (!mdd.app.Files.instant(what)) kept = false;
		for (what in rest) if (mdd.app.Files.instant(what)) kept = false;

		says("so what a sheet asks for is acted on without the progress bar", kept,
			held.length + " kinds feed a sheet that stays up and raise nothing, against "
				+ rest.length + " that do raise it");
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

	/**
		A sheet that dims the screen has to paint something.

		`raise` dims everything behind the sheet and hands it every click, so a sheet that
		paints nothing leaves a window nobody can use: dark, empty and deaf, with no sign
		of what is waiting. The update notice was raised that way, because the call that
		starts its fade does nothing until the widget has a root, and it was made before
		the raise that gives it one.

		The flow is left alone here on purpose. Without motion a fade jumps straight to
		its target and the fault cannot happen, so a check that turns motion off cannot
		see it.
	**/
	static function dimmed():Void {
		final root = shaped();
		root.resize(1280, 800);

		final session = mdd.app.Session.started(mdd.song.Library.embedded());

		final after = new mdd.view.overlay.Notice(session);
		root.raise(after);
		after.arrive();

		for (step in 0...20) root.advance(0.05);

		says("a sheet that dims is seen", after.fade.value > 0.004,
			"the scrim is at " + round(root.scrim.value * 100, 0) + " per cent and the sheet at "
			+ round(after.fade.value * 100, 0));

		final before = new mdd.view.overlay.Notice(session);
		before.arrive();
		root.raise(before);

		for (step in 0...20) root.advance(0.05);

		says("and one that arrived early", before.fade.value > 0.004,
			"arriving with no root behind it leaves it at "
			+ round(before.fade.value * 100, 0) + " per cent");
	}

	/**
		The question sheet gives one answer and then gives no more.

		Which answer a press lands on is worked out from where the row was drawn rather
		than from a widget that knows where it is, so the arithmetic is what is driven
		here, along with the two keys that answer without a pointer.
	**/
	static function questions():Void {
		final root = shaped();
		root.resize(1280, 800);

		final sheet = new mdd.view.overlay.Asking();
		root.raise(sheet);

		sheet.ask("chords", "some of these notes cannot sound",
			["move them", "remove them", "leave them"]);

		for (step in 0...20) root.advance(0.05);

		says("a question is seen", sheet.fade.value > 0.004,
			"the sheet is at " + round(sheet.fade.value * 100, 0) + " per cent");

		final metrics = root.metrics;
		final tall = metrics.whole(32);
		final middle = sheet.y + sheet.height - metrics.inset - tall * 0.5;
		final wide = (sheet.width - metrics.inset * 2 - metrics.gap * 2) / 3;

		var found = 0;

		for (which in 0...3) {
			final at = sheet.x + metrics.inset + which * (wide + metrics.gap) + wide * 0.5;
			if (sheet.answerAt(at, middle) == which) found++;
		}

		says("each answer is where it is drawn", found == 3,
			"three of three found, and above the row picks none at "
			+ sheet.answerAt(sheet.x + sheet.width * 0.5, sheet.y + metrics.inset));

		var given:Array<Int> = [];
		sheet.onAnswer = function(which:Int):Void given.push(which);

		final at = sheet.x + metrics.inset + (wide + metrics.gap) + wide * 0.5;

		root.pressed(at, middle, Pointer.Left, Mod.None);
		root.released(at, middle, Pointer.Left, Mod.None);

		says("pressing one gives that answer", given.length == 1 && given[0] == 1,
			"the middle answer came back as " + (given.length == 0 ? -1 : given[0]));

		sheet.gives(0);

		says("and it is answered only once", given.length == 1,
			"a second answer after the sheet closed added nothing");

		final after = new mdd.view.overlay.Asking();
		root.raise(after);
		after.ask("unsaved", "there are changes", ["save", "do not save", "cancel"]);

		var told = -1;
		after.onAnswer = function(which:Int):Void told = which;

		root.key(true, Key.Escape, Mod.None);

		says("escape answers the last", told == 2, "escape came back as " + told);

		final last = new mdd.view.overlay.Asking();
		root.raise(last);
		last.ask("unsaved", "there are changes", ["save", "do not save", "cancel"]);

		told = -1;
		last.onAnswer = function(which:Int):Void told = which;

		root.key(true, Key.Return, Mod.None);

		says("and enter answers the first", told == 0, "enter came back as " + told);
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
		metrics.dress(body, body, mono, mono, body);

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
		metrics.dress(body, body, mono, mono, body);

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

		says("tooltip flips", root.tooltip.y + root.tooltip.height <= 250
			&& root.tooltip.y >= 0,
			"flipped above the pointer near the bottom edge, at " + root.tooltip.y
			+ " and ending at " + (root.tooltip.y + root.tooltip.height));

		root.pressed(30, 250, Pointer.Left, Mod.None);
		root.moved(35, 255, Mod.None);
		root.advance(1.0);

		says("tooltip drag", !root.tipUp, "none while a drag holds the pointer");

		root.released(35, 255, Pointer.Left, Mod.None);
		root.resize(800, 600);
		top.arrange(0, 0, 800, 600);

		final broad = new Button("");
		broad.tip = "A panel that fills the window";
		top.add(broad);
		broad.arrange(0, 300, 800, 300);

		root.moved(500, 450, Mod.None);
		root.advance(1.0);

		final near = root.tipUp
			&& root.tooltip.x >= 500 && root.tooltip.x < 560
			&& root.tooltip.y >= 450 && root.tooltip.y < 500;

		says("a tooltip follows the pointer, not the corner of the widget", near,
			"the pointer is at 500, 450 inside a panel whose corner is 0, 300, and the"
				+ " tooltip is at " + Math.round(root.tooltip.x) + ", "
				+ Math.round(root.tooltip.y));

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

	/**
		A dropdown opens its whole list under it with the chosen entry ticked, takes the entry chosen
		from it, steps through it from the wheel and the keyboard without opening it, and keeps one
		width whichever entry it shows.

		@param renderer What the fonts are baked for.
		@param face The body font.
		@param monoFace The monospaced font.
	**/
	static function dropdowns(renderer:cpp.Star<Canvas>, face:String, monoFace:String):Void {
		final body = Font.bake(renderer, face, 13);
		final mono = Font.bake(renderer, monoFace, 12);

		if (body == null || mono == null) {
			says("a dropdown opens its list", false, "the fonts would not bake");
			return;
		}

		final metrics = new Metrics(1);
		metrics.dress(body, body, mono, mono, body);

		final top = new Widget();
		final root = new Root(top, metrics, new Theme());
		root.flow = Flow.None;
		root.resize(400, 300);
		top.arrange(0, 0, 400, 300);

		final names = ["Off", "3.98 Hz", "72.2 Hz"];
		final rate = new Dropdown("LFO", 0, names.length);
		var changes = 0;

		rate.named = function(value:Int):String return names[value];
		rate.onChange = function(from:Dropdown):Void changes++;

		top.add(rate);
		rate.measure(400, 28);
		rate.arrange(20, 20, rate.wantWidth, 28);

		final wide = rate.wantWidth;

		root.pressed(30, 30, Pointer.Left, Mod.None);
		root.released(30, 30, Pointer.Left, Mod.None);

		final list = root.popups.length == 1 ? root.popups[0] : null;
		var ticked = "";

		if (list != null) {
			for (index in 0...list.choices.length) if (list.choices[index].ticked) ticked += index;
		}

		says("a dropdown opens its list", list != null && rate.open() && list.choices.length == 3
			&& ticked == "0" && list.ticking && list.anchorY == rate.y + rate.height,
			root.popups.length + " popups open, holding " + (list == null ? 0 : list.choices.length)
			+ " entries with '" + ticked + "' ticked, anchored at "
			+ (list == null ? -1 : list.anchorY) + " under a field ending at " + (rate.y + rate.height));

		if (list != null) list.fire(2);

		final chosen = rate.value;
		final fired = changes;
		final shut = !rate.open() && root.opened() == 0;

		root.pressed(30, 30, Pointer.Left, Mod.None);
		root.released(30, 30, Pointer.Left, Mod.None);
		final reopened = root.opened() == 1;

		root.pressed(30, 30, Pointer.Left, Mod.None);
		root.released(30, 30, Pointer.Left, Mod.None);
		final toggled = root.opened() == 0;

		says("a dropdown takes what is chosen", chosen == 2 && fired == 1 && shut && reopened
			&& toggled,
			"the last entry left it on " + chosen + " after " + fired + " changes, the list "
			+ (shut ? "shut" : "stayed open") + ", and a press on the field "
			+ (reopened ? "opened it again" : "did not open it") + " and a second "
			+ (toggled ? "shut it" : "left it open"));

		root.focusOn(rate);
		root.moved(30, 30, Mod.None);
		root.turned(0, 1, Mod.None);
		final wheeled = rate.value;

		root.key(true, Key.Up, Mod.None);
		final raised = rate.value;

		root.key(true, Key.Up, Mod.None);
		final floored = rate.value;

		root.key(true, Key.Down, Mod.None);
		final lowered = rate.value;

		var widths = "";
		for (index in 0...names.length) {
			rate.set(index);
			rate.measure(400, 28);
			if (rate.wantWidth != wide) widths += names[index] + " " + rate.wantWidth + " ";
		}

		says("a dropdown steps without opening", wheeled == 1 && raised == 0 && floored == 0
			&& lowered == 1 && root.opened() == 0 && widths == "",
			"the wheel up went to " + wheeled + ", up to " + raised + " and again to " + floored
			+ ", down to " + lowered + ", " + root.opened() + " lists opened, and the width held at "
			+ wide + (widths == "" ? "" : " except for " + widths));

		body.shut();
		mono.shut();
	}

	/**
		A list scrolled down that shrinks under the view shows what is left of it rather than the
		empty space past its end, and grows back to where it was scrolled once it returns.
	**/
	static function shrunk():Void {
		final root = shaped();
		final tree = new Tree();

		root.top.add(tree);
		root.resize(400, 300);
		root.top.arrange(0, 0, 400, 300);

		tree.rowHeight = 20;
		tree.arrange(0, 0, 200, 100);

		for (row in 0...50) tree.plant(new Item("row " + row));
		tree.scrollTo(600);
		final far = tree.offsetY;

		tree.clear();
		for (row in 0...3) tree.plant(new Item("found " + row));
		final few = tree.offsetY;
		final first = tree.rowAt(5);

		tree.clear();
		for (row in 0...20) tree.plant(new Item("found " + row));
		final some = tree.offsetY;

		tree.clear();
		for (row in 0...50) tree.plant(new Item("row " + row));
		final back = tree.offsetY;

		says("a shrunk list shows its rows", far == 600 && few == 0 && first == 0
			&& some == 300 && back == 600,
			"scrolled to " + far + ", three rows put the view at " + few + " with row " + first
			+ " at the top, twenty at " + some + " against a last page at 300, and fifty again at "
			+ back);
	}

	/**
		A widget that asks for precision gets the pointer slowed while Ctrl is held in a drag of it,
		the real pointer is asked to follow, and the motion that move causes is not read as the
		hand moving. One that does not ask gets the pointer as it is.
	**/
	static function slowed():Void {
		final root = shaped();
		final fine = new Widget();
		final plain = new Widget();
		final seen:Array<Float> = [];
		final warped:Array<Float> = [];

		fine.precision = 4;

		root.top.add(fine);
		root.top.add(plain);
		root.resize(400, 300);
		root.top.arrange(0, 0, 400, 300);
		fine.arrange(0, 0, 200, 300);
		plain.arrange(200, 0, 200, 300);

		root.onWarp = function(x:Float, y:Float):Void {
			warped.push(x);
			warped.push(y);
		};

		root.pressed(100, 100, Pointer.Left, Mod.None);
		root.moved(140, 100, Mod.Ctrl);
		seen.push(root.pointerX);

		root.moved(110, 100, Mod.Ctrl);
		seen.push(root.pointerX);

		root.moved(150, 100, Mod.Ctrl);
		seen.push(root.pointerX);

		root.moved(120, 100, Mod.Ctrl);
		root.moved(130, 100, Mod.None);
		seen.push(root.pointerX);
		root.released(130, 100, Pointer.Left, Mod.None);

		root.pressed(300, 100, Pointer.Left, Mod.None);
		root.moved(340, 100, Mod.Ctrl);
		final free = root.pointerX;
		root.released(340, 100, Pointer.Left, Mod.None);

		says("ctrl slows a precise drag", seen[0] == 110 && seen[1] == 110 && seen[2] == 120
			&& seen[3] == 130 && warped.length == 4 && warped[0] == 110 && warped[2] == 120
			&& free == 340,
			"40 px with ctrl read as " + (seen[0] - 100) + ", the echo of the warp to " + warped[0]
			+ " as " + (seen[1] - seen[0]) + ", 40 more as " + (seen[2] - seen[1]) + ", 10 without"
			+ " ctrl as " + (seen[3] - seen[2]) + ", and a drag of a plain widget with ctrl as "
			+ (free - 300));
	}

	/**
		A menu that fills itself as it opens shows what is true when it opens, not when it was built,
		and a dropdown whose list shrinks under its choice moves onto the last entry left.
	**/
	static function refilled():Void {
		final root = shaped();
		root.resize(400, 300);
		root.top.arrange(0, 0, 400, 300);

		var now = 1;
		final menu = new Menu();

		menu.onShow = function(held:Menu):Void {
			held.clears();
			for (index in 0...now) held.offer(new Choice("entry " + index));
		};

		root.pop(menu, 20, 20);
		final first = menu.choices.length;
		root.dismiss();

		now = 3;
		root.pop(menu, 20, 20);
		final second = menu.choices.length;
		root.dismiss();

		final list = new Dropdown("", 5, 6);
		var moved = 0;

		list.onChange = function(from:Dropdown):Void moved++;
		list.counts(4);

		says("a menu fills itself as it opens", first == 1 && second == 3 && list.value == 3
			&& list.count == 4 && moved == 1,
			"it held " + first + " then " + second + " entries as it was opened twice, and a list"
			+ " of six on its last entry cut to four stands on " + list.value + " after " + moved
			+ " change");
	}

	static function bars(renderer:cpp.Star<Canvas>, face:String, monoFace:String):Void {
		final body = Font.bake(renderer, face, 13);
		final mono = Font.bake(renderer, monoFace, 12);

		if (body == null || mono == null) {
			says("bar opens", false, "the fonts would not bake");
			return;
		}

		final metrics = new Metrics(1);
		metrics.dress(body, body, mono, mono, body);

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
