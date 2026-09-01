package mdd.view;

import mdd.song.Instrument;
import mdd.song.Part;
import mdd.ui.Input;
import mdd.ui.Item;
import mdd.ui.Paint;
import mdd.ui.Theme;
import mdd.ui.control.Choice;
import mdd.ui.control.Menu;
import mdd.ui.control.Tree;
import mdd.ui.Widget;

@:unreflective
final class Presets extends Widget {
	public final session:Session;
	public final tree:Tree;

	public var listed(default, null):Int = 0;
	public var banks(default, null):Int = 0;

	public var onRename:Null<Int -> Void> = null;
	public var onSave:Null<Void -> Void> = null;

	var menu:Null<Menu> = null;

	final named:Array<Int> = [];
	final heads:Array<Item> = [];
	final banked:Array<Int> = [];
	final held:Array<Item> = [];

	public function new(session:Session) {
		super();
		this.session = session;

		opaque = true;

		tree = new Tree();
		add(tree);

		tree.onChoose = function(item:Item):Void picked(item);
		tree.onContext = function(item:Item, px:Float, py:Float):Void
			popped(item, px, py);
	}

	function picked(item:Item):Void {
		final at = held.indexOf(item);
		if (at < 0) return;

		final part = session.part.index();
		if (session.song.rack[part] == named[at]) return;

		session.song.rack[part] = named[at];
		session.say("loaded " + session.song.instruments[named[at]].name + " into "
			+ session.part.name());
		session.changed();
	}

	function preset(item:Item, px:Float, py:Float):Void {
		final root = root();
		final at = held.indexOf(item);
		if (root == null || at < 0) return;

		final which = named[at];
		final instrument = session.song.instrumentAt(which);
		if (instrument == null) return;

		menu = new Menu();

		fires(menu.offer(new Choice(translate(Locale.PRESET_LOAD) + " "
			+ session.part.name())), function():Void picked(item));

		menu.divide();

		fires(menu.offer(new Choice(translate(Locale.PRESET_RENAME))), function():Void {
			if (onRename != null) onRename(which);
		});

		fires(menu.offer(new Choice(translate(Locale.PRESET_DUPLICATE))), function():Void
			duplicated(which));

		menu.divide();

		fires(menu.offer(new Choice(translate(Locale.PRESET_DELETE))), function():Void
			dropped(which));

		root.pop(menu, px, py, this);
	}

	function duplicated(which:Int):Void {
		final from = session.song.instrumentAt(which);
		if (from == null) return;

		final made = from.copy();
		made.name = from.name + " 2";

		session.holds();
		session.song.instrument(made);

		final index = session.song.instruments.length - 1;
		for (bank in session.song.banks) if (bank.holds(which)) bank.add(index);

		session.frees();
		session.changed();
	}

	function dropped(which:Int):Void {
		session.holds();
		for (bank in session.song.banks) bank.remove(which);
		session.frees();

		session.changed();
	}

	function fires(choice:Choice, what:Void -> Void):Void {
		choice.onFire = function(from:Choice):Void what();
	}

	function popped(item:Item, px:Float, py:Float):Void {
		final root = root();
		if (root == null) return;

		final at = heads.indexOf(item);

		if (at < 0) {
			preset(item, px, py);
			return;
		}

		final which = banked[at];
		final bank = session.song.banks[which];
		if (bank == null) return;

		menu = new Menu();

		fires(menu.offer(new Choice(translate(Locale.BANK_EXPAND))), function():Void {
			for (held in heads) tree.fold(held, true);
		});

		fires(menu.offer(new Choice(translate(Locale.BANK_COLLAPSE))), function():Void {
			for (held in heads) tree.fold(held, false);
		});

		menu.divide();

		final keep = menu.offer(new Choice(translate(Locale.BANK_KEEP)));

		if (bank.kept) {
			keep.enabled = false;
			keep.reason = translate(Locale.BANK_ALREADY);
		} else {
			keep.onFire = function(from:Choice):Void {
				bank.kept = true;
				session.say(translate(Locale.BANK_KEPT) + " " + bank.name);
				session.changed();
			};
		}

		root.pop(menu, px, py, this);
	}

	public function instrumentOf(item:Item):Int {
		final at = held.indexOf(item);
		return at < 0 ? -1 : named[at];
	}

	public function fit():Void {
		tree.clear();

		named.resize(0);
		heads.resize(0);
		banked.resize(0);
		held.resize(0);

		listed = 0;
		banks = 0;

		final song = session.song;
		final part = session.part;
		final chosen = song.rack[part.index()];
		final from = translate(Locale.PANEL_FROM_IMPORT);
		final root = root();
		final warned = root == null ? -1 : (root.theme.warn : Int);

		for (at in 0...song.banks.length) {
			final bank = song.banks[at];
			final holds:Array<Int> = [];

			for (index in bank.instruments) {
				final instrument = song.instrumentAt(index);
				if (instrument == null || !suits(instrument, part)) continue;

				holds.push(index);
			}

			if (holds.length == 0) continue;

			final badge = bank.kept || bank.name.indexOf(from) >= 0 ? "" : "   " + from;
			final head = new Item(bank.name + badge, bank.kept ? -1 : warned);

			heads.push(head);
			banked.push(at);

			for (index in holds) {
				final child = head.add(new Item(song.instruments[index].name,
					Theme.PARTS[part.index()]));

				named.push(index);
				held.push(child);
				listed++;
			}

			tree.plant(head);
			banks++;
		}

		final at = named.indexOf(chosen);
		if (at >= 0) tree.select(held[at]);

		tree.reflow();
		invalidate();
	}

	static function suits(instrument:Instrument, part:Part):Bool {
		if (part.fm()) return instrument.kind.fm();
		if (part.square()) return instrument.kind.square();
		if (part.noise()) return instrument.kind.noise() || instrument.kind.square();
		return instrument.kind.sampled();
	}

	override function layout():Void {
		final root = root();
		final top = root == null ? 24 : root.metrics.whole(24);

		tree.arrange(x, y + top, width, height - top);
	}

	override function paint(paint:Paint):Void {
		final root = root();
		if (root == null || root.metrics.body == null) return;

		final theme = root.theme;
		final metrics = root.metrics;
		final font = metrics.small == null ? metrics.body : metrics.small;
		final top = metrics.whole(24);

		paint.rect(x, y, width, height, theme.panel);
		paint.reface(font);

		paint.text(session.part.name() + " " + translate(Locale.PANEL_PATCHES),
			x + metrics.inset,
			y + top * 0.5 + font.ascent * 0.5, theme.dim, 0.8);

		paint.textRight(listed + " / " + banks,
			x + width - metrics.inset, y + top * 0.5 + font.ascent * 0.5, theme.dim, 0.7);

		if (listed == 0) {
			paint.text(translate(Locale.PANEL_NO_PATCHES), x + metrics.inset,
				y + top + metrics.gap + font.ascent, theme.dim, 0.6);
			return;
		}

		tree.paint(paint);
	}
}
