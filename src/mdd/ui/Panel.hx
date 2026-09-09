package mdd.ui;

/**
	The band a panel is titled with, drawn the same way everywhere it appears.

	It is drawing and no state, so a widget calls it rather than containing one.
**/
@:unreflective
final class Panel {
	/**
		Draws an empty title band with a hairline under it.

		@param paint What to draw with.
		@param theme The colours to draw in.
		@param metrics The sizes to draw at.
		@param x Where it goes, across.
		@param y Where it goes, down.
		@param width How wide.
		@param tall How tall.
	**/
	public static function band(paint:Paint, theme:Theme, metrics:Metrics, x:Float, y:Float,
			width:Float, tall:Float):Void {
		final hair = metrics.whole(1);

		paint.rect(x, y, width, tall, theme.bar);
		paint.rect(x, y + tall - hair, width, hair, theme.frame, 0.7);
	}

	/**
		Draws a title band with a label in it.

		@param paint What to draw with.
		@param theme The colours to draw in.
		@param metrics The sizes to draw at.
		@param said The title.
		@param x Where it goes, across.
		@param y Where it goes, down.
		@param width How wide.
		@param tall How tall.
	**/
	public static function titled(paint:Paint, theme:Theme, metrics:Metrics, said:String,
			x:Float, y:Float, width:Float, tall:Float):Void {
		band(paint, theme, metrics, x, y, width, tall);

		final font = metrics.small == null ? metrics.body : metrics.small;
		if (font == null) return;

		paint.reface(font);
		paint.text(said, x + metrics.inset, y + (tall - font.height) * 0.5 + font.ascent,
			theme.dim, 0.85);
	}

}
