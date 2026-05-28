#ifndef INTERP_BRIDGE_H
#define INTERP_BRIDGE_H

#ifdef __cplusplus
extern "C" {
#endif

#define INTERP_EXPORT __attribute__((visibility("default")))

INTERP_EXPORT extern int bocfel_run(const char *story_path);
INTERP_EXPORT extern int glulxe_run(const char *story_path);

#ifdef __cplusplus
}
#endif

#endif
