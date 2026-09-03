package mdd.view;

import mdd.app.Session;
import mdd.ui.Paint;
import mdd.ui.Widget;

@:unreflective
final class Rail extends Widget {
	public final session:Session;

	public final rack:ChannelRack;
	public final hardware:Hardware;

	public function new(session:Session) {
		super();
		this.session = session;

		rack = new ChannelRack(session);
		hardware = new Hardware(session);

		add(rack);
		add(hardware);
	}

	override function layout():Void {
		final below = hardware.tall();
		final room = height - below;

		rack.arrange(x, y, width, room < 0 ? 0 : room);
		hardware.arrange(x, y + (room < 0 ? 0 : room), width, below);
	}

	override function paint(paint:Paint):Void {
		rack.paint(paint);
		hardware.paint(paint);
	}
}
