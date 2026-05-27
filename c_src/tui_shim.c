/* tui_shim.c — minimal C helpers for tui-fix (Yaynu::Tui).
 *
 * The only feature here is a process-wide integer for the
 * East-Asian-Width "Ambiguous" override. Fix has no IORef in `Std`,
 * so we expose `get`/`set` accessors on a static int. The flag is
 * defaulted to 1 (display ambiguous chars as width 1, matching the
 * UAX #11 default).
 */

static int g_ambiguous_width = 1;

int fix_tui_get_ambiguous_width(void) {
    return g_ambiguous_width;
}

void fix_tui_set_ambiguous_width(int v) {
    if (v <= 1) {
        g_ambiguous_width = 1;
    } else {
        g_ambiguous_width = 2;
    }
}
