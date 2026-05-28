/* Bocfel bridge: exposes bocfel_run(). */

extern "C" {
#include "interp_bridge.h"

extern int remglk_setup_and_run(const char *story_path, const char *interpreter_name);
}

extern "C" INTERP_EXPORT int bocfel_run(const char *story_path)
{
    return remglk_setup_and_run(story_path, "bocfel");
}
