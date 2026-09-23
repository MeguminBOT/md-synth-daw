package mdd.view.film;

import haxe.ds.Vector;
import mdd.app.Locale;
import mdd.song.Part;
import mdd.ui.Input;
import mdd.ui.Kind;
import mdd.ui.Metrics;
import mdd.ui.Paint;
import mdd.ui.Pointer;
import mdd.ui.Widget;
import mdd.ui.control.Button;
import mdd.ui.control.Choice;
import mdd.ui.control.Field;
import mdd.ui.control.Menu;
import mdd.ui.control.Number;
import mdd.ui.control.Slider;
import mdd.ui.control.Swatch;
import mdd.ui.control.Toggle;
import mdd.view.monitor.Windowing;

/**
	What a studio's style is set to, down the right of the editor: playback and the saved styles,
	the background, the layers in the order they are drawn, and the chosen layer.

	Every control writes straight into the style and tells the studio, which redraws the preview
	and keeps the change. The controls that belong to a kind of layer other than the chosen one are
	hidden and take no room, so the panel shows only what the chosen layer has.
**/
@:unreflective
final class Styling extends Widget {
	/**
		How many layers the list shows before it scrolls.
	**/
	static inline final SHOWN = 4;

	final studio:Studio;

	final play:Button;
	final stop:Button;
	final styles:Button;

	final plain:Button;
	final gradient:Button;
	final groundFrom:Swatch;
	final groundTo:Swatch;
	final groundTurn:Number;
	final groundPick:Button;
	final groundClear:Button;
	final groundAlpha:Slider;

	final addPicture:Button;
	final addText:Button;
	final raiseLayer:Button;
	final lowerLayer:Button;
	final dropLayer:Button;

	final placeX:Number;
	final placeY:Number;
	final sizeWide:Number;
	final sizeTall:Number;
	final turn:Number;
	final alpha:Slider;

	final colours:Array<Swatch> = [];
	final names:Toggle;
	final grid:Toggle;
	final weight:Number;
	final windowing:Button;
	final smoothing:Button;
	final smoothingWidth:Number;
	final waveform:Button;
	final spectrum:Button;
	final gather:Button;

	final swap:Button;

	final words:Field;
	final font:Button;
	final fill:Swatch;
	final border:Swatch;
	final borderWidth:Number;

	final headings:Vector<Float> = new Vector<Float>(4);
	final labels:Vector<Float> = new Vector<Float>(2);

	var listTop:Float = 0;
	var listOffset:Int = 0;
	var menu:Null<Menu> = null;
	var scrolled:Float = 0;
	var reach:Float = 0;

	/**
		Whether `follows` is writing the style into the controls, while which a control that moves
		is only showing what the style already holds and writes nothing back.
	**/
	var following:Bool = false;

