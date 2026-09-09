package mdd.ui;

/**
	How much motion the interface uses. It follows the desktop setting unless the
	reader overrides it, and `None` is what a check wants so a fade does not have to be
	waited out.
**/
enum abstract Flow(Int) from Int to Int {
	var Full = 0;
	var Reduced = 1;
	var None = 2;
}
