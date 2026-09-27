#pragma once

/**
 * Writes what this machine offers the interface to a file, one fact a line, a name and then what
 * it has: every renderer the application offers with the level it reaches, `0` where it cannot be
 * made at all, and the graphics memory the card can use. The Windows installer runs the
 * application with `--requirements` to have this written before it installs anything.
 *
 * Starts SDL and shuts it down again, so it is called instead of the application rather than
 * inside it.
 *
 * @param path Where to write, in UTF-8.
 * @return Nought where the file was written, and one where it could not be opened.
 */
extern "C" int mdd_requirements_write(const char *path);
