#ifndef MDD_CONSOLE_H
#define MDD_CONSOLE_H

#ifdef __cplusplus
extern "C" {
#endif

/**
 * Gives a program built without a console one, where one is wanted. It joins the console of
 * whatever started it, which is the terminal where it was started from cmd or PowerShell, and
 * where nothing started it from one it opens a console of its own if asked to. Standard input,
 * output and error are pointed at that console, except where the program was started with them
 * already going to a file or a pipe, which are left where they go.
 *
 * Ctrl+C and Ctrl+Break in that console are ignored, because the terminal hands it back as soon
 * as a windowed program starts and a key meant for the next command would otherwise close this
 * one. Closing the console still closes the program, which is how Windows ends everything
 * attached to one.
 *
 * Nothing happens in a program built with a console, which already has one, or on any other
 * platform.
 *
 * @param open Nonzero to open a console where nothing started this from one.
 * @return Nonzero where there is a console now.
 */
int mdd_console_attach(int open);

#ifdef __cplusplus
}
#endif

#endif
