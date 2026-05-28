/* Replaces RemGlk's main() with a function that takes a story file path
 * and runs the interpreter in-process. This bridge file is compiled into
 * each interpreter's XCFramework alongside RemGlk's other source files
 * (with main.c excluded).
 *
 * Caller responsibilities:
 *  - Set up stdin/stdout pipes (e.g. via dup2) before invoking the run function
 *  - Read RemGlk JSON from the pipe connected to stdout
 *  - Write RemGlk JSON to the pipe connected to stdin
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "glk.h"
#include "remglk.h"
#include "rgdata.h"
#include "glkstart.h"

/* These globals are required by various RemGlk source files that read them
 * directly. They were defined in main.c. */
int pref_stderr = 0;
int pref_fixedmetrics = 0;
int pref_autometrics = 0;
int pref_gamefiledir = 0;
int pref_onlyfiledir = 0;
int pref_singleturn = 0;
char *pref_resourceurl = NULL;
#if GIDEBUG_LIBRARY_SUPPORT
int gli_debugger = 0;
#endif

/* Required entry point declared in main.c — kept here so dependent code links. */
int gli_get_dataresource_info(int num, void **ptr, glui32 *len, int *isbinary)
{
    (void)num;
    if (ptr) *ptr = NULL;
    if (len) *len = 0;
    if (isbinary) *isbinary = 0;
    return 0;
}

/* Required by interpreters that use glkunix_stream_open_pathname. */
strid_t glkunix_stream_open_pathname_gen(char *pathname, glui32 writemode,
    glui32 textmode, glui32 rock)
{
    return gli_stream_open_pathname(pathname, (writemode != 0), (textmode != 0), rock);
}

strid_t glkunix_stream_open_pathname(char *pathname, glui32 textmode,
    glui32 rock)
{
    return gli_stream_open_pathname(pathname, 0, (textmode != 0), rock);
}

/* The shared entry point. Initializes RemGlk, builds fake argv,
 * invokes glkunix_startup_code (which opens the game file), and runs glk_main.
 */
int remglk_setup_and_run(const char *story_path, const char *interpreter_name)
{
    data_supportcaps_t supportcaps;
    glkunix_startup_t startdata;
    char *fake_argv[2];

    data_supportcaps_clear(&supportcaps);

    /* Build a fake argv: [interpreter_name, story_path]. */
    fake_argv[0] = (char *)interpreter_name;
    fake_argv[1] = (char *)story_path;
    startdata.argc = 2;
    startdata.argv = fake_argv;

    /* Initialize RemGlk subsystems (mirrors RemGlk main.c). */
    gli_initialize_datainput();
    gli_initialize_misc(&supportcaps);
    gli_initialize_windows();
    gli_initialize_streams();
    gli_initialize_filerefs();
    gli_initialize_events();

    if (!glkunix_startup_code(&startdata)) {
        glk_exit();
        return 1;
    }

    /* Set up metrics with defaults — we use fixed metrics since there's no
     * real terminal. The client may send a real Arrange event later. */
    {
        data_metrics_t *metrics = data_metrics_alloc(80, 50);
        data_supportcaps_t newcaps;
        gli_select_metrics(metrics, &newcaps);
        data_supportcaps_merge(&gli_supportcaps, &newcaps);
        gli_windows_update_metrics(metrics);
        data_metrics_free(metrics);
    }

    glk_main();
    glk_exit();
    return 0;
}
