package mdd.view.editor;

import mdd.app.Locale;
import mdd.app.Session;
import mdd.song.Instrument;
import mdd.song.Part;
import mdd.ui.Glyph;
import mdd.ui.Item;
import mdd.ui.Paint;
import mdd.ui.Panel;
import mdd.ui.Theme;
import mdd.ui.control.Choice;
import mdd.ui.control.Menu;
import mdd.ui.control.Tree;
import mdd.ui.Widget;
import mdd.view.Kits;

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
	final held:Array<Item> = [];

	final kinds:Array<Item> = [];
	final kindKeys:Array<String> = [];

	final groups:Array<Item> = [];
	final groupKeys:Array<String> = [];
	final grouped:Array<Int> = [];
	final kitLead:Array<Int> = [];

	final shut:Array<String> = [];
	final opened:Array<String> = [];

	var sighted:Int = -2;
	var pending:Bool = false;

	public function new(session:Session) {
		super();
		this.session = session;

		opaque = true;

		tree = new Tree();
		add(tree);

		tree.onChoose = function(item:Item):Void picked(item);
		tree.onOpen = function(item:Item):Void folded(item);
		tree.onContext = function(item:Item, px:Float, py:Float):Void
			popped(item, px, py);
	}

	function picked(item:Item):Void {
		final at = held.indexOf(item);

		if (at >= 0) {
			final owner = groups.indexOf(item.parent);

			if (owner >= 0 && kitLead[owner] >= 0) loads(kitLead[owner]);
			else loads(named[at]);

			return;
		}

		final group = groups.indexOf(item);
		if (group >= 0 && kitLead[group] >= 0) loads(kitLead[group]);
	}

	function loads(which:Int):Void {
		final instrument = session.song.instrumentAt(which);
		if (instrument == null) return;

		final part = wanted(instrument);

		session.does(new mdd.song.edit.SetInstrument(part, which));
		session.say("loaded " + Kits.named(session.song, part, which) + " into " + part.name());
	}

	function wanted(instrument:Instrument):Part {
		if (suits(instrument, session.part)) return session.part;

		for (index in 0...Part.COUNT) {
			final part:Part = index;
			if (suits(instrument, part)) return part;
		}

		return session.part;
	}

	function keyOf(item:Item):String {
		var at = kinds.indexOf(item);
		if (at >= 0) return kindKeys[at];

		at = groups.indexOf(item);
		return at < 0 ? "" : groupKeys[at];
	}

	function folded(item:Item):Void {
		final key = keyOf(item);
		if (key == "") return;

		final group = groups.indexOf(item);
		final kit = group >= 0 && kitLead[group] >= 0;
		final list = kit ? opened : shut;
		final at = list.indexOf(key);

		if (item.open == kit) {
			if (at < 0) list.push(key);
		} else if (at >= 0) {
			list.splice(at, 1);
		}
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

		menu.offer(new Choice(translate(Locale.PRESET_ICON))).submenu = icons(which);

		fires(menu.offer(new Choice(translate(Locale.PRESET_DUPLICATE))), function():Void
			duplicated(which));

		menu.divide();

		fires(menu.offer(new Choice(translate(Locale.PRESET_DELETE))), function():Void
			dropped(which));

		root.pop(menu, px, py, this);
	}

	function icons(which:Int):Menu {
		final out = new Menu();

		fires(out.offer(new Choice(translate(Locale.PRESET_NO_ICON))), function():Void
			iconed(which, -1));

		out.divide();

		out.offer(new Choice(translate(Locale.PRESET_INSTRUMENTS))).submenu =
			drawn(which, Glyph.SHAPES, Glyph.COUNT);
		out.offer(new Choice(translate(Locale.PRESET_SHAPES))).submenu =
			drawn(which, 0, Glyph.SHAPES);

		return out;
	}

	function drawn(which:Int, from:Int, until:Int):Menu {
		final out = new Menu();

		for (index in from...until) {
			final want = index;
			fires(out.offer(new Choice(Glyph.NAMES[want])), function():Void iconed(which, want));
		}

		return out;
	}

	function iconed(which:Int, icon:Int):Void {
		final instrument = session.song.instrumentAt(which);
		if (instrument == null) return;

		instrument.icon = icon;
		session.changed();
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

		if (kinds.indexOf(item) >= 0) {
			menu = new Menu();
			folding(menu);
			root.pop(menu, px, py, this);
			return;
		}

		final at = groups.indexOf(item);

		if (at < 0) {
			preset(item, px, py);
			return;
		}

		final bank = session.song.banks[grouped[at]];
		if (bank == null) return;

		menu = new Menu();

		if (kitLead[at] >= 0) {
			fires(menu.offer(new Choice(translate(Locale.PRESET_KIT))), function():Void
				picked(item));
			menu.divide();
		}

		folding(menu);
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

	function folding(into:Menu):Void {
		fires(into.offer(new Choice(translate(Locale.BANK_EXPAND))), function():Void {
			shut.resize(0);
			for (item in kinds) tree.fold(item, true);
			for (item in groups) tree.fold(item, true);
		});

		fires(into.offer(new Choice(translate(Locale.BANK_COLLAPSE))), function():Void {
			for (item in groups) {
				tree.fold(item, false);
				folded(item);
			}
		});
	}

	public function instrumentOf(item:Item):Int {
		final at = held.indexOf(item);
		return at < 0 ? -1 : named[at];
	}

	static final KINDS:Array<Part> = [Part.Fm1, Part.Psg1, Part.Noise, Part.Dac];

	public function fit():Void {
		tree.clear();

		named.resize(0);
		held.resize(0);
		kinds.resize(0);
		kindKeys.resize(0);
		groups.resize(0);
		groupKeys.resize(0);
		grouped.resize(0);
		kitLead.resize(0);

		listed = 0;
		banks = 0;

		final song = session.song;
		final chosen = song.rack[session.part.index()];
		final root = root();
		final warned = root == null ? -1 : (root.theme.warn : Int);

		for (kind in KINDS) {
			final kitting = kind.sampled();
			final places:Array<Int> = [];
			var total = 0;
			var loose = false;

			for (at in 0...song.banks.length) {
				var has = 0;

				for (index in song.banks[at].instruments) {
					final instrument = song.instrumentAt(index);
					if (instrument == null || !suits(instrument, kind)) continue;

					has++;
				}

				if (has == 0) continue;

				total += kitting ? 1 : has;
				places.push(at);
				if (!song.banks[at].kept) loose = true;
			}

			if (total == 0) continue;

			final family = kind.family();
			final head = new Item(family + "   " + total, loose ? warned : -1);
			head.open = shut.indexOf(family) < 0;

			kinds.push(head);
			kindKeys.push(family);

			for (at in places) {
				final bank = song.banks[at];
				final inside:Array<Int> = [];

				for (index in bank.instruments) {
					final instrument = song.instrumentAt(index);
					if (instrument == null || !suits(instrument, kind)) continue;
					if (inside.indexOf(index) >= 0) continue;

					inside.push(index);
				}

				if (inside.length == 0) continue;

				final group = head.add(new Item(bank.name + "   " + inside.length,
					kitting ? Theme.PARTS[kind.index()] : (bank.kept ? -1 : warned)));

				final key = family + "/" + bank.name;

				group.icon = kitting ? Glyph.DRUM : -1;
				group.open = kitting ? opened.indexOf(key) >= 0 : shut.indexOf(key) < 0;

				groups.push(group);
				groupKeys.push(key);
				grouped.push(at);
				kitLead.push(kind.sampled() ? inside[0] : -1);

				for (index in inside) {
					final instrument = song.instruments[index];
					final child = group.add(new Item(instrument.name,
						Theme.PARTS[kind.index()]));

					child.icon = instrument.icon;

					named.push(index);
					held.push(child);
					if (!kitting) listed++;
				}

				if (kitting) listed++;
			}

			tree.plant(head);
			banks++;
		}

		final at = named.indexOf(chosen);

		if (at >= 0) {
			final row = held[at];
			final want = row.parent != null && !row.parent.open ? row.parent : row;

			tree.select(want);
			if (chosen != sighted) pending = true;
		}

		sighted = chosen;

		tree.reflow();
		reveals();
		invalidate();
	}

	function reveals():Void {
		if (!pending || tree.height <= 0) return;

		tree.reveal();
		pending = false;
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
		reveals();
	}

	override function paint(paint:Paint):Void {
		final root = root();
		if (root == null || root.metrics.body == null) return;

		final theme = root.theme;
		final metrics = root.metrics;
		final font = metrics.small == null ? metrics.body : metrics.small;
		final top = metrics.whole(24);

		paint.rect(x, y, width, height, theme.panel);

		Panel.titled(paint, theme, metrics, translate(Locale.PANEL_PATCHES),
			x, y, width, top);

		paint.reface(font);
		paint.textRight(listed + " / " + banks, x + width - metrics.inset,
			y + (top - font.height) * 0.5 + font.ascent, theme.dim, 0.8);

		if (listed == 0) {
			paint.text(translate(Locale.PANEL_NO_PATCHES), x + metrics.inset,
				y + top + metrics.gap + font.ascent, theme.dim, 0.6);
			return;
		}

		tree.paint(paint);
	}
}
