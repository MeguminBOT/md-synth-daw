package mdd.song.edit;

final class History {
	public var limit:Int;

	final done:Array<Command> = [];
	final undone:Array<Command> = [];

	public function new(limit:Int = 512) {
		this.limit = limit < 1 ? 1 : limit;
	}

	public function does(song:Song, command:Command):Command {
		command.apply(song);
		done.push(command);
		undone.resize(0);

		while (done.length > limit) done.shift();
		return command;
	}

	public function undo(song:Song):Bool {
		if (done.length == 0) return false;

		final command = done.pop();
		command.revert(song);
		undone.push(command);
		return true;
	}

	public function redo(song:Song):Bool {
		if (undone.length == 0) return false;

		final command = undone.pop();
		command.apply(song);
		done.push(command);
		return true;
	}

	public function clear():Void {
		done.resize(0);
		undone.resize(0);
	}

	public inline function depth():Int {
		return done.length;
	}

	public inline function ahead():Int {
		return undone.length;
	}

	public function last():String {
		return done.length == 0 ? "" : done[done.length - 1].label();
	}
}
