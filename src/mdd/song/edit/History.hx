package mdd.song.edit;

/**
	The undo stack: what has been done, and what has been undone and could be done
	again.

	Doing something new throws away everything ahead of the cursor, which is what makes
	undo a line rather than a tree.
**/
final class History {
	/**
		How many commands to keep. The oldest is forgotten past this.
	**/
	public var limit:Int;

	final done:Array<Command> = [];
	final undone:Array<Command> = [];

	/**
		Builds an empty stack.

		@param limit How many commands to keep before the oldest is forgotten.
	**/
	public function new(limit:Int = 512) {
		this.limit = limit < 1 ? 1 : limit;
	}

	/**
		Applies a command and puts it on the stack, throwing away anything that had been
		undone.

		@param song The song to act on.
		@param command What to do.
		@return The same command, so a caller can keep hold of it.
	**/
	public function does(song:Song, command:Command):Command {
		command.apply(song);
		done.push(command);
		undone.resize(0);

		while (done.length > limit) done.shift();
		return command;
	}

	/**
		Reverts the last command.

		@param song The song to act on.
		@return False where there was nothing to undo.
	**/
	public function undo(song:Song):Bool {
		if (done.length == 0) return false;

		final command = done.pop();
		command.revert(song);
		undone.push(command);
		return true;
	}

	/**
		Applies the last command that was undone.

		@param song The song to act on.
		@return False where there was nothing to redo.
	**/
	public function redo(song:Song):Bool {
		if (undone.length == 0) return false;

		final command = undone.pop();
		command.apply(song);
		done.push(command);
		return true;
	}

	/**
		Forgets everything, which loading a song has to do.
	**/
	public function clear():Void {
		done.resize(0);
		undone.resize(0);
	}

	/**
		@return How many commands could be undone.
	**/
	public inline function depth():Int {
		return done.length;
	}

	/**
		@return How many could be redone.
	**/
	public inline function ahead():Int {
		return undone.length;
	}

	/**
		@return The label of the command that would be undone, or an empty string where there is
			none.
	**/
	public function last():String {
		return done.length == 0 ? "" : done[done.length - 1].label();
	}
}