	/**
		Builds the panel for a studio.

		@param studio The studio.
	**/
	public function new(studio:Studio) {
		super();

		this.studio = studio;
		opaque = true;

		play = button(function():Void if (studio.onPlay != null) studio.onPlay());
		stop = button(function():Void if (studio.onStop != null) studio.onStop());
		styles = button(function():Void styled());

		plain = button(function():Void grounds(Style.PLAIN));
		gradient = button(function():Void grounds(Style.GRADIENT));
		groundFrom = swatch(function():Void picks(Locale.FILM_BACKGROUND, studio.style.groundColour,
			function(colour:Int):Void studio.style.groundColour = colour));
		groundTo = swatch(function():Void picks(Locale.FILM_BACKGROUND, studio.style.groundTo,
			function(colour:Int):Void studio.style.groundTo = colour));
		groundTurn = number(0, 359, "°", function(value:Int):Void
			studio.style.groundTurn = value);
		groundPick = button(function():Void if (studio.onPick != null) studio.onPick(Studio.GROUND_PICTURE));
		groundClear = button(function():Void {
			studio.style.groundImage = "";
			studio.changed(true);
		});
		groundAlpha = slider(function(value:Int):Void studio.style.groundAlpha = value / 100);

		addPicture = button(function():Void if (studio.onPick != null) studio.onPick(Studio.LAYER_PICTURE));
		addText = button(function():Void studio.writes("{title}"));
		raiseLayer = button(function():Void studio.reorders(1));
		lowerLayer = button(function():Void studio.reorders(-1));
		dropLayer = button(function():Void studio.removes());

		placeX = number(-400, 500, "%", function(value:Int):Void
			chosenDo(function(layer:Layer):Void layer.x = value / 100));
		placeY = number(-400, 500, "%", function(value:Int):Void
			chosenDo(function(layer:Layer):Void layer.y = value / 100));
		sizeWide = number(2, 400, "%", function(value:Int):Void
			chosenDo(function(layer:Layer):Void layer.wide = value / 100));
		sizeTall = number(2, 400, "%", function(value:Int):Void
			chosenDo(function(layer:Layer):Void layer.tall = value / 100));
		turn = number(0, 359, "°", function(value:Int):Void
			chosenDo(function(layer:Layer):Void layer.turn = value));
		alpha = slider(function(value:Int):Void chosenDo(function(layer:Layer):Void layer.alpha = value / 100));

		for (part in 0...Part.COUNT) {
			final held = swatch(function():Void {
				final own:Part = part;
				picks(Locale.FILM_LANE, studio.style.colours[part] < 0 ? 0xFFFFFF : studio.style.colours[part],
					function(colour:Int):Void studio.style.colours[part] = colour, own.name());
			});

			held.onClear = function(from:Swatch):Void {
				studio.style.colours[part] = -1;
				studio.changed(true);
			};

			colours.push(held);
		}

		names = toggle(function(on:Bool):Void studio.style.names = on);
		grid = toggle(function(on:Bool):Void studio.style.grid = on);
		weight = number(1, 16, "", function(value:Int):Void studio.style.weight = value);
		windowing = button(function():Void shaped(true));
		smoothing = button(function():Void shaped(false));
		smoothingWidth = number(3, Windowing.WIDEST, "", function(value:Int):Void
			studio.style.smoothingWidth = Windowing.spanned(value));

		swap = button(function():Void if (studio.onPick != null) studio.onPick(Studio.SWAP_PICTURE));

		waveform = button(function():Void studio.views(mdd.view.monitor.Scope.WAVEFORM));
		spectrum = button(function():Void studio.views(mdd.view.monitor.Scope.SPECTRUM));
		waveform.toggle = true;
		spectrum.toggle = true;

		gather = button(function():Void studio.gathers());
		gather.tipKey = Locale.FILM_GATHER_TIP;

		words = new Field("");
		words.onChange = function(said:String):Void chosenDo(function(layer:Layer):Void layer.text = said, false);
		words.onCommit = function(said:String):Void studio.changed(true);
		add(words);

		font = button(function():Void faced());
		fill = swatch(function():Void {
			final layer = studio.chosenLayer();
			if (layer != null) picks(Locale.FILM_FILL, layer.colour, function(colour:Int):Void layer.colour = colour);
		});
		border = swatch(function():Void {
			final layer = studio.chosenLayer();
			if (layer != null) picks(Locale.FILM_BORDER, layer.border, function(colour:Int):Void layer.border = colour);
		});
		borderWidth = number(0, 25, "%", function(value:Int):Void
			chosenDo(function(layer:Layer):Void layer.borderWidth = value / 100));

		plain.toggle = true;
		gradient.toggle = true;
		names.tipKey = Locale.FILM_NAMES_TIP;
		grid.tipKey = Locale.FILM_GRID_TIP;
		windowing.tipKey = Locale.FILM_WINDOWING_TIP;
		smoothing.tipKey = Locale.FILM_SMOOTHING_TIP;
		words.detailKey = Locale.FILM_WORDS_TIP;
		borderWidth.tipKey = Locale.FILM_BORDER_TIP;
		alpha.tipKey = Locale.FILM_OPACITY;
		groundAlpha.tipKey = Locale.FILM_OPACITY;

		follows();
	}

