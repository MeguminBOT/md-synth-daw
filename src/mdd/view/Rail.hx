package mdd.view;

import mdd.app.Session;
import mdd.ui.Paint;
import mdd.ui.Widget;
import mdd.view.editor.ChannelRack;
import mdd.view.monitor.Hardware;

/**
	The rail down the left: the channel rack, with the hardware meter under it.
**/
@:unreflective
final class Rail extends Widget {
	/**
		The session both panels read.
	**/
	public final session:Session;

	/**
		The channel rack.
	**/
	public final rack:ChannelRack;

	/**
		The hardware meter.
	**/
	public final hardware:Hardware;

	/**
		Builds the rail and both panels in it.

		@param session The session to read.
	**/
	public function new(session:Session) {
		super();
		this.session = session;

		rack = new ChannelRack(session);
		hardware = new Hardware(session);

		add(rack);
		add(hardware);
	}

	/**
		Gives the meter what it asks for at the bottom and the rack the rest.
	**/
	override function layout():Void {
		final below = hardware.tall();
		final room = height - below;

		rack.arrange(x, y, width, room < 0 ? 0 : room);
		hardware.arrange(x, y + (room < 0 ? 0 : room), width, below);
	}

	/**
		Draws both panels.

		@param paint What to draw with.
	**/
	override function paint(paint:Paint):Void {
		rack.paint(paint);
		hardware.paint(paint);
	}
}
