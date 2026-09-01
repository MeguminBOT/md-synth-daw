package mdd.view;

import mdd.song.Instrument;
import mdd.song.Part;
import mdd.ui.Input;
import mdd.ui.Item;
import mdd.ui.Paint;
import mdd.ui.Theme;
import mdd.ui.Tree;
import mdd.ui.Widget;

@:unreflective
final class Presets extends Widget {
	public final session:Session;
	public final tree:Tree;

	public var listed(default, null):Int = 0;
	public var banks(default, null):Int = 0;

	final named:Array<Int> = [];
	final held:Array<Item> = [];

	public function new(session:Session) {
		super();
		this.session = session;

		opaque = true;

		tree = new Tree();
		add(tree);

		tree.onChoose = function(item:Item):Void picked(item);
	}

	function picked(item:Item):Void {
		final at = held.indexOf(item);
		if (at < 0) return;

		session.song.rack[session.part.index()] = named[at];
		session.say("loaded " + session.song.instruments[named[at]].name + " into "
			+ session.part.name());
		session.changed();
	}

	public function instrumentOf(item:Item):Int {
		final at = held.indexOf(item);
		return at < 0 ? -1 : named[at];
	}

	public function fit():Void {
		tree.clear();

		named.resize(0);
		held.resize(0);

		listed = 0;
		banks = 0;

		final song = session.song;
		final part = session.part;
		final chosen = song.rack[part.index()];

		for (at in 0...song.banks.length) {
			final bank = song.banks[at];
			final holds:Array<Int> = [];

			for (index in bank.instruments) {
				final instrument = song.instrumentAt(index);
				if (instrument == null || !suits(instrument, part)) continue;

				holds.push(index);
			}

			if (holds.length == 0) continue;

			final head = new Item(bank.name + (bank.kept ? "" : "   from the import"));

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
		if (at >= 0) tree.choose(held[at]);

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
