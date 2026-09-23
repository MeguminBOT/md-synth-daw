package mdd.view.overlay;

import mdd.app.Locale;
import mdd.app.Session;
import mdd.song.Song;
import mdd.ui.Input;
import mdd.ui.Key;
import mdd.ui.Kind;
import mdd.ui.Paint;
import mdd.ui.Widget;
import mdd.ui.control.Button;
import mdd.ui.control.Field;

@:unreflective

/**
	The sheet that describes the piece: its title, artist, composer, album, year, genre, track number
	and comment. They are kept in the project file and written into whatever is exported from it as
	tags.

	What is typed changes nothing until the sheet is accepted, and accepting it is one step on the
	undo stack however many of them changed.
**/
final class Describing extends Widget {
	/**
		The session whose piece is described.
	**/
	public var session:Session;

	/**
		One field a description, in the order `Song.TITLE` to `Song.COMMENT` gives them.
	**/
	public final fields:Array<Field> = [];

	/**
		Accepts what is typed.
	**/
	public final keep:Button;

	/**
		Closes the sheet and forgets what is typed.
	**/
	public final cancel:Button;

	/**
		Called when it closes either way.
	**/
	public var onShut:Null<Void -> Void> = null;

	static final NAMES:Array<Locale> = [Locale.EXPORT_TITLE, Locale.EXPORT_ARTIST,
		Locale.INFO_COMPOSER, Locale.EXPORT_ALBUM, Locale.EXPORT_YEAR, Locale.INFO_GENRE,
		Locale.INFO_TRACK, Locale.EXPORT_COMMENT];

	/**
		Builds the sheet over a session.

		@param session The session whose piece is described.
	**/
	public function new(session:Session) {
		super();

		this.session = session;

		opaque = true;
		focusable = true;

		for (which in 0...Song.DESCRIPTIONS) {
			final field = new Field("");

			field.onCommit = function(said:String):Void kept();
			field.tipKey = Locale.INFO_TIP;
			fields.push(field);
			add(field);
		}

		keep = new Button("");
		cancel = new Button("");

		add(keep);
		add(cancel);

		keep.onFire = function(button:Button):Void kept();
		cancel.onFire = function(button:Button):Void shut();
	}

	/**
		Reads the piece's descriptions into the fields.
	**/
	public function ask():Void {
		for (which in 0...Song.DESCRIPTIONS) fields[which].set(session.song.described(which));
	}

	/**
		Writes every description that was changed back to the piece, as one step on the undo stack,
		and closes the sheet.
	**/
	public function kept():Void {
		final all = new mdd.song.edit.Together("describe the piece");

		for (which in 0...Song.DESCRIPTIONS) {
			final said = StringTools.trim(fields[which].value);
			if (said != session.song.described(which)) all.also(new mdd.song.edit.DescribeSong(which, said));
		}

		if (all.count() > 0) session.does(all);

		shut();
	}

	function shut():Void {
		if (onShut != null) onShut();
	}

	function rowTall():Float {
		final root = root();
		return root == null ? 40 : root.metrics.whole(40);
	}

	function head():Float {
		final root = root();
		return root == null ? 52 : root.metrics.whole(52);
	}

	override function measure(availableWidth:Float, availableHeight:Float):Void {
		final root = root();
		final metrics = root == null ? null : root.metrics;

		wantWidth = metrics == null ? 520 : metrics.whole(520);
		wantHeight = head() + rowTall() * Song.DESCRIPTIONS
			+ (metrics == null ? 64 : metrics.control + metrics.inset * 2 + metrics.gap);
	}

	override function layout():Void {
		final root = root();
		if (root == null) return;

		final metrics = root.metrics;
		final left = x + metrics.whole(120);
		final tall = rowTall();

		for (which in 0...fields.length) {
			fields[which].arrange(left, y + head() + which * tall + metrics.gap,
				width - metrics.whole(120) - metrics.inset, tall - metrics.gap * 2);
		}

		final wide = metrics.whole(120);
		final bottom = y + height - metrics.inset - metrics.control;

		cancel.arrange(x + width - metrics.inset - wide * 2 - metrics.gap, bottom, wide,
			metrics.control);
		keep.arrange(x + width - metrics.inset - wide, bottom, wide, metrics.control);
	}

	override function took(event:Input):Bool {
		if (super.took(event)) return true;

		switch (event.kind) {
			case Kind.KeyDown:
				if (event.code != Key.Escape) return false;

				shut();
				return true;

			case _:
		}

		return false;
	}

	override function paint(paint:Paint):Void {
		final root = root();
		if (root == null || root.metrics.body == null) return;

		final theme = root.theme;
		final metrics = root.metrics;
		final font = metrics.body;
		final small = metrics.small == null ? font : metrics.small;

		paint.roundedRect(x, y, width, height, metrics.radiusPanel, theme.panel);
		paint.outline(x, y, width, height, theme.frame, metrics.whole(1), 1, metrics.radiusPanel);

		paint.reface(font);
		paint.text(translate(Locale.FILE_INFO), x + metrics.inset, y + metrics.inset + font.ascent,
			theme.ink);

		paint.reface(small);

		final tall = rowTall();

		for (which in 0...fields.length) {
			paint.text(translate(NAMES[which]), x + metrics.inset,
				y + head() + which * tall + (tall - small.height) * 0.5 + small.ascent, theme.dim, 0.9);
		}

		for (field in fields) field.paint(paint);

		keep.label = translate(Locale.INFO_KEEP);
		cancel.label = translate(Locale.EXPORT_CANCEL);

		cancel.paint(paint);
		keep.paint(paint);
	}
}