	/**
		Reads the style and the chosen layer back into every control, and shows the ones the
		chosen layer has.
	**/
	public function follows():Void {
		final style = studio.style;
		final layer = studio.chosenLayer();
		final kind = layer == null ? -1 : layer.kind;
		final laned = kind == Layer.LANES || kind == Layer.LANE;

		following = true;

		plain.on = style.ground == Style.PLAIN;
		gradient.on = style.ground == Style.GRADIENT;
		groundFrom.colour = style.groundColour;
		groundTo.colour = style.groundTo;
		groundTurn.set(Math.round(style.groundTurn));
		groundAlpha.set(Math.round(style.groundAlpha * 100));

		groundTo.visible = style.ground == Style.GRADIENT;
		groundTurn.visible = style.ground == Style.GRADIENT;
		groundClear.visible = style.groundImage != "";
		groundAlpha.visible = style.groundImage != "";

		for (control in [placeX, placeY, sizeWide, sizeTall, turn]) control.visible = layer != null;
		alpha.visible = layer != null;
		sizeWide.visible = layer != null && kind != Layer.TEXT;

		if (layer != null) {
			placeX.set(Math.round(layer.x * 100));
			placeY.set(Math.round(layer.y * 100));
			sizeWide.set(Math.round(layer.wide * 100));
			sizeTall.set(Math.round(layer.tall * 100));
			turn.set(Math.round((layer.turn % 360 + 360) % 360));
			alpha.set(Math.round(layer.alpha * 100));
		}

		for (part in 0...Part.COUNT) {
			final held = colours[part];
			final own:Part = part;

			held.visible = laned;
			held.borrowed = style.colours[part] < 0;
			held.colour = style.colours[part] < 0 ? partColour(part) : style.colours[part];
			held.tip = own.name();
			held.detailKey = Locale.FILM_LANE_TIP;
		}

		for (control in [names, grid]) control.visible = laned;
		for (control in [weight, smoothingWidth]) control.visible = laned;

		windowing.visible = laned;
		smoothing.visible = laned;
		waveform.visible = laned;
		spectrum.visible = laned;
		waveform.on = studio.scope.showing == mdd.view.monitor.Scope.WAVEFORM;
		spectrum.on = studio.scope.showing == mdd.view.monitor.Scope.SPECTRUM;
		smoothingWidth.visible = laned && style.smoothing != Windowing.NONE;

		names.set(style.names);
		grid.set(style.grid);
		weight.set(Math.round(style.weight));
		smoothingWidth.set(style.smoothingWidth);

		swap.visible = kind == Layer.IMAGE;

		var alone = false;
		for (held in style.layers) if (held.kind == Layer.LANE) alone = true;

		gather.visible = kind == Layer.LANES && alone;

		words.visible = kind == Layer.TEXT;
		font.visible = kind == Layer.TEXT;
		fill.visible = kind == Layer.TEXT;
		border.visible = kind == Layer.TEXT;
		borderWidth.visible = kind == Layer.TEXT;

		if (layer != null && kind == Layer.TEXT) {
			if (words.value != layer.text) words.set(layer.text);

			fill.colour = layer.colour;
			border.colour = layer.border;
			borderWidth.set(Math.round(layer.borderWidth * 100));
		}

		if (layer != null) {
			final row = style.layers.length - 1 - studio.chosen;

			if (row < listOffset) listOffset = row;
			if (row >= listOffset + SHOWN) listOffset = row - SHOWN + 1;
		}

		raiseLayer.enabled = layer != null && studio.chosen < style.layers.length - 1;
		lowerLayer.enabled = layer != null && studio.chosen > 0;
		dropLayer.enabled = layer != null && kind != Layer.LANES;

		following = false;

		labelled();
		relayout();
		invalidate();
	}

