/* vms_mountlist.c - read_file_system_list() for GNU findutils on OpenVMS.

   gnulib's mountlist.c has no OpenVMS method ("Please port gnulib
   mountlist.c to your platform!").  find uses the list only for -fstype
   and to notice file systems mounted during a search, and copes with
   none: -fstype then reports "unknown".  So there is no list.

   Part of the OpenVMS port of GNU findutils
   (github.com/issinoho/vms-findutils); distributed under the GNU General
   Public License, version 3 or later.  */

#include <config.h>
#include "mountlist.h"

#include <errno.h>
#include <stdlib.h>

struct mount_entry *
read_file_system_list (bool need_fs_type)
{
  (void) need_fs_type;
  errno = ENOSYS;
  return NULL;
}

void
free_mount_entry (struct mount_entry *me)
{
  free (me->me_devname);
  free (me->me_mountdir);
  free (me->me_mntroot);
  if (me->me_type_malloced)
    free (me->me_type);
  free (me);
}
