package mdd.ui;

enum abstract Flow(Int) from Int to Int {
	var Full = 0;
	var Reduced = 1;
	var None = 2;
}
