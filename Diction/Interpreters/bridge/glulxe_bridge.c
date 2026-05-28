/* Glulxe bridge: exposes glulxe_run(). */

#include "interp_bridge.h"

extern int remglk_setup_and_run(const char *story_path, const char *interpreter_name);

INTERP_EXPORT int glulxe_run(const char *story_path)
{
    return remglk_setup_and_run(story_path, "glulxe");
}