	/**
		Puts the words on every control, which changing the language needs as well as a change of
		layer.
	**/
	function labelled():Void {
		final root = root();
		if (root == null) return;

		final style = studio.style;
		final layer = studio.chosenLayer();

		play.label = root.translate(Locale.FILM_PLAY);
		stop.label = root.translate(Locale.FILM_STOP);
		styles.label = root.translate(Locale.FILM_STYLES);
		plain.label = root.translate(Locale.FILM_COLOUR);
		gradient.label = root.translate(Locale.FILM_GRADIENT);
		groundPick.label = root.translate(style.groundImage == "" ? Locale.FILM_PICTURE_ADD : Locale.FILM_PICTURE_SWAP);
		groundClear.label = root.translate(Locale.FILM_CLEAR);
		addPicture.label = root.translate(Locale.FILM_ADD_PICTURE);
		addText.label = root.translate(Locale.FILM_ADD_TEXT);
		raiseLayer.label = root.translate(Locale.FILM_RAISE);
		lowerLayer.label = root.translate(Locale.FILM_LOWER);
		dropLayer.label = root.translate(Locale.FILM_REMOVE);
		swap.label = root.translate(Locale.FILM_PICTURE_SWAP);

		names.label = root.translate(Locale.FILM_NAMES);
		grid.label = root.translate(Locale.FILM_GRID);
		waveform.label = root.translate(Locale.SCOPE_WAVEFORM);
		spectrum.label = root.translate(Locale.SCOPE_SPECTRUM);
		gather.label = root.translate(Locale.FILM_GATHER);

		placeX.label = root.translate(Locale.FILM_ACROSS);
		placeY.label = root.translate(Locale.FILM_DOWN);
		sizeWide.label = root.translate(Locale.FILM_WIDE);
		sizeTall.label = root.translate(layer != null && layer.kind == Layer.TEXT ? Locale.FILM_SIZE
			: Locale.FILM_TALL);
		turn.label = root.translate(Locale.FILM_TURN);
		groundTurn.label = root.translate(Locale.FILM_ANGLE);
		weight.label = root.translate(Locale.FILM_WEIGHT);
		smoothingWidth.label = root.translate(Locale.FILM_SPAN);
		borderWidth.label = root.translate(Locale.FILM_BORDER_WIDTH);

		windowing.label = root.translate(Locale.FILM_WINDOWING) + ": "
			+ root.translate(Windowing.NAMES[style.windowing]);
		smoothing.label = root.translate(Locale.FILM_SMOOTHING) + ": "
			+ root.translate(Windowing.NAMES[style.smoothing]);

		final faced = layer == null || layer.font == "" ? root.translate(Locale.FILM_FACE_OWN)
			: faceName(layer.font);
		font.label = root.translate(Locale.FILM_FONT) + ": " + faced;

		words.hint = root.translate(Locale.FILM_WORDS);
	}

	/**
		@return A font file's name as the system names it, or the file's own name where it is not
			among the installed fonts read so far.
	**/
	function faceName(path:String):String {
		final held = studio.installed;

		if (held != null) {
			final at = held.paths.indexOf(path);
			if (at >= 0) return held.names[at];
		}

		return haxe.io.Path.withoutExtension(haxe.io.Path.withoutDirectory(path));
	}

	function partColour(part:Int):Int {
		final root = root();
		return root == null ? 0xFFFFFF : root.theme.part(part);
	}

	/**
		Changes the chosen layer and tells the studio.

		@param what What to do to it.
		@param settles Whether the change has settled.
	**/
	function chosenDo(what:Layer -> Void, settles:Bool = true):Void {
		final layer = studio.chosenLayer();
		if (layer == null) return;

		what(layer);
		layer.tidied();
		studio.changed(settles);
	}

	function grounds(kind:Int):Void {
		studio.style.ground = kind;
		studio.changed(true);
	}

	/**
		Raises the colour picker over the editor, open on a colour, writing each step of it back.

		@param named What is being coloured.
		@param colour The colour it opens on.
		@param sets What to do with each colour picked.
		@param extra Words to add to the title, or an empty string.
	**/
	function picks(named:Locale, colour:Int, sets:Int -> Void, extra:String = ""):Void {
		final root = root();
		if (root == null) return;

		final picker = studio.picker;

		picker.title = root.translate(named) + (extra == "" ? "" : "  " + extra);
		picker.beginsAt(colour);

		picker.onChange = function(next:Int):Void {
			sets(next);
			studio.changed(false);
			follows();
		};

		picker.onShut = function():Void studio.changed(true);

		root.raise(picker);
	}

	/**
		Opens the saved styles: saving the style under a name, the ones saved to load, one to
		delete, and the plain style to start again from.
	**/
	function styled():Void {
		final root = root();
		if (root == null) return;

		final held = new Menu();
		final saved = studio.onStyles == null ? [] : studio.onStyles();

		fires(held.offer(new Choice(root.translate(Locale.FILM_SAVE_AS))), function():Void named());
		held.divide();

		if (saved.length == 0) {
			final none = held.offer(new Choice(root.translate(Locale.FILM_NONE_SAVED)));
			none.enabled = false;
		}

		for (name in saved) {
			fires(held.offer(new Choice(name)), function():Void if (studio.onLoad != null) studio.onLoad(name));
		}

		if (saved.length > 0) {
			final deleting = new Menu();

			for (name in saved) {
				fires(deleting.offer(new Choice(name)), function():Void
					if (studio.onDelete != null) studio.onDelete(name));
			}

			held.offer(new Choice(root.translate(Locale.FILM_DELETE))).submenu = deleting;
		}

		held.divide();
		fires(held.offer(new Choice(root.translate(Locale.FILM_PLAIN))), function():Void
			studio.restyles(Style.plain()));

		menu = held;
		root.pop(held, styles.x, styles.y + styles.height, this);
	}

