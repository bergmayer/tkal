#ifndef NCURSES_BRIDGE_H
#define NCURSES_BRIDGE_H

#include <ncurses.h>

// Wrapper functions for macros that Swift can't access directly

static inline void bridge_getmaxyx(WINDOW *win, int *y, int *x) {
    *y = getmaxy(win);
    *x = getmaxx(win);
}

static inline int bridge_mvwprintw(WINDOW *win, int y, int x, const char *str) {
    return mvwprintw(win, y, x, "%s", str);
}

static inline int bridge_mvwaddch(WINDOW *win, int y, int x, chtype ch) {
    return mvwaddch(win, y, x, ch);
}

// Attribute constants as inline functions (Swift can't access C macros directly)
static inline int bridge_a_bold(void) { return A_BOLD; }
static inline int bridge_a_normal(void) { return A_NORMAL; }
static inline int bridge_a_dim(void) { return A_DIM; }
static inline int bridge_a_reverse(void) { return A_REVERSE; }
static inline int bridge_a_standout(void) { return A_STANDOUT; }
static inline int bridge_a_underline(void) { return A_UNDERLINE; }

#endif
