package mdd.ui;

@:unreflective
final class Panel {
	public static function band(paint:Paint, theme:Theme, metrics:Metrics, x:Float, y:Float,
			width:Float, tall:Float):Void {
		final hair = metrics.whole(1);

		paint.rect(x, y, width, tall, theme.bar);
		paint.rect(x, y + tall - hair, width, hair, theme.frame, 0.7);
	}

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
