package mdd.gate;

@:unreflective

/**
	Tells whether a stretch of code allocated anything on the thread running it.

	`cpp.vm.Gc.memInfo` counts the heap blocks a thread takes, and a generational build puts every
	small object in the thread's nursery first, so a stretch allocating ten megabytes of small
	objects moved it by twenty one kilobytes and one allocating a few hundred did not move it at
	all. The thread's own allocator is exact: every small object moves its nursery pointer, and
	every large one adds to what the collector holds as large. With the collector off, nothing else
	moves either, so a stretch that moved neither allocated nothing.
**/
class Allocations {
	final nursery:Float;
	final large:Float;

	function new() {
		nursery = nurseryAt();
		large = cpp.vm.Gc.memInfo(cpp.vm.Gc.MEM_INFO_LARGE);
	}

	/**
		Starts a measurement on the calling thread. The collector should be off until it is read.

		@return The measurement.
	**/
	public static function begin():Allocations {
		return new Allocations();
	}

	/**
		@return Roughly how many bytes the thread has allocated since `begin`, and nought exactly
			when it has allocated nothing. A nursery that filled and was replaced counts as however
			far its pointer moved, which is still not nought.
	**/
	public function since():Float {
		final moved = nurseryAt() - nursery;
		final grown = cpp.vm.Gc.memInfo(cpp.vm.Gc.MEM_INFO_LARGE) - large;

		return (moved < 0 ? -moved : moved) + (grown < 0 ? -grown : grown);
	}

	/**
		@return Where the calling thread's nursery is up to.
	**/
	static inline function nurseryAt():Float {
		return untyped __cpp__("(double)(size_t)(HX_CTX_GET)->spaceFirst");
	}
}
