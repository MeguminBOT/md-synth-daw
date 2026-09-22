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

/**
	The preset browser: every instrument the piece carries, searchable by name or by
	tag, and orderable by bank, by name or by tag.
**/
final class Presets extends Widget {
	/**
		The session to read.
	**/
	public final session:Session;

	/**
		The rows.
	**/
	public final tree:Tree;

	/**
		What is typed into the search.
	**/
	public final search:mdd.ui.control.Field;

	/**
		Order: grouped by the bank they came from.
	**/
	public static inline final BY_BANK = 0;

	/**
		Order: by name.
	**/
	public static inline final BY_NAME = 1;

	/**
		Order: grouped by tag.
	**/
	public static inline final BY_TAG = 2;

	/**
		Order: only the presets the reader has starred, by name.
	**/
	public static inline final BY_FAVOURITE = 3;

	/**
		Order: how alike each preset is to the one the chosen part is playing, closest first,
		with how alike beside each row.
	**/
	public static inline final BY_LIKENESS = 4;

	/**
		How many orders there are.
	**/
	public static inline final ORDERS = 5;

	static final ORDER_NAMES:Array<Locale> = [Locale.PRESET_BY_BANK, Locale.PRESET_BY_NAME,
		Locale.PRESET_BY_TAG, Locale.PRESET_FAVOURITES, Locale.PRESET_BY_LIKENESS];

	/**
		Which order is chosen.
	**/
	public var order(default, null):Int = BY_BANK;

	/**
		How many instruments are shown.
	**/
	public var listed(default, null):Int = 0;

	/**
		How many groups they are in.
	**/
	public var banks(default, null):Int = 0;

	/**
		Called to rename a preset.
	**/
	public var onRename:Null<Int -> Void> = null;

	/**
		Called to edit its tags.
	**/
	public var onTags:Null<Int -> Void> = null;

	/**
		Called to lift the chosen patch into the library.
	**/
	public var onSave:Null<Void -> Void> = null;

	/**
		Called to open the presets folder in the file manager, where a subfolder made
		becomes a bank of its own.
	**/
	public var onFolder:Null<Void -> Void> = null;

	/**
		Called to write one preset out as a patch file, by index into the piece.
	**/
	public var onWritePatch:Null<Int -> Void> = null;

	/**
		Called to write what one preset plays out as a wave file, by index into the piece.
	**/
	public var onWriteSample:Null<Int -> Void> = null;

	/**
		Called to write a whole bank out as one file, by index into the piece's banks.
	**/
	public var onWriteBank:Null<Int -> Void> = null;

	/**
		The presets the reader has starred, or null where none are kept. A star is on the preset
		rather than on the row, so it follows the preset into every piece that carries it.
	**/
	public var favourites:Null<mdd.app.Favourites> = null;

	var menu:Null<Menu> = null;

	final named:Array<Int> = [];
	final held:Array<Item> = [];

	final kinds:Array<Item> = [];
	final kindKeys:Array<String> = [];

	final groups:Array<Item> = [];
	final groupKeys:Array<String> = [];
	final grouped:Array<Int> = [];
	final kitLead:Array<Int> = [];

	/**
		The families a reader has folded, which start open.
	**/
	final shut:Array<String> = [];

	/**
		The banks a reader has opened, which start folded.
	**/
	final opened:Array<String> = [];

	/**
		The toolbar button that steps through the orders.
	**/
	static inline final ORDER_CHIP = 0;

	/**
		The toolbar button that opens the presets folder.
	**/
	static inline final FOLDER_CHIP = 1;

	/**
		How many buttons the toolbar holds.
	**/
	static inline final CHIPS = 2;

	final chipLeft:haxe.ds.Vector<Float> = new haxe.ds.Vector<Float>(CHIPS);
	final chipWide:haxe.ds.Vector<Float> = new haxe.ds.Vector<Float>(CHIPS);

	/**
		Where the toolbar row starts, down.
	**/
	var barTop:Float = 0;

	/**
		How tall the toolbar row is.
	**/
	var barTall:Float = 0;

	var sighted:Int = -2;
	var sought:String = "";
	var pending:Bool = false;