	/**
		Asks for the name to save the style under.
	**/
	function named():Void {
		final root = root();
		if (root == null) return;

		final asking = new mdd.view.overlay.Naming();

		asking.ask(root.translate(Locale.FILM_STYLE_NAME), studio.style.name);
		asking.onName = function(said:String):Void {
			studio.style.name = said;
			if (studio.onSave != null) studio.onSave(said);
		};
		asking.onShut = function():Void root.lower();

		root.raise(asking);
	}

	/**
		Opens the shapes a spectrum is weighed by, or a waveform smoothed with.

		@param spectrum Whether it is the spectrum's window rather than the waveform's smoothing.
	**/
	function shaped(spectrum:Bool):Void {
		final root = root();
		if (root == null) return;

		final held = new Menu();
		final style = studio.style;

		for (kind in 0...Windowing.KINDS) {
			final choice = held.offer(new Choice(root.translate(Windowing.NAMES[kind])));
			if ((spectrum ? style.windowing : style.smoothing) == kind) choice.shortcut = "•";

			fires(choice, function():Void {
				if (spectrum) style.windowing = kind;
				else style.smoothing = kind;

				studio.changed(true);
			});
		}

		final from = spectrum ? windowing : smoothing;

		menu = held;
		root.pop(held, from.x, from.y + from.height, this);
	}

	/**
		Opens the fonts installed on this machine, the interface's own first.
	**/
	function faced():Void {
		final root = root();
		final layer = studio.chosenLayer();
		if (root == null || layer == null) return;

		final held = new Menu();
		final installed = studio.fonts();

		fires(held.offer(new Choice(root.translate(Locale.FILM_FACE_OWN))), function():Void {
			layer.font = "";
			studio.changed(true);
		});

		if (installed.names.length > 0) held.divide();

		for (index in 0...installed.names.length) {
			final path = installed.paths[index];
			final choice = held.offer(new Choice(installed.names[index]));

			if (layer.font == path) choice.shortcut = "•";

			fires(choice, function():Void {
				layer.font = path;
				studio.changed(true);
			});
		}

		menu = held;
		root.pop(held, font.x, font.y + font.height, this);
	}

	override function took(event:Input):Bool {
		switch (event.kind) {
			case Kind.PointerDown:
				if (event.button != Pointer.Left) return false;

				final at = rowAt(event.y);
				if (at < 0) return false;

				studio.chooses(at);
				return true;

			case Kind.Wheel:
				if (event.y >= listTop && event.y <= listTop + rowTall() * SHOWN
						&& studio.style.layers.length > SHOWN) {
					final most = studio.style.layers.length - SHOWN;
					listOffset -= Std.int(event.dy);
					if (listOffset > most) listOffset = most;
					if (listOffset < 0) listOffset = 0;

					invalidate();
					return true;
				}

				final most = reach - height;
				if (most <= 0) return false;

				scrolled -= event.dy * rowTall() * 2;
				if (scrolled > most) scrolled = most;
				if (scrolled < 0) scrolled = 0;

				relayout();
				invalidate();
				return true;

			case _:
		}

		return false;
	}

	/**
		@param py A point, down.
		@return Which layer's row of the list is there, by index into the style's layers, or -1.
	**/
	function rowAt(py:Float):Int {
		if (py < listTop) return -1;

		final row = Std.int((py - listTop) / rowTall());
		if (row >= SHOWN) return -1;

		final shown = order(row + listOffset);
		return shown < 0 ? -1 : shown;
	}

	/**
		@param row A row of the list, counted from the top.
		@return Which layer it shows: the list runs from the uppermost down, so the top row is the
			last layer drawn. -1 past the last.
	**/
	function order(row:Int):Int {
		final many = studio.style.layers.length;
		return row < 0 || row >= many ? -1 : many - 1 - row;
	}

	function rowTall():Float {
		final root = root();
		return root == null ? 24 : root.metrics.whole(24);
	}

