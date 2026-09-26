package mdd.view.overlay;

import mdd.app.Locale;
import mdd.ui.Input;
import mdd.ui.Key;
import mdd.ui.Kind;
import mdd.ui.Metrics;
import mdd.ui.Motion;
import mdd.ui.Paint;
import mdd.ui.Theme;
import mdd.ui.Widget;

@:unreflective

/**
	The about sheet: what this is, what it was built with, and what it ships that it
	did not write.
**/
final class About extends Widget {
	static final SOURCES:Array<String> = ["SDL3", "miniaudio", "stb_truetype", "libogg",
		"libvorbis", "libopus", "libvpx", "libwebm"];

	static final LICENCES:Array<String> = ["zlib", "MIT-0", "public domain", "BSD-3", "BSD-3",
		"BSD-3", "BSD-3", "BSD-3"];

	static final ADDRESS:String = "github.com/" + mdd.Config.GITHUB;

	/**
		Called when it closes.
	**/
	public var onShut:Null<Void -> Void> = null;

	/**
		How far it has risen into place.
	**/
	public final rise:Motion;

	/**
		How far it has faded in.
	**/
	public final fade:Motion;

	/**
		Builds the sheet.
	**/
	public function new() {
		super();
		modal = true;

		opaque = true;
		focusable = true;

		rise = new Motion(this, 0, true);
		fade = new Motion(this, 0, false);
	}

	/**
		Starts the fade and the rise.
	**/
	public function arrive():Void {
		final root = root();
		if (root == null) return;

		rise.hold(0);
		fade.hold(0);

		root.start(rise, 1, Motion.ENTER);
		root.start(fade, 1, Motion.ENTER);
	}

	/**
		@return How tall the title band is.
	**/
	public function head():Float {
		final root = root();
		return root == null ? 58 : root.metrics.whole(58);
	}

	/**
		@return How tall one row is.
	**/
	public function rowTall():Float {
		final root = root();
		return root == null ? 20 : root.metrics.whole(20);
	}

	override function measure(availableWidth:Float, availableHeight:Float):Void {
		final root = root();
		final metrics = root == null ? null : root.metrics;

		wantWidth = metrics == null ? 420 : metrics.whole(420);
		wantHeight = metrics == null ? 320
			: head() + rowTall() * (SOURCES.length + 4) + metrics.inset * 2;
	}

	override function took(event:Input):Bool {
		if (event.kind == Kind.KeyDown && event.code == Key.Escape) {
			if (onShut != null) onShut();
			return true;
		}

		if (event.kind == Kind.PointerDown && onShut != null) onShut();
		return true;
	}

	override function paint(paint:Paint):Void {
		final root = root();
		if (root == null || root.metrics.body == null) return;

		final theme = root.theme;
		final metrics = root.metrics;
		final alpha = fade.value;

		if (alpha <= 0.004) return;

		final lift = (1 - rise.value) * metrics.sizeOf(8);
		paint.pushTransform(0, lift);

		paint.roundedRect(x, y, width, height, metrics.radiusPanel, theme.raise1, alpha);
		paint.outline(x, y, width, height, theme.frame, metrics.whole(1), alpha,
			metrics.radiusPanel);

		final font = metrics.large == null ? metrics.body : metrics.large;
		final small = metrics.small == null ? metrics.body : metrics.small;

		paint.reface(font);
		paint.text(mdd.Config.TITLE, x + metrics.inset, y + metrics.inset + font.ascent,
			theme.ink, alpha);

		paint.reface(small);
		paint.text(mdd.Config.VERSION, x + metrics.inset,
			y + metrics.inset + font.height + small.ascent, theme.dim, alpha * 0.8);

		paint.textRight(translate(Locale.PREFERENCES_CLOSE), x + width - metrics.inset,
			y + metrics.inset + small.ascent, theme.dim, alpha * 0.7);

		var top = y + head();
		final tall = rowTall();

		paint.text(translate(Locale.ABOUT_BUILT), x + metrics.inset, top + small.ascent,
			theme.dim, alpha * 0.9);

		top += tall * 1.5;

		for (index in 0...SOURCES.length) {
			paint.text(SOURCES[index], x + metrics.inset, top + small.ascent, theme.ink,
				alpha * 0.85);

			paint.textRight(LICENCES[index], x + width - metrics.inset, top + small.ascent,
				theme.dim, alpha * 0.7);

			top += tall;
		}

		top += tall * 0.5;

		paint.text(ADDRESS, x + metrics.inset, top + small.ascent,

			theme.accent, alpha * 0.9);

		paint.popTransform();
	}
}
