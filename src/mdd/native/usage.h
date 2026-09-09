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
 * @return Graphics memory held, in megabytes, or a negative number where it cannot be measured.
 */
extern "C" double mdd_usage_gpu();
