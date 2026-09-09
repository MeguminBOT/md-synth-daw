package mdd.ui;

/**
	Which pointer button an event is about.
**/
enum abstract Pointer(Int) from Int to Int {
	var Nothing = 0;
	var Left = 1;
	var Middle = 2;
	var Right = 3;
}