	/**
		Builds the browser.

		@param session The session to read.
	**/
	public function new(session:Session) {
		super();
		this.session = session;

		opaque = true;

		tree = new Tree();
		add(tree);

		search = new mdd.ui.control.Field("");
		add(search);

		search.onChange = function(said:String):Void {
			fit();
			relayout();
		};

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

	function loads(which:Int, ?into:Part):Void {
		final instrument = session.song.instrumentAt(which);
		if (instrument == null) return;

		final part = into == null ? wanted(instrument) : into;

		session.does(new mdd.song.edit.TakesPreset(part, which));
		session.says(Locale.SAID_INSTRUMENT_LOADED,
			Kits.named(session.song, part, which), part.name());
	}

	/**
		Switches the chosen part to a preset from the playhead on, by putting it in the part's
		preset lane in the chosen pattern. A point already at that tick takes the new preset
		rather than a second point being laid over it, so one undo puts it back.

		@param which Which instrument.
	**/
	function switched(which:Int):Void {
		final instrument = session.song.instrumentAt(which);
		final pattern = session.current();
		if (instrument == null || pattern == null) return;

		final part = session.part;
		final begun = session.begins(session.transport.tick());
		final at = begun < 0 ? 0 : begun;

		var line:Null<mdd.song.Automation> = null;

		for (found in pattern.lane(part).automation) {
			if (found.held(mdd.song.Automation.INSTRUMENT, 0)) line = found;
		}

		if (line != null && line.marks(at)) {
			session.does(new mdd.song.edit.MovePoint(session.pattern, part,
				mdd.song.Automation.INSTRUMENT, 0, line.points[line.seek(at)], at, which));
		} else {
			session.does(new mdd.song.edit.AddPoint(session.pattern, part,
				mdd.song.Automation.INSTRUMENT, 0, new mdd.song.Point(at, which)));
		}

		session.says(Locale.SAID_PRESET_SWITCHED, Kits.named(session.song, part, which),
			part.name());
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

		final bank = groups.indexOf(item) >= 0;
		final list = bank ? opened : shut;
		final at = list.indexOf(key);

		if (item.open == bank) {
			if (at < 0) list.push(key);
		} else if (at >= 0) {
			list.splice(at, 1);
		}
	}

	/**
		Opens every family and every bank, or folds every bank and leaves the families open, and
		remembers it the way a reader's own folding is remembered.

		@param open Whether they should be open.
	**/
	public function opensAll(open:Bool):Void {
		if (open) {
			for (item in kinds) {
				tree.fold(item, true);
				folded(item);
			}
		}

		for (item in groups) {
			tree.fold(item, open);
			folded(item);
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

		menu.offer(new Choice(translate(Locale.PRESET_LOAD))).submenu = into(item, instrument);

		if (suits(instrument, session.part) && !session.part.sampled()) {
			fires(menu.offer(new Choice(filled(Locale.PRESET_SWITCH, [session.part.name()]))),
				function():Void switched(which));
		}

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

		final starring = favourites;

		if (starring != null && instrument.id != "") {
			fires(menu.offer(new Choice(translate(starring.favours(instrument.id)
				? Locale.PRESET_UNFAVOURITE : Locale.PRESET_FAVOURITE))), function():Void
				stars(which));
		}

		if (instrument.patch != null || instrument.sample >= 0) menu.divide();

		if (instrument.patch != null) {
			fires(menu.offer(new Choice(translate(Locale.PRESET_SAVE_PATCH))), function():Void
				if (onWritePatch != null) onWritePatch(which));
		}

		if (instrument.sample >= 0) {
			fires(menu.offer(new Choice(translate(Locale.PRESET_SAVE_SAMPLE))), function():Void
				if (onWriteSample != null) onWriteSample(which));
		}

		menu.divide();

		fires(menu.offer(new Choice(translate(Locale.PRESET_DELETE))), function():Void
			dropped(which));

		root.pop(menu, px, py, this);
	}

	/**
		@param item The preset's row.
		@param instrument The preset.
		@return A menu of every channel the preset plays on, each with what it plays now beside
			it. A converter preset in a kit loads the kit.
	**/
	function into(item:Item, instrument:Instrument):Menu {
		final out = new Menu();
		final at = held.indexOf(item);
		final owner = at < 0 ? -1 : groups.indexOf(item.parent);
		final which = owner >= 0 && kitLead[owner] >= 0 ? kitLead[owner] : named[at];
		final song = session.song;

		for (index in 0...Part.COUNT) {
			final part:Part = index;
			if (!mdd.song.Library.kin(instrument.kind, part)) continue;

			final playing = song.instrumentAt(song.rack[index]);

			fires(out.offer(new Choice(part.name(), playing == null ? ""
				: Kits.named(song, part, song.rack[index]))), function():Void loads(which, part));
		}

		return out;
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

	/**
		Stars one preset, or takes the star off it, and says which it did.

		@param which The preset, by index into the piece.
	**/
	function stars(which:Int):Void {
		final starring = favourites;
		final held = session.song.instrumentAt(which);

		if (starring == null || held == null || held.id == "") return;

		final on = starring.toggles(held.id);

		session.say(translate(on ? Locale.PRESET_FAVOURITE : Locale.PRESET_UNFAVOURITE)
			+ ": " + held.name);

		fit();
		invalidate();
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

		final which = grouped[at];

		fires(menu.offer(new Choice(translate(Locale.PRESET_SAVE_BANK))), function():Void
			if (onWriteBank != null) onWriteBank(which));

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
		fires(into.offer(new Choice(translate(Locale.PRESET_EXPAND_ALL))), function():Void
			opensAll(true));

		fires(into.offer(new Choice(translate(Locale.PRESET_COLLAPSE_ALL))), function():Void
			opensAll(false));
	}

	/**
		@param item A row.
		@return Which instrument it is, by index, or -1 for a group heading.
	**/
	public function instrumentOf(item:Item):Int {
		final at = held.indexOf(item);
		return at < 0 ? -1 : named[at];
	}

	static final KINDS:Array<Part> = [Part.Fm1, Part.Psg1, Part.Noise, Part.Dac];

	/**
		Changes the order and builds the rows again.

		@param which Which order.
	**/
	public function sorts(which:Int):Void {
		final want = which < 0 ? 0 : (which >= ORDERS ? ORDERS - 1 : which);
		if (want == order) return;

		order = want;
		fit();

		session.say(translate(ORDER_NAMES[order]));
		session.changed();

		relayout();
	}

	/**
		Steps to the next order.
	**/
	public function turns():Void {
		sorts((order + 1) % ORDERS);
	}

	/**
		@return How wide the order button is.
	**/
	public inline function orderWide():Float {
		return chipWide[ORDER_CHIP];
	}

	/**
		@return Where it sits, across.
	**/
	public inline function orderLeft():Float {
		return chipLeft[ORDER_CHIP];
	}

	/**
		@return Where the toolbar row the buttons sit in starts, down.
	**/
	public inline function toolbarTop():Float {
		return barTop;
	}

	/**
		@param px A point, across.
		@param py A point, down.
		@return Whether the point is on the order button.
	**/
	public inline function onOrder(px:Float, py:Float):Bool {
		return chipAt(px, py) == ORDER_CHIP;
	}

	/**
		@param px A point, across.
		@param py A point, down.
		@return Which toolbar button the point is on, or -1 for none.
	**/
	function chipAt(px:Float, py:Float):Int {
		if (py < barTop || py >= barTop + barTall) return -1;

		for (which in 0...CHIPS) {
			if (px >= chipLeft[which] && px < chipLeft[which] + chipWide[which]) return which;
		}

		return -1;
	}

	/**
		@param which A toolbar button.
		@return What it says.
	**/
	function chipLabel(which:Int):String {
		return which == ORDER_CHIP ? translate(ORDER_NAMES[order]) : translate(Locale.PRESET_FOLDER);
	}

	/**
		Lays the toolbar out along its row: the order at the start and the folder at the end, each
		as wide as its label, both squeezed evenly where the row is narrower than the two.

		@param left Where the row starts, across.
		@param room How wide it is.
	**/
	function lays(left:Float, room:Float):Void {
		final root = root();
		final metrics = root == null ? null : root.metrics;
		final font = metrics == null ? null : (metrics.small == null ? metrics.body : metrics.small);
		final pad = metrics == null ? 8 : metrics.gap;
		final gap = pad * 0.5;

		var total = gap;

		for (which in 0...CHIPS) {
			chipWide[which] = (font == null ? 60 : font.measure(chipLabel(which))) + pad * 2;
			total += chipWide[which];
		}

		if (total > room) {
			final scale = (room - gap) / (total - gap);
			for (which in 0...CHIPS) chipWide[which] = Math.max(0, chipWide[which] * scale);
		}

		chipLeft[ORDER_CHIP] = left;
		chipLeft[FOLDER_CHIP] = left + room - chipWide[FOLDER_CHIP];
	}

	override function took(event:mdd.ui.Input):Bool {
		if (event.kind != mdd.ui.Kind.PointerDown) return false;

		switch (chipAt(event.x, event.y)) {
			case FOLDER_CHIP:
				if (onFolder != null) onFolder();
				return true;

			case ORDER_CHIP:
				turns();
				return true;

			case _:
		}

		return false;
	}

	/**
		@param index A preset, by index into the piece.
		@return How alike it is to what the chosen part is playing, as a fraction of one, or
			nought where the part plays nothing.
	**/
	function likeness(index:Int):Float {
		final playing = session.song.instrumentAt(session.song.rack[session.part.index()]);
		final held = session.song.instrumentAt(index);

		return playing == null || held == null ? 0 : held.likeness(playing);
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

		if (order == BY_LIKENESS) {
			inside.sort(function(one:Int, two:Int):Int {
				final first = likeness(one);
				final second = likeness(two);

				if (first != second) return first > second ? -1 : 1;

				final held = called(one);
				final other = called(two);

				return held < other ? -1 : (held > other ? 1 : 0);
			});

			return;
		}

		if (order == BY_NAME || order == BY_FAVOURITE) {
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

	/**
		Builds the rows again from the piece and whatever is typed in the search.
	**/
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

		final hunting = seeking() != "" || order == BY_FAVOURITE;
		final starring = favourites;

		for (kind in KINDS) {
			final kitting = kind.sampled();
			final places:Array<Int> = [];
			var total = 0;

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
			}

			if (total == 0) continue;

			final family = kind.family();
			final head = new Item(family + "   " + total);
			head.open = hunting || shut.indexOf(family) < 0;

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
					kitting ? Theme.PARTS[kind.index()] : -1));

				final key = family + "/" + bank.name;

				group.icon = kitting ? Icon.DRUMKIT : -1;
				group.open = hunting || opened.indexOf(key) >= 0;

				groups.push(group);
				groupKeys.push(key);
				grouped.push(at);
				kitLead.push(kind.sampled() ? inside[0] : -1);

				for (index in inside) {
					final instrument = song.instruments[index];
					final child = group.add(new Item(instrument.name,
						Theme.PARTS[kind.index()]));

					child.icon = instrument.icon;
					child.mark = starring != null && starring.favours(instrument.id)
						? Icon.STAR : -1;
					child.note = order == BY_LIKENESS
						? Math.round(likeness(index) * 100) + " %"
						: briefly(instrument.tags);
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

		if (order == BY_FAVOURITE) {
			final starring = favourites;
			if (starring == null || !starring.favours(instrument.id)) return false;
		}

		if (part.fm()) return instrument.kind.fm();
		if (part.square()) return instrument.kind.square();
		if (part.noise()) return instrument.kind.noise();
		return instrument.kind.sampled();
	}

	function searchTall():Float {
		final root = root();
		return root == null ? 28 : root.metrics.whole(28);
	}

	/**
		@return How tall a preset row is, a little under the tree's own so more of a bank fits.
	**/
	function rowTall():Float {
		final root = root();
		return root == null ? 22 : root.metrics.whole(22);
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
		final gap = metrics == null ? 8 : metrics.gap;

		search.arrange(x + gap, y + top + gap * 0.5, width - gap * 2, deep);

		barTop = y + top + gap * 0.5 + deep + gap * 0.5;
		barTall = metrics == null ? 22 : metrics.whole(22);

		lays(x + gap, width - gap * 2);

		final under = barTop - y + barTall + gap * 0.5;

		tree.rowHeight = rowTall();
		tree.arrange(x, y + under, width, height - under);
		reveals();
	}

	/**
		@return What is typed into the search.
	**/
	public inline function seeking():String {
		return StringTools.trim(search.value);
	}

	/**
		Draws one of the buttons in the title strip.

		@param paint Where to draw.
		@param label What it says.
		@param left Where it sits, across.
		@param chip How wide it is.
	**/
	function chipped(paint:Paint, label:String, left:Float, chip:Float):Void {
		final root = root();
		if (root == null) return;

		final theme = root.theme;
		final metrics = root.metrics;
		final font = metrics.small == null ? metrics.body : metrics.small;
		if (font == null) return;

		final deep = metrics.whole(18);
		final at = barTop + (barTall - deep) * 0.5;

		if (chip < metrics.whole(8)) return;

		paint.roundedRect(left, at, chip, deep, metrics.radiusSmall, theme.raise2, 0.9);
		paint.outline(left, at, chip, deep, theme.frame, metrics.whole(1), 0.7,
			metrics.radiusSmall);

		paint.reface(font);
		paint.pushClip(left, at, chip, deep);
		paint.textCentred(label, left + chip * 0.5,
			at + (deep - font.height) * 0.5 + font.ascent, theme.ink, 0.85);
		paint.popClip();
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

		for (which in 0...CHIPS) chipped(paint, chipLabel(which), chipLeft[which], chipWide[which]);

		if (listed == 0) {
			paint.text(translate(Locale.PANEL_NO_PRESETS), x + metrics.inset,
				tree.y + metrics.gap + font.ascent, theme.dim, 0.6);
			return;
		}

		tree.paint(paint);
	}
}