	override function layout():Void {
		final root = root();
		if (root == null) return;

		final metrics = root.metrics;
		final pad = metrics.inset;
		final gap = metrics.gap;
		final control = metrics.control;
		final heading = metrics.whole(26);
		final left = x + pad;
		final wide = width - pad * 2;
		final half = (wide - gap) * 0.5;
		final third = (wide - gap * 2) / 3;

		var top = y + pad - scrolled;

		play.arrange(left, top, third, control);
		stop.arrange(left + third + gap, top, third, control);
		styles.arrange(left + (third + gap) * 2, top, third, control);
		top += control + gap * 2;

		headings[0] = top;
		top += heading;

		plain.arrange(left, top, half, control);
		gradient.arrange(left + half + gap, top, half, control);
		top += control + gap;

		final swatchSide = control;

		groundFrom.arrange(left, top, swatchSide, control);
		groundTo.arrange(left + swatchSide + gap, top, swatchSide, control);
		groundTurn.arrange(left + (swatchSide + gap) * 2, top, wide - (swatchSide + gap) * 2, control);
		top += control + gap;

		groundPick.arrange(left, top, groundClear.visible ? half : wide, control);
		groundClear.arrange(left + half + gap, top, half, control);
		top += control + gap;

		labels[0] = top;

		if (groundAlpha.visible) {
			groundAlpha.arrange(left + wide * 0.35, top, wide * 0.65, control);
			top += control + gap;
		}

		headings[1] = top + gap;
		top += heading + gap;

		listTop = top;
		top += rowTall() * SHOWN + gap;

		final fifth = (wide - gap * 4) / 5;

		addPicture.arrange(left, top, fifth * 2 + gap, control);
		addText.arrange(left + (fifth + gap) * 2, top, fifth, control);
		lowerLayer.arrange(left + (fifth + gap) * 3, top, fifth, control);
		raiseLayer.arrange(left + (fifth + gap) * 4, top, fifth, control);
		top += control + gap;

		dropLayer.arrange(left, top, wide, control);
		top += control + gap;

		headings[2] = top + gap;
		top += heading + gap;

		placeX.arrange(left, top, half, control);
		placeY.arrange(left + half + gap, top, half, control);
		top += control + gap;

		if (sizeWide.visible) {
			sizeWide.arrange(left, top, half, control);
			sizeTall.arrange(left + half + gap, top, half, control);
		} else {
			sizeTall.arrange(left, top, half, control);
		}

		top += control + gap;

		turn.arrange(left, top, half, control);
		alpha.arrange(left + half + gap, top, half, control);
		labels[1] = top;
		top += control + gap * 2;

		if (gather.visible) {
			gather.arrange(left, top, wide, control);
			top += control + gap;
		}

		final little = (wide - gap * (Part.COUNT - 1)) / Part.COUNT;

		for (part in 0...Part.COUNT) colours[part].arrange(left + part * (little + gap), top, little, little);

		if (colours[0].visible) top += little + gap * 2;

		if (names.visible) {
			waveform.arrange(left, top, half, control);
			spectrum.arrange(left + half + gap, top, half, control);
			top += control + gap;

			names.arrange(left, top, half, control);
			grid.arrange(left + half + gap, top, half, control);
			top += control + gap;

			windowing.arrange(left, top, wide, control);
			top += control + gap;

			smoothing.arrange(left, top, wide, control);
			top += control + gap;

			weight.arrange(left, top, half, control);
			smoothingWidth.arrange(left + half + gap, top, half, control);
			top += control + gap;
		}

		swap.arrange(left, top, wide, control);

		words.arrange(left, top, wide, control);
		top += control + gap;

		font.arrange(left, top, wide, control);
		top += control + gap;

		fill.arrange(left, top, swatchSide, control);
		border.arrange(left + swatchSide + gap, top, swatchSide, control);
		borderWidth.arrange(left + (swatchSide + gap) * 2, top, wide - (swatchSide + gap) * 2, control);

		var lowest = listTop + rowTall() * SHOWN;

		for (child in children) {
			if (child.visible && child.y + child.height > lowest) lowest = child.y + child.height;
		}

		reach = lowest + pad + scrolled - y;

		if (scrolled > 0 && reach - height < scrolled) {
			scrolled = reach - height < 0 ? 0 : reach - height;
		}

		headings[3] = 0;
	}

