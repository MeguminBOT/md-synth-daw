package mdd.view.monitor;

import haxe.ds.Vector;
import mdd.app.Locale;
import mdd.app.Session;
import mdd.play.Stream;
import mdd.ui.Input;
import mdd.ui.Kind;
import mdd.ui.Paint;
import mdd.ui.Panel;
import mdd.ui.Pointer;
import mdd.ui.control.Choice;
import mdd.ui.control.Menu;
import mdd.ui.Scroll;

@:unreflective

/**
	The register timeline: every write, which part took it, and what it meant.

	It reads the same stream playback and the export read, so what it shows is what
	the hardware would have been given and not a second account of it.
**/
final class Registers extends Scroll {
	static inline final KEPT = 512;
	static final PORTS:Array<String> = ["port 0", "port 1", "port 2", "port 3"];

	/**
		The session to read.
	**/
	public final session:Session;

	/**
		How many writes are held.
	**/
	public var writes(default, null):Int = 0;

	/**
		How many rows the last frame drew, which is what proves only the visible ones cost
		anything.
	**/
	public var painted(default, null):Int = 0;
	var following:Bool = true;

	var menu:Null<Menu> = null;

	final ticks:Vector<Int> = new Vector<Int>(KEPT);
	final kinds:Vector<Int> = new Vector<Int>(KEPT);
	final ports:Vector<Int> = new Vector<Int>(KEPT);
	final values:Vector<Int> = new Vector<Int>(KEPT);

	var at:Int = 0;

	final tickShown:Vector<Int> = new Vector<Int>(KEPT);
	final tickText:Array<String> = cpp.NativeArray.create(KEPT);
	final portText:Array<String> = cpp.NativeArray.create(4);
	final squareText:Array<String> = cpp.NativeArray.create(8);
	var dataText:String = "";
	var spokenIn:String = "";
	var spoken:Bool = false;
	var headWrites:Int = -1;
	var headFollowing:Bool = false;
	var headText:String = "";

	/**
		Builds the timeline.

		@param session The session to read.
	**/
	public function new(session:Session) {
		super();
		this.session = session;

		focusable = true;
		opaque = true;

		for (index in 0...KEPT) {
			ticks[index] = 0;
			kinds[index] = 0;
			ports[index] = 0;
			values[index] = -1;
		}
	}

	/**
		Throws every held write away.
	**/
	public function forget():Void {
		writes = 0;
		at = 0;

		for (index in 0...KEPT) values[index] = -1;

		invalidate();
	}

	/**
		Reads a span of the stream and keeps it, dropping the oldest where the timeline
		is full.

		@param stream The stream to read.
		@param from Where to start.
		@return How far it read to, to pass back next time.
	**/
	public function take(stream:Stream, from:Int):Int {
		final many = stream.count;
		if (from >= many) return many;

		for (index in from...many) {
			ticks[at] = stream.tickAt(index);
			kinds[at] = stream.kindAt(index);
			ports[at] = stream.portAt(index);
			values[at] = stream.valueAt(index);

			at = (at + 1) % KEPT;
			writes++;
		}

		invalidate();
		return many;
	}

	/**
		@return How tall one row is.
	**/
	public function rowTall():Float {
		final root = root();
		return root == null ? 22 : root.metrics.whole(22);
	}

	/**
		@return How many rows there are.
	**/
	public function rows():Int {
		return writes < KEPT ? writes : KEPT;
	}

	function indexOf(row:Int):Int {
		if (writes < KEPT) return row;

		return (at + row) % KEPT;
	}

	override function took(event:Input):Bool {
		if (super.took(event)) return true;

		switch (event.kind) {
			case Kind.PointerDown:
				if (event.button == Pointer.Right) {
					popped(rowUnder(event.y), event.x, event.y);
					return true;
				}

				following = !following;
				invalidate();
				return true;

			case Kind.PointerMove:
				tip = translate(following ? Locale.REGISTERS_HOLD : Locale.REGISTERS_FOLLOW);
				detail = translate(Locale.TIP_MORE);

			case _:
		}

		return false;
	}

	function rowUnder(py:Float):Int {
		final root = root();
		if (root == null) return -1;

		final head = root.metrics.whole(24);
		final at = Std.int((py - y - head + offsetY) / rowTall());

		return at < 0 || at >= rows() ? -1 : at;
	}

	/**
		@param row A row.
		@return The register and the value, as the documentation writes them.
	**/
	public function said(row:Int):String {
		final index = indexOf(row);
		if (values[index] < 0) return "";

		final ym = kinds[index] == Stream.YM;

		return hex(ticks[index], 8) + "  " + (ym ? "ym" : "psg")
			+ (ym ? "  port " + ports[index] : "") + "  " + hex(values[index], 2)
			+ "  " + named(kinds[index], ports[index], values[index]);
	}

	/**
		@param row A row.
		@return What that write actually did, in words.
	**/
	public function command(row:Int):String {
		final index = indexOf(row);
		if (values[index] < 0) return "";

		if (kinds[index] != Stream.YM) return "0x50 " + hex(values[index], 2);

		final port = ports[index] < 2 ? "0x52" : "0x53";
		return port + " " + hex(values[index], 2);
	}

