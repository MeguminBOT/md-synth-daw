package mdd.view.editor;

import mdd.app.Locale;
import mdd.app.Session;
import mdd.song.Instrument;
import mdd.song.Part;
import mdd.Icon;
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
	public final search:mdd.ui.control.Field;

	public static inline final BY_BANK = 0;
	public static inline final BY_NAME = 1;
	public static inline final BY_TAG = 2;
	public static inline final ORDERS = 3;

	static final ORDER_NAMES:Array<Locale> = [Locale.PRESET_BY_BANK, Locale.PRESET_BY_NAME,
		Locale.PRESET_BY_TAG];

	public var order(default, null):Int = BY_BANK;

	public var listed(default, null):Int = 0;
	public var banks(default, null):Int = 0;

	public var onRename:Null<Int -> Void> = null;
	public var onTags:Null<Int -> Void> = null;
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
	var sought:String = "";
	var pending:Bool = false;

	public function new(session:Session) {
		super();
		this.session = session;

		opaque = true;

		tree = new Tree();
		add(tree);

		search = new mdd.ui.control.Field("");
		add(search);

		search.onChange = function(said:String):Void relayout();

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

		menu.offer(new Choice(translate(Locale.ICON_PICK))).submenu = icons(which);

		final tagging = menu.offer(new Choice(translate(Locale.PRESET_TAGS),
			instrument.tags.length == 0 ? "" : "" + instrument.tags.length));

		fires(tagging, function():Void if (onTags != null) onTags(which));

		fires(menu.offer(new Choice(translate(Locale.PRESET_DUPLICATE))), function():Void
			duplicated(which));

		menu.divide();

		fires(menu.offer(new Choice(translate(Locale.PRESET_DELETE))), function():Void
			dropped(which));

		root.pop(menu, px, py, this);
	}

	function icons(which:Int):Menu {
		final out = new Menu();

		fires(out.offer(new Choice(translate(Locale.ICON_NONE))), function():Void
			iconed(which, -1));

		out.divide();

		final seen:Array<String> = [];

		for (group in Icon.GROUPS) if (seen.indexOf(group) < 0) seen.push(group);

		for (group in seen) {
			out.offer(new Choice(titled(group))).submenu = drawn(which, group);
		}

		return out;
	}

	function titled(group:String):String {
		return switch (group) {
			case "shape": translate(Locale.ICON_SHAPES);
			case "audio": translate(Locale.ICON_AUDIO);
			case "instrument": translate(Locale.ICON_INSTRUMENTS);
			case _: group;
		}
	}

	function drawn(which:Int, group:String):Menu {
		final out = new Menu();

		for (index in 0...Icon.COUNT) {
			if (Icon.GROUPS[index] != group) continue;

			final want = index;
			fires(out.offer(new Choice(Icon.NAMES[want])), function():Void iconed(which, want));
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

	static inline final SHOWN = 4;

	static function shortened(tag:String):Bool {
		if (tag.length < 2 || tag.length > 5) return false;

		for (index in 0...tag.length) {
			final code = StringTools.fastCodeAt(tag, index);

			final letter = code >= 65 && code <= 90;
			final digit = code >= 48 && code <= 57;

			if (!letter && !digit) return false;
		}

		return true;
	}

	public static function briefly(tags:Array<String>):String {
		final held:Array<String> = [];

		for (tag in tags) if (shortened(tag) && held.indexOf(tag) < 0) held.push(tag);

		if (held.length > SHOWN) {
			return held.slice(0, SHOWN).join(" ") + "  +" + (held.length - SHOWN);
		}

		if (held.length > 0) return held.join(" ");

		if (tags.length == 0) return "";
		if (tags.length <= 2) return tags.join(", ");

		return tags[0] + ", " + tags[1] + "  +" + (tags.length - 2);
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

		final keep = menu.offer(new Choice(translate(Locale.PRESET_KEEP)));

		if (bank.kept) {
			keep.enabled = false;
			keep.reason = translate(Locale.PRESET_ALREADY);
		} else {
			keep.onFire = function(from:Choice):Void {
				bank.kept = true;
				session.say(translate(Locale.PRESET_KEPT) + " " + bank.name);
				session.changed();
			};
		}

		root.pop(menu, px, py, this);
	}

	function folding(into:Menu):Void {
		fires(into.offer(new Choice(translate(Locale.PRESET_EXPAND_ALL))), function():Void {
			shut.resize(0);
			for (item in kinds) tree.fold(item, true);
			for (item in groups) tree.fold(item, true);
		});

		fires(into.offer(new Choice(translate(Locale.PRESET_COLLAPSE_ALL))), function():Void {
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

	public function sorts(which:Int):Void {
		final want = which < 0 ? 0 : (which >= ORDERS ? ORDERS - 1 : which);
		if (want == order) return;

		order = want;
		fit();

		session.say(translate(ORDER_NAMES[order]));
		session.changed();

		invalidate();
	}

	public function turns():Void {
		sorts((order + 1) % ORDERS);
	}

	public function orderWide():Float {
		final root = root();
		return root == null ? 62 : root.metrics.whole(62);
	}

	public function orderLeft():Float {
		final root = root();
		if (root == null) return x;

		final metrics = root.metrics;
		final font = metrics.small == null ? metrics.body : metrics.small;

		return x + width - metrics.inset - font.measure(listed + " / " + banks)
			- metrics.gap - orderWide();
	}

	public function onOrder(px:Float, py:Float):Bool {
		final root = root();
		if (root == null) return false;

		final left = orderLeft();

		return py >= y && py < y + root.metrics.head && px >= left
			&& px < left + orderWide();
	}

	override function took(event:mdd.ui.Input):Bool {
		if (event.kind != mdd.ui.Kind.PointerDown) return false;
		if (!onOrder(event.x, event.y)) return false;

		turns();
		return true;
	}

	function tagged(index:Int):String {
		final held = session.song.instrumentAt(index);
		if (held == null || held.tags.length == 0) return "~";

		return held.tags[0].toLowerCase();
	}

	function called(index:Int):String {
		final held = session.song.instrumentAt(index);
		return held == null ? "" : held.name.toLowerCase();
	}

	function ordered(inside:Array<Int>):Void {
		if (order == BY_BANK) return;

		if (order == BY_NAME) {
			inside.sort(function(one:Int, two:Int):Int {
				final first = called(one);
				final second = called(two);

				return first < second ? -1 : (first > second ? 1 : 0);
			});

			return;
		}

		inside.sort(function(one:Int, two:Int):Int {
			final first = tagged(one);
			final second = tagged(two);

			if (first != second) return first < second ? -1 : 1;

			final held = called(one);
			final other = called(two);

			return held < other ? -1 : (held > other ? 1 : 0);
		});
	}

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
				ordered(inside);

				final group = head.add(new Item(bank.name + "   " + inside.length,
					kitting ? Theme.PARTS[kind.index()] : (bank.kept ? -1 : warned)));

				final key = family + "/" + bank.name;

				group.icon = kitting ? Icon.DRUMKIT : -1;
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
					child.note = briefly(instrument.tags);
					child.says = instrument.tags.length == 0 ? ""
						: instrument.tags.join(", ");

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

	function suits(instrument:Instrument, part:Part):Bool {
		final want = seeking();
		if (want != "" && !instrument.tagged(want)) return false;

		if (part.fm()) return instrument.kind.fm();
		if (part.square()) return instrument.kind.square();
		if (part.noise()) return instrument.kind.noise();
		return instrument.kind.sampled();
	}

	function searchTall():Float {
		final root = root();
		return root == null ? 28 : root.metrics.whole(28);
	}

	override function layout():Void {
		if (seeking() != sought) {
			sought = seeking();
			fit();
		}

		final root = root();
		final top = root == null ? 26 : root.metrics.head;
		final deep = searchTall();

		final metrics = root == null ? null : root.metrics;
		final inset = metrics == null ? 12 : metrics.inset;
		final gap = metrics == null ? 8 : metrics.gap;

		search.arrange(x + gap, y + top + gap * 0.5, width - gap * 2, deep);

		final under = top + deep + gap;

		tree.arrange(x, y + under, width, height - under);
		reveals();
	}

	public inline function seeking():String {
		return StringTools.trim(search.value);
	}

	override function paint(paint:Paint):Void {
		final root = root();
		if (root == null || root.metrics.body == null) return;

		final theme = root.theme;
		final metrics = root.metrics;
		final font = metrics.small == null ? metrics.body : metrics.small;
		final top = metrics.head;

		paint.rect(x, y, width, height, theme.panel);

		Panel.titled(paint, theme, metrics, translate(Locale.PANEL_PRESETS),
			x, y, width, top);

		search.hint = translate(Locale.PRESET_SEARCH);
		search.paint(paint);

		paint.reface(font);
		paint.textRight(listed + " / " + banks, x + width - metrics.inset,
			y + (top - font.height) * 0.5 + font.ascent, theme.dim, 0.8);

		final chip = orderWide();
		final left = orderLeft();
		final deep = metrics.whole(17);
		final at = y + (top - deep) * 0.5;

		paint.roundedRect(left, at, chip, deep, metrics.radiusSmall, theme.raise2, 0.9);
		paint.outline(left, at, chip, deep, theme.frame, metrics.whole(1), 0.7,
			metrics.radiusSmall);

		paint.pushClip(left, at, chip, deep);
		paint.textCentred(translate(ORDER_NAMES[order]), left + chip * 0.5,
			at + (deep - font.height) * 0.5 + font.ascent, theme.ink, 0.85);
		paint.popClip();

		if (listed == 0) {
			paint.text(translate(Locale.PANEL_NO_PRESETS), x + metrics.inset,
				y + top + metrics.gap + font.ascent, theme.dim, 0.6);
			return;
		}

		tree.paint(paint);
	}
}