	override function paint(paint:Paint):Void {
		final root = root();
		if (root == null || root.metrics.body == null) return;

		final theme = root.theme;
		final metrics = root.metrics;
		final font = metrics.small == null ? metrics.body : metrics.small;
		final left = x + metrics.inset;
		final layer = studio.chosenLayer();

		paint.rect(x, y, width, height, theme.panel);
		paint.rect(x, y, metrics.whole(1), height, theme.frame, 0.7);

		paint.pushClip(x, y, width, height);
		paint.reface(font);

		titled(paint, font, translate(Locale.FILM_BACKGROUND), left, headings[0]);
		titled(paint, font, translate(Locale.FILM_LAYERS), left, headings[1]);

		if (layer != null) {
			titled(paint, font, kindName(layer), left, headings[2]);
		}

		if (groundAlpha.visible) {
			paint.text(translate(Locale.FILM_OPACITY), left, labels[0] + (metrics.control - font.height) * 0.5
				+ font.ascent, theme.dim, 0.9);
		}

		listed(paint, metrics, font);
		super.paint(paint);
		paint.popClip();
	}

	function titled(paint:Paint, font:mdd.ui.Font, said:String, left:Float, top:Float):Void {
		final root = root();
		if (root == null) return;

		paint.text(said, left, top + font.ascent, root.theme.ink, 0.95);
	}

	function kindName(layer:Layer):String {
		if (layer.kind == Layer.LANE) return partName(layer.part);

		return translate(switch (layer.kind) {
			case Layer.LANES: Locale.FILM_LANES;
			case Layer.TEXT: Locale.FILM_TEXT;
			case _: Locale.FILM_PICTURE;
		});
	}

	static function partName(part:Int):String {
		final held:Part = part;
		return held.name();
	}

	/**
		Draws the layers, uppermost first, the chosen one lit.
	**/
	function listed(paint:Paint, metrics:Metrics, font:mdd.ui.Font):Void {
		final root = root();
		if (root == null) return;

		final theme = root.theme;
		final tall = rowTall();
		final left = x + metrics.inset;
		final wide = width - metrics.inset * 2;

		paint.roundedRect(left, listTop, wide, tall * SHOWN, metrics.radiusSmall, theme.sink);

		for (row in 0...SHOWN) {
			final index = order(row + listOffset);
			if (index < 0) break;

			final layer = studio.style.layers[index];
			final top = listTop + row * tall;

			if (index == studio.chosen) paint.rect(left, top, wide, tall, theme.accent, 0.35);

			final said = switch (layer.kind) {
				case Layer.LANES: translate(Locale.FILM_LANES);
				case Layer.LANE: partName(layer.part);
				case Layer.TEXT: translate(Locale.FILM_TEXT) + "  " + layer.text;
				case _: translate(Locale.FILM_PICTURE) + "  " + haxe.io.Path.withoutDirectory(layer.path);
			};

			paint.pushClip(left, top, wide, tall);
			paint.text(said, left + metrics.gap, top + (tall - font.height) * 0.5 + font.ascent,
				index == studio.chosen ? theme.ink : theme.dim);
			paint.popClip();
		}
	}

	/**
		@return A button that does something, added to the panel.
	**/
	function button(what:Void -> Void):Button {
		final out = new Button("");
		out.onFire = function(from:Button):Void what();
		add(out);
		return out;
	}

	/**
		@return A swatch that does something when clicked, added to the panel.
	**/
	function swatch(what:Void -> Void):Swatch {
		final out = new Swatch(0);
		out.onFire = function(from:Swatch):Void what();
		add(out);
		return out;
	}

	/**
		@param least The least it goes to.
		@param most The most.
		@param unit What is written after the value.
		@param sets What to do with each value.
		@return A number that writes into the style and settles, added to the panel.
	**/
	function number(least:Int, most:Int, unit:String, sets:Int -> Void):Number {
		final out = new Number("", least, least, most);
		out.unit = unit;
		out.onChange = function(from:Number):Void {
			if (following) return;

			sets(from.value);
			studio.changed(true);
		};
		add(out);
		return out;
	}

	/**
		@return A slider from nought to a hundred that writes into the style, added to the panel.
	**/
	function slider(sets:Int -> Void):Slider {
		final out = new Slider(100, 0, 100);
		out.onChange = function(from:Slider):Void {
			if (following) return;

			sets(from.value);
			studio.changed(true);
		};
		add(out);
		return out;
	}

	/**
		@param sets What to do with each state.
		@return A checkbox that writes into the style, added to the panel.
	**/
	function toggle(sets:Bool -> Void):Toggle {
		final out = new Toggle("");
		out.onChange = function(from:Toggle):Void {
			if (following) return;

			sets(from.on);
			studio.changed(true);
		};
		add(out);
		return out;
	}
}
