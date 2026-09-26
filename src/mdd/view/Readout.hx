package mdd.view;

@:unreflective

/**
	What one parameter's value reads as, made again only when the parameter or the value changes, so
	a lane drawing its scale and its value on every frame allocates nothing for them. A lane keeps
	one for each place it writes a value.
**/
final class Readout {
	var held:Null<Parameter> = null;
	var value:Int = 0;
	var text:String = "";

	/**
		Builds an empty readout.
	**/
	public function new() {}

	/**
		@param held The parameter.
		@param value A value of it.
		@return What `held.said` makes of the value.
	**/
	public function of(held:Parameter, value:Int):String {
		if (held != this.held || value != this.value) {
			this.held = held;
			this.value = value;
			text = held.said(value);
		}

		return text;
	}
}
