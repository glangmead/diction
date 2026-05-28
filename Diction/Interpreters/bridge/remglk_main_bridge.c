/* Replaces RemGlk's main() with a function that takes a story file path
 * and runs the interpreter in-process. Compiled into each interpreter's
 * XCFramework alongside RemGlk's other source files (with main.c excluded).
 *
 * The interpreter normally terminates by calling glk_exit(), which in turn
 * calls exit() — fatal for an iOS host process. We rename glk_exit via -D
 * and provide our own implementation that longjmps back to the entry point.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <setjmp.h>

#include "glk.h"
#include "remglk.h"
#include "rgdata.h"
#include "glkstart.h"

/* main.c globals that other RemGlk sources read directly. */
int pref_stderr = 0;
int pref_fixedmetrics = 1;
int pref_autometrics = 0;
int pref_gamefiledir = 0;
int pref_onlyfiledir = 0;
int pref_singleturn = 0;
char *pref_resourceurl = NULL;
#if GIDEBUG_LIBRARY_SUPPORT
int gli_debugger = 0;
#endif

int gli_get_dataresource_info(int num, void **ptr, glui32 *len, int *isbinary)
{
    (void)num;
    if (ptr) *ptr = NULL;
    if (len) *len = 0;
    if (isbinary) *isbinary = 0;
    return 0;
}

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

/* Replacement for glk_exit (renamed via -Dglk_exit=bridge_glk_exit).
 * Instead of exit()ing the process, longjmp back to remglk_setup_and_run. */
static jmp_buf exit_jmp;
static int exit_jmp_set = 0;

void bridge_glk_exit(void) __attribute__((noreturn));
void bridge_glk_exit(void)
{
    if (exit_jmp_set) {
        longjmp(exit_jmp, 1);
    }
    /* Fallback if called before setjmp — shouldn't happen but exit the
     * thread cleanly rather than the whole process. pthread_exit is noreturn
     * in practice but its prototype on Darwin lacks the attribute, so add
     * __builtin_unreachable to silence the noreturn-returns warning. */
    pthread_exit(NULL);
    __builtin_unreachable();
}

int remglk_setup_and_run(const char *story_path, const char *interpreter_name)
{
    fprintf(stderr, "[diction] starting %s for %s\n",
            interpreter_name, story_path);

    if (setjmp(exit_jmp) != 0) {
        fprintf(stderr, "[diction] %s exited via glk_exit\n", interpreter_name);
        exit_jmp_set = 0;
        return 0;
    }
    exit_jmp_set = 1;

    data_supportcaps_t supportcaps;
    glkunix_startup_t startdata;
    char *fake_argv[2];

    data_supportcaps_clear(&supportcaps);

    fake_argv[0] = (char *)interpreter_name;
    fake_argv[1] = (char *)story_path;
    startdata.argc = 2;
    startdata.argv = fake_argv;

    gli_initialize_datainput();
    gli_initialize_misc(&supportcaps);
    gli_initialize_windows();
    gli_initialize_streams();
    gli_initialize_filerefs();
    gli_initialize_events();

    fprintf(stderr, "[diction] calling glkunix_startup_code\n");
    if (!glkunix_startup_code(&startdata)) {
        fprintf(stderr, "[diction] glkunix_startup_code returned false\n");
        bridge_glk_exit();
    }

    {
        data_metrics_t *metrics = data_metrics_alloc(80, 50);
        gli_select_imaginary();
        gli_windows_update_metrics(metrics);
        data_metrics_free(metrics);
    }

    fprintf(stderr, "[diction] entering glk_main\n");
    glk_main();
    fprintf(stderr, "[diction] glk_main returned\n");

    exit_jmp_set = 0;
    return 0;
}
