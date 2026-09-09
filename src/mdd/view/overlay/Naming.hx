package mdd.view.overlay;

import mdd.app.Locale;
import mdd.ui.Input;
import mdd.ui.Key;
import mdd.ui.Kind;
import mdd.ui.Paint;
import mdd.ui.Theme;
import mdd.ui.Widget;
import mdd.ui.control.Field;

@:unreflective

/**
	The sheet that asks for one line of text: a name for a pattern, a track, a preset
	or its tags.
**/
final class Naming extends Widget {
	/**
		What is typed.
	**/
	public final field:Field;

	/**
		What is being asked for.
	**/
	public var asking(default, null):String = "";

	/**
		Called with what was typed, where it was accepted.
	**/
	public var onName:Null<String -> Void> = null;

	/**
		Called when it closes either way.
	**/
	public var onShut:Null<Void -> Void> = null;

	/**
		Builds an empty sheet.
	**/
	public function new() {
		super();

		opaque = true;
		focusable = true;

		field = new Field("");
		add(field);

		field.onCommit = function(said:String):Void committed(said);
	}

	/**
		Asks for a line, with the whole of what is there already selected so typing
		replaces it.

		@param asking What is being asked for.
		@param value What is there now.
	**/
	public function ask(asking:String, value:String):Void {
		this.asking = asking;

		field.set(value);
	}

	function committed(said:String):Void {
		final held = StringTools.trim(said);
		final what = onName;

		if (held != "" && what != null) what(held);
		if (onShut != null) onShut();
	}

	override function measure(availableWidth:Float, availableHeight:Float):Void {
		final root = root();
		final metrics = root == null ? null : root.metrics;

		wantWidth = metrics == null ? 420 : metrics.whole(420);
		wantHeight = metrics == null ? 150 : metrics.whole(58) + metrics.control
			+ metrics.inset * 2;
	}

	override function layout():Void {
		final root = root();
		if (root == null) return;

		final metrics = root.metrics;
		final top = y + metrics.whole(58);

		field.arrange(x + metrics.inset, top, width - metrics.inset * 2, metrics.control);
	}

	override function took(event:Input):Bool {
		if (super.took(event)) return true;

		switch (event.kind) {
			case Kind.KeyDown:
				if (event.code != Key.Escape) return false;

				if (onShut != null) onShut();
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
		paint.outline(x, y, width, height, theme.frame, metrics.whole(1), 1,
			metrics.radiusPanel);

		paint.reface(font);
		paint.text(asking, x + metrics.inset, y + metrics.inset + font.ascent, theme.ink);

		paint.reface(small);
		paint.text(translate(Locale.NAMING_HINT), x + metrics.inset,
			y + metrics.whole(38) + small.ascent, theme.dim, 0.8);

		field.paint(paint);
	}
}
