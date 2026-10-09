/* vms_names.h - VMS-syntax starting points and names (DECISIONS D2).  */
#ifndef VMS_NAMES_H
#define VMS_NAMES_H

#include <stdbool.h>

/* Begin a starting point.  ARG in VMS syntax ("[.tree]", "[]",
   "DKA0:[X]", "tree.dir") is returned as a Unix name for the walk, and
   names under it are then shown in VMS syntax by vms_display_name;
   any other ARG is returned as it is, and names stay Unix names.  */
char *vms_start_point (char *arg);

/* PATH (a Unix name under the current starting point) as find should
   show it: unchanged for a Unix starting point; for a VMS one, the
   starting point as typed, or PATH in VMS syntax ("[.tree.sub]two.txt",
   a directory as "[.tree]sub.DIR").  The result may be a static buffer,
   valid until the next call.  */
char const *vms_display_name (char const *path, bool is_dir);

/* Whether names are being shown in VMS syntax.  */
bool vms_display_vms (void);

#endif
