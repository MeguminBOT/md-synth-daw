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
 * @return Graphics memory held, in megabytes, or a negative number where it cannot be measured.
 */
extern "C" double mdd_usage_gpu();