	function popped(row:Int, px:Float, py:Float):Void {
		final root = root();
		if (root == null) return;

		menu = new Menu();

		final copy = menu.offer(new Choice(translate(Locale.REGISTERS_COPY)));
		final asVgm = menu.offer(new Choice(translate(Locale.REGISTERS_AS_VGM)));

		if (row < 0) {
			copy.enabled = false;
			asVgm.enabled = false;
			copy.reason = translate(Locale.REGISTERS_NO_ROW);
			asVgm.reason = copy.reason;
		} else {
			fires(copy, function():Void mdd.host.Sdl.setClipboard(said(row)));
			fires(asVgm, function():Void mdd.host.Sdl.setClipboard(command(row)));
		}

		menu.divide();

		fires(menu.offer(new Choice(translate(following
			? Locale.REGISTERS_HOLD : Locale.REGISTERS_FOLLOW))), function():Void {
			following = !following;
			invalidate();
		});

		fires(menu.offer(new Choice(translate(Locale.REGISTERS_FORGET))), function():Void
			forget());

		root.pop(menu, px, py, this);
	}

	function named(kind:Int, port:Int, value:Int):String {
		if (kind != Stream.YM) return square(value);
		return PORTS[port & 3];
	}

	function square(value:Int):String {
		speaks();

		if ((value & 0x80) == 0) return dataText;

		return squareText[((value >> 5) & 3) * 2 + ((value & 0x10) != 0 ? 1 : 0)];
	}

	/**
		Makes the words the rows write again where the language has changed since they were
		last made, so a frame of rows allocates nothing.
	**/
	function speaks():Void {
		final root = root();
		final language = root == null ? "" : root.translation.language;

		if (spoken && language == spokenIn) return;

		spoken = true;
		spokenIn = language;
		headText = "";
		dataText = translate(Locale.REGISTERS_DATA);

		for (which in 0...4) {
			final part = which == 3 ? "noise" : "psg" + (which + 1);

			squareText[which * 2] = part + " " + translate(Locale.REGISTERS_TONE);
			squareText[which * 2 + 1] = part + " " + translate(Locale.REGISTERS_LEVEL);
		}

		for (port in 0...4) portText[port] = filled(Locale.FIELD_PORT, [Std.string(port)]);
	}

	/**
		@param index A slot.
		@return The tick of the write held there, in hexadecimal, made again only when the slot
			holds a different tick.
	**/
	function tickOf(index:Int):String {
		if (tickText[index] == null || tickShown[index] != ticks[index]) {
			tickShown[index] = ticks[index];
			tickText[index] = hex(ticks[index], 8);
		}

		return tickText[index];
	}

	static function hex(value:Int, wide:Int):String {
		return StringTools.lpad(StringTools.hex(value, wide), "0", wide);
	}

	override function paint(paint:Paint):Void {
		final root = root();
		if (root == null || root.metrics.body == null) return;

		final theme = root.theme;
		final metrics = root.metrics;
		final font = metrics.mono == null ? metrics.body : metrics.mono;
		final small = metrics.small == null ? metrics.body : metrics.small;
		final tall = rowTall();
		final head = metrics.head;
		final many = rows();

		contentHeight = many * tall + head;

		paint.rect(x, y, width, height, theme.panel);
		Panel.titled(paint, theme, metrics, translate(Locale.VIEW_REGISTERS), x, y, width, head);
		paint.reface(small);

		speaks();

		if (writes != headWrites || following != headFollowing || headText == "") {
			headWrites = writes;
			headFollowing = following;
			headText = writes + "   "
				+ translate(following ? Locale.REGISTERS_FOLLOWING : Locale.REGISTERS_HELD);
		}

		paint.textRight(headText, x + width - metrics.inset,
			y + (head - small.height) * 0.5 + small.ascent, theme.dim, 0.8);

		if (many == 0) {
			paint.text(translate(Locale.REGISTERS_NOTHING), x + metrics.inset,
				y + head + metrics.gap + small.ascent, theme.dim, 0.7);

			painted = 0;
			return;
		}

		if (following) scrolled = contentHeight - height;

		paint.pushClip(x, y + head, width, height - head);
		paint.reface(font);

		var first = Std.int(offsetY / tall);
		if (first < 0) first = 0;

		var last = Std.int((offsetY + height - head) / tall) + 1;
		if (last > many) last = many;

		painted = last - first;

		final tickAt = x + metrics.inset;
		final chipAt = tickAt + font.measure("00000000") + metrics.inset;
		final portAt = chipAt + font.measure("psg") + metrics.inset;
		final valueAt = portAt + font.measure("port 0") + metrics.inset;
		final sayAt = valueAt + font.measure("00") + metrics.inset;

		for (row in first...last) {
			final index = indexOf(row);
			if (values[index] < 0) continue;

			final top = y + head + row * tall - offsetY;
			final line = top + (tall - font.height) * 0.5 + font.ascent;

			if (row % 2 == 1) paint.rect(x, top, width, tall, theme.sink, 0.35);

			final ym = kinds[index] == Stream.YM;

			paint.text(tickOf(index), tickAt, line, theme.dim, 0.85);
			paint.text(ym ? "ym" : "psg", chipAt, line, ym ? theme.part(1) : theme.part(6), 1);

			if (ym) paint.text(portText[ports[index] & 3], portAt, line, theme.dim, 0.85);

			paint.text(root.numerals.hex(values[index]), valueAt, line, theme.ink, 1);

			paint.reface(small);
			paint.text(named(kinds[index], ports[index], values[index]), sayAt, line,
				theme.ink, 0.7);
			paint.reface(font);
		}

		paint.popClip();
	}
}
