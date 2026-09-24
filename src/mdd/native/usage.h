#pragma once

/**
 * Begins measuring what this process costs.
 */
extern "C" void mdd_usage_start();

/**
 * Stops measuring and gives back whatever it held.
 */
extern "C" void mdd_usage_stop();

/**
 * @return Processor use as a fraction of one core, or a negative number where it cannot be
 * 	measured.
 */
extern "C" double mdd_usage_cpu();

/**
 * @return Memory held, in megabytes.
 */
extern "C" double mdd_usage_ram();

/**
 * The high water mark rather than what is held now. A phase that allocates and frees
 * inside itself is over by the time anything asks what it cost, so the figure that
 * says whether a machine can run it is this one.
 *
 * @return The most memory held at once since the process started, in megabytes, or a
 *         negative number where it cannot be measured.
 */
extern "C" double mdd_usage_peak();

/**
 * How busy the graphics device is: for this process on Windows and Linux, and for the whole device
 * on macOS, which keeps no figure for one process. Linux works it out between two calls, so the
 * first answers nought.
 *
 * @return Percent, or a negative number where it cannot be measured.
 */
extern "C" double mdd_usage_gpu();

/**
 * Graphics memory this process has to itself, which is what the interface's glyph
 * atlases and render targets sit in. Approximate: the counter is per process and
 * what a driver reports against it is its own business. On macOS it is what the whole
 * device has in use.
 *
 * @return Megabytes held, or a negative number where it cannot be measured.
 */
extern "C" double mdd_usage_vram();
