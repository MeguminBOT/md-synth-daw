package mdd.view.editor;

import mdd.app.Locale;
import mdd.app.Session;
import mdd.song.Instrument;
import mdd.song.Part;
import mdd.song.Sample;
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
	The preset browser: every preset installed and the ones the open piece carries because it plays
	them, under the four families of part, which stay the top of the tree whatever else is chosen.

	Inside a family the presets are grouped by bank, by tag, by when they were added, by where they
	come from, or not at all, and sorted by name, by date, by how alike each is to what the chosen
	part plays, or as their bank lists them. The starting bank is always the first group. What is
	shown can be narrowed by the filter menu and by words typed into the search, which filter the
	same way: `tag:` and `bank:` look at one thing only, a leading `-` leaves out what matches,
	`fav` keeps the starred and `used` keeps what the piece plays.

	Nothing it offers is in the piece until it is loaded: loading one copies it into the piece,
	so the piece carries what it plays rather than everything it was offered.
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
		Grouping: by the bank each is in.
	**/
	public static inline final GROUP_BANK = 0;

	/**
		Grouping: by tag, a preset listed under every tag it carries.
	**/
	public static inline final GROUP_TAG = 1;

	/**
		Grouping: by when each was added, newest first.
	**/
	public static inline final GROUP_ADDED = 2;

	/**
		Grouping: by where each comes from.
	**/
	public static inline final GROUP_SOURCE = 3;

	/**
		Grouping: none, every preset of a family in one list.
	**/
	public static inline final GROUP_NONE = 4;

	/**
		How many groupings there are.
	**/
	public static inline final GROUPINGS = 5;

	static final GROUP_NAMES:Array<Locale> = [Locale.PRESET_BY_BANK, Locale.PRESET_BY_TAG,
		Locale.PRESET_BY_ADDED, Locale.PRESET_BY_SOURCE, Locale.PRESET_BY_NONE];

	/**
		Sorting: by name, the way a person reads one, so 2 comes before 10.
	**/
	public static inline final SORT_NAME = 0;

	/**
		Sorting: newest first.
	**/
	public static inline final SORT_ADDED = 1;

	/**
		Sorting: how alike each is to what the chosen part is playing, closest first, with how
		alike beside each row.
	**/
	public static inline final SORT_LIKENESS = 2;

	/**
		Sorting: as each bank lists them.
	**/
	public static inline final SORT_LISTED = 3;

	/**
		How many sortings there are.
	**/
	public static inline final SORTS = 4;

	static final SORT_NAMES:Array<Locale> = [Locale.PRESET_BY_NAME, Locale.PRESET_BY_ADDED,
		Locale.PRESET_BY_LIKENESS, Locale.PRESET_BY_LISTED];

	/**
		What each source is called in the filter menu and as a group, by `Offer.DEFAULT` to
		`Offer.PROJECT`.
	**/
	static final SOURCE_NAMES:Array<Locale> = [Locale.PRESET_SOURCE_DEFAULT,
		Locale.PRESET_SOURCE_SHIPPED, Locale.PRESET_SOURCE_MINE, Locale.PRESET_FROM_PROJECT];

	/**
		The order sources are listed in as groups.
	**/
	static final SOURCE_ORDER:Array<Int> = [Offer.DEFAULT, Offer.PROJECT, Offer.SHIPPED, Offer.MINE];

	/**
		The spans a date added falls into, newest first, by the seconds each reaches back.
	**/
	static final AGES:Array<Float> = [86400, 7 * 86400, 31 * 86400, 366 * 86400];

	static final AGE_NAMES:Array<Locale> = [Locale.PRESET_ADDED_TODAY, Locale.PRESET_ADDED_WEEK,
		Locale.PRESET_ADDED_MONTH, Locale.PRESET_ADDED_YEAR, Locale.PRESET_ADDED_EARLIER];

	/**
		How many tags the filter menu offers, the most used first.
	**/
	static inline final TAGS_OFFERED = 30;

	/**
		Which grouping is chosen.
	**/
	public var grouping(default, null):Int = GROUP_BANK;

	/**
		Which sorting is chosen.
	**/
	public var sorting(default, null):Int = SORT_NAME;

	/**
		Whether the sorting runs the other way.
	**/
	public var reversed(default, null):Bool = false;

	/**
		Whether only the starred are shown.
	**/
	public var starredOnly(default, null):Bool = false;

	/**
		Whether only what the open piece plays, or was loaded from, is shown.
	**/
	public var usedOnly(default, null):Bool = false;

	/**
		Whether a sound in several banks is shown once, where it is first listed.
	**/
	public var single(default, null):Bool = false;

	/**
		Which sources are hidden, by `Offer.DEFAULT` to `Offer.PROJECT`.
	**/
	final hiddenSources:haxe.ds.Vector<Bool> = new haxe.ds.Vector<Bool>(4);

	/**
		The tags a preset must carry every one of to be shown.
	**/
	final wantedTags:Array<String> = [];

	/**
		The banks hidden by name.
	**/
	final hiddenBanks:Array<String> = [];

	/**
		How many presets are shown, a kit counting once.
	**/
	public var listed(default, null):Int = 0;

	/**
		How many families they are in.
	**/
	public var banks(default, null):Int = 0;

	/**
		Called to rename a preset the piece carries, by index into the piece.
	**/
	public var onRename:Null<Int -> Void> = null;

	/**
		Called to edit the tags of a preset the piece carries, by index into the piece.
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
		Called to write one preset out as a patch file.
	**/
	public var onWritePatch:Null<(Instrument, Null<Sample>) -> Void> = null;

	/**
		Called to write what one preset plays out as a wave file.
	**/
	public var onWriteSample:Null<(Instrument, Null<Sample>) -> Void> = null;

	/**
		Called to write a whole bank out as one file: its name, its presets and what each plays.
	**/
	public var onWriteBank:Null<(String, Array<Instrument>, Array<Null<Sample>>) -> Void> = null;

	/**
		Called whenever the grouping, the sorting or a filter changes, so it can be kept.
	**/
	public var onView:Null<Void -> Void> = null;

	/**
		Called once files in the presets folder have changed, so the library is read again.
	**/
	public var onShelved:Null<Void -> Void> = null;

	/**
		Called to ask for a line of text: what is asked, what the field starts with, and what to do
		with the answer.
	**/
	public var onAsk:Null<(Locale, String, String -> Void) -> Void> = null;

	/**
		Called to ask whether to go ahead: the question, what the answer that goes ahead says, and
		what going ahead does.
	**/
	public var onConfirm:Null<(String, String, Void -> Void) -> Void> = null;

	/**
		The presets folder, which a preset or a category in it is changed through, or null where
		nothing in it may be changed from here.
	**/
	public var folder:Null<mdd.app.PresetFolder> = null;

	/**
		Every file in the presets folder that was written from a bank shipped with the application,
		which is listed as shipped rather than as the reader's own.
	**/
	public var planted:Array<String> = [];

	/**
		The presets the reader has starred, or null where none are kept. A star is on the preset
		rather than on the row, so it follows the preset into every piece that carries it.
	**/
	public var favourites:Null<mdd.app.Favourites> = null;

	/**
		When each installed preset was added, or null where no dates are kept.
	**/
	public var added:Null<mdd.app.Added> = null;

	var menu:Null<Menu> = null;

	/**
		Every preset on offer this build, drawn from the pool.
	**/
	final offers:Array<Offer> = [];

	/**
		The offers built so far, reused from one build to the next.
	**/
	final pool:Array<Offer> = [];

	/**
		The preset rows, and the offer each stands for, by the same index.
	**/
	final held:Array<Item> = [];
	final shown:Array<Offer> = [];

	final kinds:Array<Item> = [];
	final kindKeys:Array<String> = [];

	/**
		The group rows, what each is keyed by for folding, and whether each is a kit.
	**/
	final groups:Array<Item> = [];
	final groupKeys:Array<String> = [];
	final kits:Array<Bool> = [];

	/**
		What each group row is called without its count, and the family it is listed under.
	**/
	final groupTitles:Array<String> = [];
	final groupFamilies:Array<String> = [];

	/**
		The first offer under each group row, which is what choosing a kit's row loads, or null for
		a category with nothing in it.
	**/
	final leads:Array<Null<Offer>> = [];

	/**
		What one family lists, the groups it lists them in, and what one group lists, kept between
		builds.
	**/
	final within:Array<Offer> = [];
	final groupNames:Array<String> = [];
	final inside:Array<Offer> = [];

	/**
		The identities the piece plays or was loaded from, and the ones already listed, rebuilt
		each time.
	**/
	final used:haxe.ds.StringMap<Bool> = new haxe.ds.StringMap<Bool>();
	final seen:haxe.ds.StringMap<Bool> = new haxe.ds.StringMap<Bool>();

	/**
		What the search holds, taken apart: words a name or a tag must hold, words neither may,
		words a tag must or may not hold, and words the bank's name must or may not hold.
	**/
	final words:Array<String> = [];
	final notWords:Array<String> = [];
	final tagWords:Array<String> = [];
	final notTagWords:Array<String> = [];
	final bankWords:Array<String> = [];
	final notBankWords:Array<String> = [];

	/**
		Whether the search asks for the starred, or for what the piece plays.
	**/
	var wantsStarred:Bool = false;
	var wantsUsed:Bool = false;

	/**
		What time it was when the rows were last built, in seconds since 1970, which every date
		added is measured against.
	**/
	var clock:Float = 0;

	/**
		The families a reader has folded, which start open.
	**/
	final shut:Array<String> = [];

	/**
		The groups a reader has opened, which start folded.
	**/
	final opened:Array<String> = [];

	/**
		The toolbar button that picks the grouping.
	**/
	static inline final GROUP_CHIP = 0;

	/**
		The toolbar button that picks the sorting.
	**/
	static inline final SORT_CHIP = 1;

	/**
		The toolbar button that opens the filters.
	**/
	static inline final FILTER_CHIP = 2;

	/**
		The toolbar button that opens the presets folder.
	**/
	static inline final FOLDER_CHIP = 3;

	/**
		How many buttons the toolbar holds.
	**/
	static inline final CHIPS = 4;

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

	/**
		Whether the toolbar is too narrow for its buttons to say what they are for as well as what
		they are set to, so they say only the second.
	**/
	var terse:Bool = false;

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

		for (at in 0...hiddenSources.length) hiddenSources[at] = false;

		tree = new Tree();
		add(tree);

		search = new mdd.ui.control.Field("");
		search.tipKey = Locale.PRESET_SEARCH_TIP;
		search.detailKey = Locale.PRESET_SEARCH_DETAIL;
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
			loads(shown[at]);
			return;
		}

		final group = groups.indexOf(item);
		if (group < 0 || !kits[group]) return;

		final lead = leads[group];
		if (lead != null) loads(lead);
	}

	/**
		Loads a preset into a part: one the piece carries by pointing at it, one the library holds
		by copying it in, and a converter preset out of the library by copying in the whole kit it
		sits in, since a drum note picks its hit out of one bank.

		@param offer The preset.
		@param into The part, or null for the chosen one where it can play the preset and the first
			that can otherwise.
	**/
	function loads(offer:Offer, ?into:Part):Void {
		final instrument = offer.preset;
		final part = into == null ? wanted(instrument) : into;
		final song = session.song;

		if (offer.owned()) {
			session.does(new mdd.song.edit.TakesPreset(part, offer.index));
		} else if (part.sampled()) {
			session.does(kitOf(offer, part));
		} else {
			session.does(mdd.song.edit.TakesPreset.adopting(part, instrument, offer.sample));
		}

		session.says(Locale.SAID_INSTRUMENT_LOADED,
			part.sampled() && !offer.owned() ? offer.bank : Kits.named(song, part, song.rack[part.index()]),
			part.name());
	}

	/**
		@param offer A converter preset out of the library.
		@param part The part it loads into.
		@return The step that copies in the kit it sits in, with that hit as the one the part points
			at.
	**/
	function kitOf(offer:Offer, part:Part):mdd.song.edit.TakesPreset {
		final hits:Array<Instrument> = [];
		final played:Array<Null<Sample>> = [];
		var lead = 0;

		final library = session.library;

		if (library != null && offer.shelf >= 0 && offer.shelf < library.names.length) {
			final shelf = library.instruments[offer.shelf];

			for (which in 0...shelf.length) {
				if (!shelf[which].kind.sampled()) continue;
				if (shelf[which] == offer.preset) lead = hits.length;

				hits.push(shelf[which]);
				played.push(library.samples[offer.shelf][which]);
			}
		}

		if (hits.length == 0) {
			hits.push(offer.preset);
			played.push(offer.sample);
		}

		return mdd.song.edit.TakesPreset.kitting(part, offer.bank, hits, played, lead);
	}

	/**
		Switches the chosen part to a preset from the playhead on, by putting it in the part's
		preset lane in the chosen pattern. A point already at that tick takes the new preset
		rather than a second point being laid over it, so one undo puts it back. A preset out of
		the library is copied into the piece first, since a lane names a preset the piece carries.

		@param offer The preset.
	**/
	function switched(offer:Offer):Void {
		final pattern = session.current();
		if (pattern == null) return;

		final song = session.song;
		var which = offer.index;

		if (!offer.owned()) {
			session.holds();
			which = song.adopts(offer.preset, offer.sample);
			session.frees();
		}

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

		session.says(Locale.SAID_PRESET_SWITCHED, Kits.named(song, part, which), part.name());
	}

	function wanted(instrument:Instrument):Part {
		if (mdd.song.Library.kin(instrument.kind, session.part)) return session.part;

		for (index in 0...Part.COUNT) {
			final part:Part = index;
			if (mdd.song.Library.kin(instrument.kind, part)) return part;
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

		final group = groups.indexOf(item) >= 0;
		final list = group ? opened : shut;
		final at = list.indexOf(key);

		if (item.open == group) {
			if (at < 0) list.push(key);
		} else if (at >= 0) {
			list.splice(at, 1);
		}
	}

	/**
		Opens every family and every group, or folds every group and leaves the families open, and
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

		final offer = shown[at];
		final instrument = offer.preset;
		final which = offer.index;
		final keeper = folder;

		menu = new Menu();

		menu.offer(new Choice(translate(Locale.PRESET_LOAD))).submenu = into(offer);

		if (mdd.song.Library.kin(instrument.kind, session.part) && !session.part.sampled()) {
			fires(menu.offer(new Choice(filled(Locale.PRESET_SWITCH, [session.part.name()]))),
				function():Void switched(offer));
		}

		menu.divide();

		if (offer.owned()) {
			fires(menu.offer(new Choice(translate(Locale.PRESET_RENAME))), function():Void {
				if (onRename != null) onRename(which);
			});
		} else if (offer.filed() && keeper != null) {
			fires(menu.offer(new Choice(translate(Locale.PRESET_RENAME))), function():Void
				asks(Locale.PRESET_NAME, instrument.name, function(said:String):Void
					shelved(keeper.renames(session.library, offer.shelf, offer.place, said), said)));
		}

		if (offer.owned() || (offer.filed() && keeper != null)) {
			menu.offer(new Choice(translate(Locale.ICON_PICK))).submenu = icons(offer);

			final tagging = menu.offer(new Choice(translate(Locale.PRESET_TAGS),
				instrument.tags.length == 0 ? "" : "" + instrument.tags.length));

			if (offer.owned()) {
				fires(tagging, function():Void if (onTags != null) onTags(which));
			} else {
				fires(tagging, function():Void
					asks(Locale.PRESET_TAGS, instrument.tags.join(", "), function(said:String):Void
						shelved(keeper.retags(session.library, offer.shelf, offer.place,
							said.split(",")), instrument.name)));
			}
		}

		final starring = favourites;

		if (starring != null && instrument.id != "") {
			fires(menu.offer(new Choice(translate(starring.favours(instrument.id)
				? Locale.PRESET_UNFAVOURITE : Locale.PRESET_FAVOURITE))), function():Void
				stars(instrument));
		}

		if (keeper != null) {
			menu.divide();

			if (offer.filed()) {
				menu.offer(new Choice(translate(Locale.PRESET_MOVE_TO))).submenu = placing(offer, true);
			}

			menu.offer(new Choice(translate(Locale.PRESET_COPY_TO))).submenu = placing(offer, false);
		}

		final sample = offer.sample;

		if (instrument.patch != null || sample != null) menu.divide();

		if (instrument.patch != null) {
			fires(menu.offer(new Choice(translate(Locale.PRESET_SAVE_PATCH))), function():Void
				if (onWritePatch != null) onWritePatch(instrument, sample));
		}

		if (sample != null) {
			fires(menu.offer(new Choice(translate(Locale.PRESET_SAVE_SAMPLE))), function():Void
				if (onWriteSample != null) onWriteSample(instrument, sample));
		}

		if (offer.filed() && keeper != null) {
			menu.divide();

			fires(menu.offer(new Choice(translate(Locale.PRESET_DELETE))), function():Void
				confirms(filled(Locale.PRESET_DELETE_ASKED, [instrument.name]),
					translate(Locale.PRESET_DELETE), function():Void
					shelved(keeper.deletes(session.library, offer.shelf, offer.place), instrument.name)));
		}

		root.pop(menu, px, py, this);
	}

	/**
		@param offer A preset.
		@return A menu of every channel the preset plays on, each with what it plays now beside
			it. A converter preset loads the kit it sits in.
	**/
	function into(offer:Offer):Menu {
		final out = new Menu();
		final song = session.song;

		for (index in 0...Part.COUNT) {
			final part:Part = index;
			if (!mdd.song.Library.kin(offer.preset.kind, part)) continue;

			final playing = song.instrumentAt(song.rack[index]);

			fires(out.offer(new Choice(part.name(), playing == null ? ""
				: Kits.named(song, part, song.rack[index]))), function():Void loads(offer, part));
		}

		return out;
	}

	/**
		@param offer A preset.
		@param moving Whether it is moved rather than copied.
		@return A menu of every category of the preset's family in the presets folder, the one it
			is in left out of a move, and a new one.
	**/
	function placing(offer:Offer, moving:Bool):Menu {
		final out = new Menu();
		final library = session.library;
		final family = offer.preset.kind.family();

		if (library != null) {
			for (at in 0...library.folders.length) {
				if (library.folderFamilies[at] != family) continue;
				if (moving && library.folderBanks[at] == offer.bank) continue;

				final where = library.folders[at];
				fires(out.offer(new Choice(library.folderBanks[at])), function():Void
					places(offer, where, moving));
			}
		}

		if (out.choices.length > 0) out.divide();

		fires(out.offer(new Choice(translate(Locale.PRESET_NEW_CATEGORY))), function():Void
			founds(family, function(where:String):Void places(offer, where, moving)));

		return out;
	}

	/**
		Copies or moves a preset into a folder.

		@param offer The preset.
		@param where The folder.
		@param moving Whether it is moved rather than copied.
	**/
	function places(offer:Offer, where:String, moving:Bool):Void {
		final keeper = folder;
		if (keeper == null) return;

		final done = moving && offer.filed()
			? keeper.moves(session.library, offer.shelf, offer.place, where)
			: keeper.copies(offer.preset, offer.sample, where) != "";

		shelved(done, offer.preset.name);
	}

	/**
		Asks for a category's name and makes it under a family's folder.

		@param family The family's folder name.
		@param then What to do with the folder once it is made, or null.
	**/
	function founds(family:String, ?then:String -> Void):Void {
		final keeper = folder;
		if (keeper == null) return;

		asks(Locale.PRESET_CATEGORY_NAME, "", function(said:String):Void {
			final made = keeper.makes(family, said);

			if (made == "") {
				session.says(Locale.SAID_CATEGORY_UNMADE, said);
				return;
			}

			if (then != null) then(made);
			shelved(true, said);
		});
	}

	/**
		Asks for a line of text through whoever can, and hands the answer on where one came.

		@param asking What is asked.
		@param said What the field starts with.
		@param then What to do with the answer.
	**/
	function asks(asking:Locale, said:String, then:String -> Void):Void {
		if (onAsk != null) onAsk(asking, said, then);
	}

	/**
		Asks whether to go ahead, through whoever can.

		@param question What is asked.
		@param going What the answer that goes ahead says.
		@param then What going ahead does.
	**/
	function confirms(question:String, going:String, then:Void -> Void):Void {
		if (onConfirm != null) onConfirm(question, going, then);
	}

	/**
		Says what a change to the presets folder came to and has the library read again.

		@param done Whether the change was made.
		@param name What it was made to.
	**/
	function shelved(done:Bool, name:String):Void {
		if (!done) {
			session.says(Locale.SAID_PRESETS_UNCHANGED, name);
			return;
		}

		if (onShelved != null) onShelved();

		session.say(name);
		session.changed();
	}

	function icons(offer:Offer):Menu {
		final out = new Menu();

		fires(out.offer(new Choice(translate(Locale.ICON_NONE))), function():Void
			iconed(offer, -1));

		out.divide();

		final seen:Array<String> = [];

		for (group in Icon.GROUPS) if (seen.indexOf(group) < 0) seen.push(group);

		for (group in seen) {
			out.offer(new Choice(titled(group))).submenu = drawn(offer, group);
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

	function drawn(offer:Offer, group:String):Menu {
		final out = new Menu();

		for (index in 0...Icon.COUNT) {
			if (Icon.GROUPS[index] != group) continue;

			final want = index;
			fires(out.offer(new Choice(Icon.NAMES[want])), function():Void iconed(offer, want));
		}

		return out;
	}

	/**
		Gives a preset another icon: the piece's own copy of one it carries, and the file of one in
		the presets folder.

		@param offer The preset.
		@param icon The icon, or -1 for none.
	**/
	function iconed(offer:Offer, icon:Int):Void {
		if (offer.owned()) {
			final instrument = session.song.instrumentAt(offer.index);
			if (instrument == null) return;

			instrument.icon = icon;
			session.changed();

			return;
		}

		final keeper = folder;
		if (keeper == null || !offer.filed()) return;

		shelved(keeper.reicons(session.library, offer.shelf, offer.place, icon), offer.preset.name);
	}

	/**
		Stars one preset, or takes the star off it, and says which it did.

		@param held The preset.
	**/
	function stars(held:Instrument):Void {
		final starring = favourites;

		if (starring == null || held.id == "") return;

		final on = starring.toggles(held.id);

		session.say(translate(on ? Locale.PRESET_FAVOURITE : Locale.PRESET_UNFAVOURITE)
			+ ": " + held.name);

		fit();
		invalidate();
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

		final kind = kinds.indexOf(item);

		if (kind >= 0) {
			menu = new Menu();
			folding(menu);

			final keeper = folder;

			if (keeper != null) {
				final family = kindKeys[kind];

				menu.divide();
				fires(menu.offer(new Choice(translate(Locale.PRESET_NEW_CATEGORY))), function():Void
					founds(family));
			}

			root.pop(menu, px, py, this);
			return;
		}

		final at = groups.indexOf(item);

		if (at < 0) {
			preset(item, px, py);
			return;
		}

		menu = new Menu();

		if (kits[at]) {
			fires(menu.offer(new Choice(translate(Locale.PRESET_KIT))), function():Void
				picked(item));
			menu.divide();
		}

		folding(menu);
		menu.divide();

		final name = groupTitles[at];
		final presets:Array<Instrument> = [];
		final samples:Array<Null<Sample>> = [];

		for (index in 0...held.length) {
			if (held[index].parent != item) continue;

			presets.push(shown[index].preset);
			samples.push(shown[index].sample);
		}

		if (presets.length > 0) {
			fires(menu.offer(new Choice(translate(Locale.PRESET_SAVE_BANK))), function():Void
				if (onWriteBank != null) onWriteBank(name, presets, samples));
		}

		if (grouping != GROUP_BANK) {
			root.pop(menu, px, py, this);
			return;
		}

		fires(menu.offer(new Choice(translate(Locale.PRESET_HIDE_BANK))), function():Void
			hidesBank(name, true));

		final keeper = folder;
		final home = homeOf(groupFamilies[at], name);

		if (keeper != null && home != "") {
			final library = session.library;
			final shelf = library == null ? -1 : library.names.indexOf(name);
			final tags = shelf < 0 ? [] : library.tagsOf(shelf);
			final bankFile = !sys.FileSystem.isDirectory(home);

			menu.divide();

			fires(menu.offer(new Choice(translate(Locale.PRESET_RENAME))), function():Void
				asks(Locale.PRESET_CATEGORY_NAME, name, function(said:String):Void
					shelved(bankFile ? keeper.renamesBank(home, said)
						: keeper.renamesFolder(home, said) != "", said)));

			fires(menu.offer(new Choice(translate(Locale.PRESET_TAGS), tags.length == 0 ? ""
				: "" + tags.length)), function():Void
				asks(Locale.PRESET_TAGS, tags.join(", "), function(said:String):Void
					shelved(keeper.tagsCategory(home, said.split(",")), name)));

			fires(menu.offer(new Choice(translate(Locale.PRESET_DELETE))), function():Void
				confirms(filled(Locale.PRESET_DELETE_ASKED, [name]), translate(Locale.PRESET_DELETE),
					function():Void shelved(keeper.deletesCategory(home), name)));
		}

		root.pop(menu, px, py, this);
	}

	/**
		@param family A family's folder name.
		@param bank A bank listed under it.
		@return What the bank is on disk under that family, the folder its presets sit loose in or
			the one bank file that holds them all, or an empty string where it is neither, as for a
			bank that ships, the piece's own, or the presets sitting loose in the family's folder,
			which is no category of its own.
	**/
	function homeOf(family:String, bank:String):String {
		final library = session.library;
		if (library == null || bank == translate(Locale.PRESET_SAVED)) return "";

		final folder = library.folderOf(family, bank);
		if (folder != "") return folder;

		final at = library.names.indexOf(bank);
		if (at < 0 || !library.owned[at]) return "";

		var file = "";

		for (which in 0...library.paths[at].length) {
			if (library.instruments[at][which].kind.family() != family) continue;

			final path = library.paths[at][which];

			if (path == "" || (file != "" && file != path)) return "";
			file = path;
		}

		return StringTools.endsWith(file.toLowerCase(), mdd.song.Library.BANK) ? file : "";
	}

	function folding(into:Menu):Void {
		fires(into.offer(new Choice(translate(Locale.PRESET_EXPAND_ALL))), function():Void
			opensAll(true));

		fires(into.offer(new Choice(translate(Locale.PRESET_COLLAPSE_ALL))), function():Void
			opensAll(false));
	}

	/**
		@param item A row.
		@return Which preset it stands for, or null for a heading.
	**/
	public function presetOf(item:Item):Null<Instrument> {
		final at = held.indexOf(item);
		return at < 0 ? null : shown[at].preset;
	}

	/**
		@param item A row.
		@return Which preset the piece carries it stands for, by index into the piece, or -1 for a
			heading or a preset only the library holds.
	**/
	public function instrumentOf(item:Item):Int {
		final at = held.indexOf(item);
		return at < 0 ? -1 : shown[at].index;
	}

	/**
		@param item A row.
		@return The bank the preset it stands for is listed under, or an empty string for a
			heading.
	**/
	public function bankOf(item:Item):String {
		final at = held.indexOf(item);
		return at < 0 ? "" : shown[at].bank;
	}

	static final KINDS:Array<Part> = [Part.Fm1, Part.Psg1, Part.Noise, Part.Dac];

	/**
		Changes the grouping and builds the rows again.

		@param which Which grouping, `GROUP_BANK` to `GROUP_NONE`.
	**/
	public function groupsBy(which:Int):Void {
		final want = which < 0 ? 0 : (which >= GROUPINGS ? GROUPINGS - 1 : which);
		if (want == grouping) return;

		grouping = want;
		viewed(translate(GROUP_NAMES[grouping]));
	}

	/**
		Changes the sorting and builds the rows again.

		@param which Which sorting, `SORT_NAME` to `SORT_LISTED`.
	**/
	public function sortsBy(which:Int):Void {
		final want = which < 0 ? 0 : (which >= SORTS ? SORTS - 1 : which);
		if (want == sorting) return;

		sorting = want;
		viewed(translate(SORT_NAMES[sorting]));
	}

	/**
		Runs the sorting the other way, or back.

		@param on Whether it runs the other way.
	**/
	public function reverses(on:Bool):Void {
		if (on == reversed) return;

		reversed = on;
		viewed(translate(Locale.PRESET_REVERSE));
	}

	/**
		Shows or hides every preset from one source.

		@param source Which, `Offer.DEFAULT` to `Offer.PROJECT`.
		@param hidden Whether it is hidden.
	**/
	public function hidesSource(source:Int, hidden:Bool):Void {
		if (source < 0 || source >= hiddenSources.length || hiddenSources[source] == hidden) return;

		hiddenSources[source] = hidden;
		viewed(translate(SOURCE_NAMES[source]));
	}

	/**
		@param source Which, `Offer.DEFAULT` to `Offer.PROJECT`.
		@return Whether it is hidden.
	**/
	public inline function hides(source:Int):Bool {
		return source >= 0 && source < hiddenSources.length && hiddenSources[source];
	}

	/**
		Shows only the starred, or everything again.

		@param on Whether only the starred are shown.
	**/
	public function starsOnly(on:Bool):Void {
		if (on == starredOnly) return;

		starredOnly = on;
		viewed(translate(Locale.PRESET_FAVOURITES_ONLY));
	}

	/**
		Shows only what the open piece plays or was loaded from, or everything again.

		@param on Whether only those are shown.
	**/
	public function usesOnly(on:Bool):Void {
		if (on == usedOnly) return;

		usedOnly = on;
		viewed(translate(Locale.PRESET_USED_ONLY));
	}

	/**
		Shows a sound that sits in several banks once, or everywhere it sits.

		@param on Whether it is shown once.
	**/
	public function hidesDuplicates(on:Bool):Void {
		if (on == single) return;

		single = on;
		viewed(translate(Locale.PRESET_HIDE_DUPLICATES));
	}

	/**
		Asks for a tag every preset shown must carry, or stops asking for it.

		@param tag The tag.
		@param on Whether it is asked for.
	**/
	public function wantsTag(tag:String, on:Bool):Void {
		final at = indexIgnoringCase(wantedTags, tag);

		if (on == (at >= 0)) return;

		if (on) wantedTags.push(tag);
		else wantedTags.splice(at, 1);

		viewed(tag);
	}

	/**
		Hides a bank, or shows it again.

		@param name The bank.
		@param hidden Whether it is hidden.
	**/
	public function hidesBank(name:String, hidden:Bool):Void {
		final at = hiddenBanks.indexOf(name);

		if (hidden == (at >= 0)) return;

		if (hidden) hiddenBanks.push(name);
		else hiddenBanks.splice(at, 1);

		viewed(name);
	}

	/**
		Turns every filter off, the search aside.
	**/
	public function clearsFilters():Void {
		for (at in 0...hiddenSources.length) hiddenSources[at] = false;

		starredOnly = false;
		usedOnly = false;
		single = false;
		wantedTags.resize(0);
		hiddenBanks.resize(0);

		viewed(translate(Locale.PRESET_CLEAR_FILTERS));
	}

	/**
		@return How many filters are on, which the filter button shows.
	**/
	public function filtering():Int {
		var many = wantedTags.length + hiddenBanks.length;

		for (hidden in hiddenSources) if (hidden) many++;
		if (starredOnly) many++;
		if (usedOnly) many++;
		if (single) many++;

		return many;
	}

	/**
		Builds the rows again after the view changed, says what changed and asks for it to be kept.

		@param said What to say.
	**/
	function viewed(said:String):Void {
		fit();

		session.say(said);
		session.changed();

		if (onView != null) onView();

		relayout();
	}

	/**
		@return The grouping, the sorting and every filter as one line, which is how the settings
			keep them.
	**/
	public function spelt():String {
		var sources = 0;
		for (at in 0...hiddenSources.length) if (hiddenSources[at]) sources |= 1 << at;

		return grouping + "," + sorting + "," + (reversed ? 1 : 0) + "," + sources + ","
			+ (starredOnly ? 1 : 0) + "," + (usedOnly ? 1 : 0) + "," + (single ? 1 : 0) + ";"
			+ coded(wantedTags) + ";" + coded(hiddenBanks);
	}

	/**
		Takes back what `spelt` wrote. Anything that does not read is left as it is.

		@param said The line.
	**/
	public function reads(said:String):Void {
		final parts = said.split(";");
		final numbers = parts[0].split(",");

		if (numbers.length >= 7) {
			final group = Std.parseInt(numbers[0]);
			final sort = Std.parseInt(numbers[1]);
			final sources = Std.parseInt(numbers[3]);

			if (group != null && group >= 0 && group < GROUPINGS) grouping = group;
			if (sort != null && sort >= 0 && sort < SORTS) sorting = sort;

			reversed = numbers[2] == "1";
			starredOnly = numbers[4] == "1";
			usedOnly = numbers[5] == "1";
			single = numbers[6] == "1";

			for (at in 0...hiddenSources.length) {
				hiddenSources[at] = sources != null && (sources & (1 << at)) != 0;
			}
		}

		wantedTags.resize(0);
		hiddenBanks.resize(0);

		if (parts.length > 1) decoded(parts[1], wantedTags);
		if (parts.length > 2) decoded(parts[2], hiddenBanks);
	}

	static function coded(names:Array<String>):String {
		final out:Array<String> = [];
		for (name in names) out.push(StringTools.urlEncode(name));

		return out.join(",");
	}

	static function decoded(said:String, into:Array<String>):Void {
		for (one in said.split(",")) {
			if (one == "") continue;

			final name = StringTools.urlDecode(one);
			if (name != "" && into.indexOf(name) < 0) into.push(name);
		}
	}

	/**
		@return Where the toolbar row the buttons sit in starts, down.
	**/
	public inline function toolbarTop():Float {
		return barTop;
	}

	/**
		@param which A toolbar button, from the grouping at nought to the folder at three.
		@return Where it sits, across.
	**/
	public inline function chipLeftOf(which:Int):Float {
		return chipLeft[which];
	}

	/**
		@param which A toolbar button.
		@return How wide it is.
	**/
	public inline function chipWideOf(which:Int):Float {
		return chipWide[which];
	}

	/**
		@return How many buttons the toolbar holds.
	**/
	public inline function chips():Int {
		return CHIPS;
	}

	/**
		@param px A point, across.
		@param py A point, down.
		@return Which toolbar button the point is on, or -1 for none.
	**/
	public function chipAt(px:Float, py:Float):Int {
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
		return switch (which) {
			case GROUP_CHIP:
				final name = translate(GROUP_NAMES[grouping]);
				terse ? name : filled(Locale.PRESET_GROUP, [name]);

			case SORT_CHIP:
				final name = translate(SORT_NAMES[sorting]);
				(terse ? name : filled(Locale.PRESET_SORT, [name])) + (reversed ? " ↑" : "");

			case FILTER_CHIP:
				final many = filtering();
				translate(Locale.PRESET_FILTER) + (many > 0 ? " " + many : "");

			case _: translate(Locale.PRESET_FOLDER);
		}
	}

	/**
		Lays the toolbar out along its row: the grouping, the sorting and the filters at the start
		and the folder at the end, each as wide as its label. Where the row is narrower than they
		are, the grouping and the sorting say only what they are set to, and where it is narrower
		still they are all squeezed evenly.

		@param left Where the row starts, across.
		@param room How wide it is.
	**/
	function lays(left:Float, room:Float):Void {
		final root = root();
		final metrics = root == null ? null : root.metrics;
		final font = metrics == null ? null : (metrics.small == null ? metrics.body : metrics.small);
		final pad = metrics == null ? 8 : metrics.gap;
		final gap = pad * 0.5;

		var total = 0.0;

		for (pass in 0...2) {
			terse = pass == 1;
			total = gap * (CHIPS - 1);

			for (which in 0...CHIPS) {
				chipWide[which] = (font == null ? 60 : font.measure(chipLabel(which))) + pad * 2;
				total += chipWide[which];
			}

			if (total <= room) break;
		}

		if (total > room) {
			final gaps = gap * (CHIPS - 1);
			final scale = room > gaps ? (room - gaps) / (total - gaps) : 0;

			for (which in 0...CHIPS) chipWide[which] = Math.max(0, chipWide[which] * scale);
		}

		var pen = left;

		for (which in 0...FOLDER_CHIP) {
			chipLeft[which] = pen;
			pen += chipWide[which] + gap;
		}

		chipLeft[FOLDER_CHIP] = left + room - chipWide[FOLDER_CHIP];
	}

	/**
		What each toolbar button does, in the order the buttons stand.
	**/
	static final CHIP_TIPS:Array<Locale> = [Locale.PRESET_GROUP_TIP, Locale.PRESET_SORT_TIP,
		Locale.PRESET_FILTER_TIP, Locale.PRESET_FOLDER_TIP];

	override function took(event:mdd.ui.Input):Bool {
		if (event.kind == mdd.ui.Kind.PointerMove) {
			final over = chipAt(event.x, event.y);
			tip = over < 0 ? "" : translate(CHIP_TIPS[over]);
			return false;
		}

		if (event.kind != mdd.ui.Kind.PointerDown) return false;

		final which = chipAt(event.x, event.y);
		if (which < 0) return false;

		if (which == FOLDER_CHIP) {
			if (onFolder != null) onFolder();
			return true;
		}

		final root = root();
		if (root == null) return true;

		menu = switch (which) {
			case GROUP_CHIP: groupMenu();
			case SORT_CHIP: sortMenu();
			case _: filterMenu();
		}

		root.pop(menu, chipLeft[which], barTop + barTall, this);
		return true;
	}

	/**
		@return The menu of groupings, the chosen one ticked.
	**/
	public function groupMenu():Menu {
		final out = new Menu();
		out.ticking = true;

		for (which in 0...GROUPINGS) {
			final pick = which;
			final choice = out.offer(new Choice(translate(GROUP_NAMES[pick])));
			choice.ticked = pick == grouping;

			fires(choice, function():Void groupsBy(pick));
		}

		return out;
	}

	/**
		@return The menu of sortings, the chosen one ticked, and the way they run.
	**/
	public function sortMenu():Menu {
		final out = new Menu();
		out.ticking = true;

		for (which in 0...SORTS) {
			final pick = which;
			final choice = out.offer(new Choice(translate(SORT_NAMES[pick])));
			choice.ticked = pick == sorting;

			fires(choice, function():Void sortsBy(pick));
		}

		out.divide();

		final turning = out.offer(new Choice(translate(Locale.PRESET_REVERSE)));
		turning.ticked = reversed;

		fires(turning, function():Void reverses(!reversed));

		return out;
	}

	/**
		@return The menu of filters: the sources, the starred, what the piece plays, duplicates,
			the tags most used, the hidden banks, and a way to turn them all off.
	**/
	public function filterMenu():Menu {
		final out = new Menu();
		out.ticking = true;

		final sources = new Menu();
		sources.ticking = true;

		for (source in SOURCE_ORDER) {
			final pick = source;
			final choice = sources.offer(new Choice(translate(SOURCE_NAMES[pick])));
			choice.ticked = !hiddenSources[pick];

			fires(choice, function():Void hidesSource(pick, !hiddenSources[pick]));
		}

		out.offer(new Choice(translate(Locale.PRESET_BY_SOURCE))).submenu = sources;
		out.divide();

		final starring = out.offer(new Choice(translate(Locale.PRESET_FAVOURITES_ONLY)));
		starring.ticked = starredOnly;
		fires(starring, function():Void starsOnly(!starredOnly));

		final playing = out.offer(new Choice(translate(Locale.PRESET_USED_ONLY)));
		playing.ticked = usedOnly;
		fires(playing, function():Void usesOnly(!usedOnly));

		final once = out.offer(new Choice(translate(Locale.PRESET_HIDE_DUPLICATES)));
		once.ticked = single;
		fires(once, function():Void hidesDuplicates(!single));

		final tags = new Menu();
		tags.ticking = true;

		for (tag in offeredTags()) {
			final pick = tag;
			final choice = tags.offer(new Choice(pick));
			choice.ticked = indexIgnoringCase(wantedTags, pick) >= 0;

			fires(choice, function():Void wantsTag(pick, indexIgnoringCase(wantedTags, pick) < 0));
		}

		final tagging = out.offer(new Choice(translate(Locale.PRESET_TAGS)));
		if (tags.choices.length > 0) tagging.submenu = tags;
		else tagging.enabled = false;

		final hidden = new Menu();
		hidden.ticking = true;

		for (bank in hiddenBanks) {
			final pick = bank;
			fires(hidden.offer(new Choice(pick)), function():Void hidesBank(pick, false));
		}

		final hiding = out.offer(new Choice(translate(Locale.PRESET_HIDDEN_BANKS),
			hiddenBanks.length == 0 ? "" : "" + hiddenBanks.length));

		if (hidden.choices.length > 0) hiding.submenu = hidden;
		else hiding.enabled = false;

		out.divide();

		final clearing = out.offer(new Choice(translate(Locale.PRESET_CLEAR_FILTERS)));
		clearing.enabled = filtering() > 0;
		fires(clearing, function():Void clearsFilters());

		return out;
	}

	/**
		@return The tags the filter menu offers: those asked for already, and then the most used
			among everything on offer, in the order a person reads them.
	**/
	function offeredTags():Array<String> {
		final counts = new haxe.ds.StringMap<Int>();
		final spelled = new haxe.ds.StringMap<String>();
		final keys:Array<String> = [];

		for (offer in offers) {
			for (tag in offer.preset.tags) {
				final key = tag.toLowerCase();
				final many = counts.get(key);

				if (many == null) {
					counts.set(key, 1);
					spelled.set(key, tag);
					keys.push(key);
				} else {
					counts.set(key, many + 1);
				}
			}
		}

		keys.sort(function(one:String, two:String):Int {
			final apart = counts.get(two) - counts.get(one);
			return apart != 0 ? apart : mdd.Names.inOrder(one, two);
		});

		final out:Array<String> = [];

		for (tag in wantedTags) out.push(tag);

		for (key in keys) {
			if (out.length >= TAGS_OFFERED + wantedTags.length) break;

			final tag = spelled.get(key);
			if (indexIgnoringCase(out, tag) < 0) out.push(tag);
		}

		out.sort(function(one:String, two:String):Int return mdd.Names.inOrder(one, two));

		return out;
	}

	/**
		@param names Some names.
		@param name A name.
		@return Where the name is among them, ignoring case, or -1.
	**/
	static function indexIgnoringCase(names:Array<String>, name:String):Int {
		final want = name.toLowerCase();

		for (at in 0...names.length) if (names[at].toLowerCase() == want) return at;

		return -1;
	}

	/**
		Takes the search apart into the words it asks for.

		@param said What is typed.
	**/
	function parses(said:String):Void {
		words.resize(0);
		notWords.resize(0);
		tagWords.resize(0);
		notTagWords.resize(0);
		bankWords.resize(0);
		notBankWords.resize(0);

		wantsStarred = false;
		wantsUsed = false;

		final text = said.toLowerCase();
		var at = 0;

		while (at < text.length) {
			while (at < text.length && StringTools.isSpace(text, at)) at++;
			if (at >= text.length) break;

			var negated = false;

			if (StringTools.fastCodeAt(text, at) == "-".code && at + 1 < text.length
					&& !StringTools.isSpace(text, at + 1)) {
				negated = true;
				at++;
			}

			var field = "";
			final colon = text.indexOf(":", at);
			final space = spaceAfter(text, at);

			if (colon > at && colon < space) {
				field = text.substring(at, colon);
				at = colon + 1;
			}

			var word = "";

			if (at < text.length && StringTools.fastCodeAt(text, at) == "\"".code) {
				final close = text.indexOf("\"", at + 1);
				final end = close < 0 ? text.length : close;

				word = text.substring(at + 1, end);
				at = end + 1;
			} else {
				final end = spaceAfter(text, at);

				word = text.substring(at, end);
				at = end;
			}

			if (word == "") continue;

			switch (field) {
				case "tag": (negated ? notTagWords : tagWords).push(word);
				case "bank": (negated ? notBankWords : bankWords).push(word);

				case "is":
					if (word == "fav" && !negated) wantsStarred = true;
					if (word == "used" && !negated) wantsUsed = true;

				case _:
					if (field == "" && !negated && word == "fav") wantsStarred = true;
					else if (field == "" && !negated && word == "used") wantsUsed = true;
					else (negated ? notWords : words).push(field == "" ? word : field + ":" + word);
			}
		}
	}

	/**
		@param text Some text.
		@param from Where to start.
		@return Where the next space is, or the end.
	**/
	static function spaceAfter(text:String, from:Int):Int {
		var at = from;
		while (at < text.length && !StringTools.isSpace(text, at)) at++;

		return at;
	}

	/**
		@param offer A preset on offer.
		@return Whether it passes every filter and every word in the search. The family is not
			asked about here.
	**/
	function passes(offer:Offer):Bool {
		if (hides(offer.source)) return false;
		if (hiddenBanks.indexOf(offer.bank) >= 0) return false;

		final instrument = offer.preset;

		if (starredOnly || wantsStarred) {
			final starring = favourites;
			if (starring == null || !starring.favours(instrument.id)) return false;
		}

		if ((usedOnly || wantsUsed) && !offer.owned() && !used.exists(instrument.id)) return false;

		for (tag in wantedTags) if (!answers(offer, tag.toLowerCase(), true)) return false;

		for (word in words) if (!instrument.tagged(word) && !answers(offer, word, false)) return false;
		for (word in notWords) if (instrument.tagged(word) || answers(offer, word, false)) return false;
		for (word in tagWords) if (!answers(offer, word, false)) return false;
		for (word in notTagWords) if (answers(offer, word, false)) return false;

		if (bankWords.length > 0 || notBankWords.length > 0) {
			final bank = offer.bank.toLowerCase();

			for (word in bankWords) if (bank.indexOf(word) < 0) return false;
			for (word in notBankWords) if (bank.indexOf(word) >= 0) return false;
		}

		return true;
	}

	/**
		@param offer A preset on offer.
		@param word A word in lower case.
		@param whole Whether a tag has to be the word rather than hold it.
		@return Whether one of its tags, or of its bank's own, answers to the word.
	**/
	function answers(offer:Offer, word:String, whole:Bool):Bool {
		if (carries(offer.preset, word, whole)) return true;

		for (tag in bankTagsOf(offer)) {
			final lower = tag.toLowerCase();
			if (whole ? lower == word : lower.indexOf(word) >= 0) return true;
		}

		return false;
	}

	/**
		@param offer A preset on offer.
		@return Its bank's own tags, which it answers to as well, or none for one the piece
			carries.
	**/
	function bankTagsOf(offer:Offer):Array<String> {
		final library = session.library;
		if (library == null || offer.shelf < 0 || offer.shelf >= library.bankTags.length) return NONE;

		return library.bankTags[offer.shelf];
	}

	static final NONE:Array<String> = [];

	/**
		@param instrument A preset.
		@param word A word in lower case.
		@param whole Whether a tag has to be the word rather than hold it.
		@return Whether one of its tags answers to the word.
	**/
	static function carries(instrument:Instrument, word:String, whole:Bool):Bool {
		for (tag in instrument.tags) {
			final lower = tag.toLowerCase();
			if (whole ? lower == word : lower.indexOf(word) >= 0) return true;
		}

		return false;
	}

	/**
		@param offer A preset on offer.
		@return How alike it is to what the chosen part is playing, as a fraction of one, or
			nought where the part plays nothing.
	**/
	function likeness(offer:Offer):Float {
		final playing = session.song.instrumentAt(session.song.rack[session.part.index()]);
		return playing == null ? 0 : offer.preset.likeness(playing);
	}

	/**
		Orders the presets of one group by the chosen sorting, with the name deciding a tie.

		@param list The presets.
	**/
	function ordered(list:Array<Offer>):Void {
		final by = sorting;
		final flip = reversed ? -1 : 1;

		list.sort(function(one:Offer, two:Offer):Int {
			var apart = switch (by) {
				case SORT_ADDED: two.time < one.time ? -1 : (two.time > one.time ? 1 : 0);
				case SORT_LIKENESS: two.alike < one.alike ? -1 : (two.alike > one.alike ? 1 : 0);
				case SORT_LISTED: one.order - two.order;
				case _: 0;
			}

			if (apart == 0) apart = mdd.Names.inOrder(one.preset.name, two.preset.name);
			if (apart == 0) apart = one.order - two.order;

			return apart * flip;
		});
	}

	/**
		Takes an offer out of the pool and fills it in.

		@param preset The preset.
		@param sample What it plays, or null.
		@param bank The bank it is listed under.
		@param source Where it comes from.
		@param index Its index into the piece, or -1.
		@param shelf Its bank's position in the library, or -1.
	**/
	function offered(preset:Instrument, sample:Null<Sample>, bank:String, source:Int, index:Int,
			shelf:Int):Void {
		if (offers.length == pool.length) pool.push(new Offer(preset));

		final out = pool[offers.length];

		out.holds(preset, sample, bank, source, index, shelf);
		out.order = offers.length;

		final dates = added;
		if (dates != null && source == Offer.MINE) out.time = dates.when(preset.id);

		offers.push(out);
	}

	/**
		Gathers everything on offer: the starting bank first, then the presets the piece carries
		because it plays them, then every other bank the library holds.
	**/
	function gathers():Void {
		offers.resize(0);

		shelves(true);
		project();
		shelves(false);
	}

	/**
		Gathers the library's banks.

		@param starting Whether to gather the starting bank alone, or every bank but it.
	**/
	function shelves(starting:Bool):Void {
		final library = session.library;
		if (library == null) return;

		for (at in 0...library.names.length) {
			final name = library.names[at];
			if ((name == mdd.song.Library.STARTERS) != starting) continue;

			final owned = library.owned[at];
			final held = library.instruments[at];

			for (which in 0...held.length) {
				final path = library.paths[at][which];
				final source = !owned ? (starting ? Offer.DEFAULT : Offer.SHIPPED)
					: (planted.indexOf(path) >= 0 ? Offer.SHIPPED : Offer.MINE);

				offered(held[which], library.samples[at][which], name, source, -1, at);

				final offer = offers[offers.length - 1];

				offer.place = which;
				offer.kept = owned && path != "";
			}
		}
	}

	/**
		Gathers the presets the piece carries because it plays them, under one bank of their own,
		and notes every identity they carry or came from.
	**/
	function project():Void {
		final song = session.song;
		final needed = mdd.format.Needed.of(song);
		final named = translate(Locale.PRESET_FROM_PROJECT);

		used.clear();

		for (index in 0...song.instruments.length) {
			if (needed.instrument(index) < 0) continue;

			final held = song.instruments[index];

			if (held.id != "") used.set(held.id, true);
			if (held.from != "") used.set(held.from, true);

			offered(held, song.sampleAt(held.sample), named, Offer.PROJECT, index, -1);
		}
	}

	/**
		Adds the groups a preset is listed in under the chosen grouping to a list of them, each
		once.

		@param offer A preset on offer.
		@param into The groups found so far.
	**/
	function grouped(offer:Offer, into:Array<String>):Void {
		switch (grouping) {
			case GROUP_TAG:
				final own = bankTagsOf(offer);

				if (offer.preset.tags.length == 0 && own.length == 0) {
					final none = translate(Locale.PRESET_NO_TAG);
					if (into.indexOf(none) < 0) into.push(none);
					return;
				}

				for (tag in offer.preset.tags) if (indexIgnoringCase(into, tag) < 0) into.push(tag);
				for (tag in own) if (indexIgnoringCase(into, tag) < 0) into.push(tag);

			case GROUP_ADDED:
				final name = translate(AGE_NAMES[ageOf(offer)]);
				if (into.indexOf(name) < 0) into.push(name);

			case GROUP_SOURCE:
				final name = translate(SOURCE_NAMES[offer.source]);
				if (into.indexOf(name) < 0) into.push(name);

			case GROUP_NONE:

			case _:
				if (into.indexOf(offer.bank) < 0) into.push(offer.bank);
		}
	}

	/**
		@param offer A preset on offer.
		@param group A group's name.
		@return Whether it is listed in that group under the chosen grouping.
	**/
	function belongs(offer:Offer, group:String):Bool {
		return switch (grouping) {
			case GROUP_TAG:
				offer.preset.tags.length == 0 && bankTagsOf(offer).length == 0
					? group == translate(Locale.PRESET_NO_TAG) : answers(offer, group.toLowerCase(), true);

			case GROUP_ADDED: group == translate(AGE_NAMES[ageOf(offer)]);
			case GROUP_SOURCE: group == translate(SOURCE_NAMES[offer.source]);
			case GROUP_NONE: true;
			case _: offer.bank == group;
		}
	}

	/**
		@param offer A preset on offer.
		@return Which span its date added falls in, as an index into `AGE_NAMES`.
	**/
	function ageOf(offer:Offer):Int {
		if (offer.time <= 0) return AGE_NAMES.length - 1;

		final apart = clock - offer.time;

		for (at in 0...AGES.length) if (apart < AGES[at]) return at;

		return AGE_NAMES.length - 1;
	}

	/**
		Puts the groups of one family in their order: the starting bank and then the piece's own
		first where the grouping is by bank, the spans newest first, the sources in their order,
		and anything else in the order a person reads it, with no tag last.

		@param names The groups.
	**/
	function arranged(names:Array<String>):Void {
		final starting = mdd.song.Library.STARTERS;
		final own = translate(Locale.PRESET_FROM_PROJECT);
		final none = translate(Locale.PRESET_NO_TAG);

		switch (grouping) {
			case GROUP_ADDED:
				names.sort(function(one:String, two:String):Int return spanOf(one) - spanOf(two));

			case GROUP_SOURCE:
				names.sort(function(one:String, two:String):Int return sourceRank(one) - sourceRank(two));

			case _:
				names.sort(function(one:String, two:String):Int {
					final first = pinned(one, starting, own, none);
					final second = pinned(two, starting, own, none);

					if (first != second) return first - second;

					return mdd.Names.inOrder(one, two);
				});
		}
	}

	/**
		@param name A group's name.
		@param starting The starting bank's name.
		@param own What the piece's own are listed as.
		@param none What an untagged preset is listed as.
		@return Where a group is pinned: nought for the starting bank, one for the piece's own, two
			for anything else and three for no tag.
	**/
	function pinned(name:String, starting:String, own:String, none:String):Int {
		if (grouping == GROUP_BANK && name == starting) return 0;
		if (grouping == GROUP_BANK && name == own) return 1;
		if (grouping == GROUP_TAG && name == none) return 3;

		return 2;
	}

	function spanOf(name:String):Int {
		for (at in 0...AGE_NAMES.length) if (translate(AGE_NAMES[at]) == name) return at;

		return AGE_NAMES.length;
	}

	function sourceRank(name:String):Int {
		for (at in 0...SOURCE_ORDER.length) {
			if (translate(SOURCE_NAMES[SOURCE_ORDER[at]]) == name) return at;
		}

		return SOURCE_ORDER.length;
	}

	/**
		Builds the rows again from the library, the piece, the view and whatever is typed in the
		search.
	**/
	public function fit():Void {
		tree.clear();

		held.resize(0);
		shown.resize(0);
		kinds.resize(0);
		kindKeys.resize(0);
		groups.resize(0);
		groupKeys.resize(0);
		kits.resize(0);
		leads.resize(0);
		groupTitles.resize(0);
		groupFamilies.resize(0);

		listed = 0;
		banks = 0;

		clock = Date.now().getTime() / 1000;

		gathers();
		parses(seeking());

		final song = session.song;
		final chosen = song.rack[session.part.index()];
		final playing = song.instrumentAt(chosen);

		final hunting = seeking() != "" || filtering() > 0;
		final starring = favourites;
		final alike = sorting == SORT_LIKENESS;

		seen.clear();

		for (offer in offers) {
			if (alike && playing != null) offer.alike = offer.preset.likeness(playing);
		}

		for (kind in KINDS) {
			final kitting = kind.sampled();
			final family = kind.family();

			within.resize(0);

			for (offer in offers) {
				if (!mdd.song.Library.kin(offer.preset.kind, kind) || !passes(offer)) continue;

				if (single && offer.preset.id != "") {
					if (seen.exists(offer.preset.id)) continue;
					seen.set(offer.preset.id, true);
				}

				within.push(offer);
			}

			final empty = grouping == GROUP_BANK && !hunting ? categories(family) : 0;
			if (within.length == 0 && empty == 0) continue;

			groupNames.resize(0);
			for (offer in within) grouped(offer, groupNames);
			if (empty > 0) for (name in unfilled) if (groupNames.indexOf(name) < 0) groupNames.push(name);
			arranged(groupNames);

			final head = new Item(family);
			head.open = hunting || shut.indexOf(family) < 0;

			kinds.push(head);
			kindKeys.push(family);

			var total = 0;

			if (grouping == GROUP_NONE) {
				inside.resize(0);
				for (offer in within) inside.push(offer);

				ordered(inside);
				total += rows(head, inside, kind, alike, starring, false);
			} else {
				for (name in groupNames) {
					inside.resize(0);
					for (offer in within) if (belongs(offer, name)) inside.push(offer);

					if (inside.length == 0) {
						if (unfilled.indexOf(name) < 0) continue;

						final bare = head.add(new Item(name + "   0"));

						groups.push(bare);
						groupKeys.push(family + "/" + grouping + "/" + name);
						kits.push(false);
						leads.push(null);
						groupTitles.push(name);
						groupFamilies.push(family);

						continue;
					}

					ordered(inside);

					final kit = kitting && grouping == GROUP_BANK;
					final group = head.add(new Item(name + "   " + inside.length,
						kit ? Theme.PARTS[kind.index()] : -1));

					final key = family + "/" + grouping + "/" + name;

					group.icon = kit ? Icon.DRUMKIT : -1;
					group.open = hunting || opened.indexOf(key) >= 0;

					groups.push(group);
					groupKeys.push(key);
					kits.push(kit);
					leads.push(inside[0]);
					groupTitles.push(name);
					groupFamilies.push(family);

					total += rows(group, inside, kind, alike, starring, kit);
				}
			}

			head.label = family + "   " + total;

			tree.plant(head);
			banks++;
		}

		var at = -1;

		for (index in 0...shown.length) {
			if (shown[index].owned() && shown[index].index == chosen) {
				at = index;
				break;
			}
		}

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

	/**
		The categories of one family in the presets folder with nothing in them, which
		`categories` gathers.
	**/
	final unfilled:Array<String> = [];

	/**
		Gathers the categories of a family in the presets folder that hold nothing, so one just
		made shows before anything is put in it.

		@param family The family's folder name.
		@return How many there are.
	**/
	function categories(family:String):Int {
		unfilled.resize(0);

		final library = session.library;
		if (library == null) return 0;

		final saved = translate(Locale.PRESET_SAVED);

		for (at in 0...library.folders.length) {
			if (library.folderFamilies[at] != family) continue;

			final bank = library.folderBanks[at];
			if (bank == saved || hiddenBanks.indexOf(bank) >= 0 || unfilled.indexOf(bank) >= 0) continue;

			var held = false;

			for (offer in within) {
				if (offer.bank == bank) {
					held = true;
					break;
				}
			}

			if (!held) unfilled.push(bank);
		}

		return unfilled.length;
	}

	/**
		Hangs a row for each preset under a heading.

		@param under The heading.
		@param list The presets, in order.
		@param kind The family they are listed under.
		@param alike Whether each shows how alike it is rather than its tags.
		@param starring The stars, or null.
		@param kit Whether the heading is a kit, which counts once.
		@return How many presets were counted for the family, a kit counting once and a preset
			already counted under another heading not at all.
	**/
	function rows(under:Item, list:Array<Offer>, kind:Part, alike:Bool,
			starring:Null<mdd.app.Favourites>, kit:Bool):Int {
		var many = kit ? 1 : 0;

		for (offer in list) {
			final instrument = offer.preset;
			final child = under.add(new Item(instrument.name, Theme.PARTS[kind.index()]));

			child.icon = instrument.icon;
			child.mark = starring != null && starring.favours(instrument.id) ? Icon.STAR : -1;
			child.note = alike ? Math.round(offer.alike * 100) + " %" : briefly(instrument.tags);
			child.says = instrument.tags.length == 0 ? "" : instrument.tags.join(", ");

			shown.push(offer);
			held.push(child);

			if (!kit && !offer.counted) many++;
			offer.counted = true;
		}

		listed += many;
		return many;
	}

	function reveals():Void {
		if (!pending || tree.height <= 0) return;

		tree.reveal();
		pending = false;
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
		Draws one of the buttons in the toolbar.

		@param paint Where to draw.
		@param label What it says.
		@param left Where it sits, across.
		@param chip How wide it is.
		@param lit Whether it stands for something that is on.
	**/
	function chipped(paint:Paint, label:String, left:Float, chip:Float, lit:Bool):Void {
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
		if (lit) paint.roundedRect(left, at, chip, deep, metrics.radiusSmall, theme.accent, Theme.SELECT);

		paint.outline(left, at, chip, deep, lit ? theme.accent : theme.frame, metrics.whole(1), 0.7,
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

		for (which in 0...CHIPS) {
			chipped(paint, chipLabel(which), chipLeft[which], chipWide[which],
				which == FILTER_CHIP && filtering() > 0);
		}

		if (listed == 0) {
			paint.text(translate(Locale.PANEL_NO_PRESETS), x + metrics.inset,
				tree.y + metrics.gap + font.ascent, theme.dim, 0.6);
			return;
		}

		tree.paint(paint);
	}
}
