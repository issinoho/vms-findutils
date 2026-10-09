$! FINDUTILS$STARTUP.COM - system startup for GNU findutils on OpenVMS
$!
$! Installed by PCSI into SYS$STARTUP.  Defines the system logical name
$! FINDUTILS$ROOT, pointing at the installed [FINDUTILS] directory.  To run it at every
$! boot, add this line to SYS$MANAGER:SYSTARTUP_VMS.COM:
$!
$!     $ @SYS$STARTUP:FINDUTILS$STARTUP.COM
$!
$! P1 = "INSTALL": also print the post-installation tasks (PCSI runs it so).
$! P1 = "REMOVE":  deassign FINDUTILS$ROOT instead (PCSI runs it so at removal).
$!
$! Users then define the commands with
$!     $ @FINDUTILS$ROOT:[000000]FINDUTILS$SETUP.COM
$!
$ set noon
$ mode = f$edit(p1, "UPCASE")
$ if mode .eqs. "REMOVE"
$ then
$   if f$trnlnm("FINDUTILS$ROOT", "LNM$SYSTEM_TABLE") .nes. "" then -
        deassign/system/executive_mode FINDUTILS$ROOT
$   exit 1
$ endif
$!
$! This procedure sits in <destination>[SYS$STARTUP]; the product is in
$! <destination>[FINDUTILS].  Rooted logicals need the physical form:
$! DKA0:[SYS0.SYSCOMMON.SYS$STARTUP] -> DKA0:[SYS0.SYSCOMMON.FINDUTILS.]
$ proc = f$environment("PROCEDURE")
$ dev = f$parse(proc,,,"DEVICE","NO_CONCEAL")
$ dir = f$edit(f$parse(proc,,,"DIRECTORY","NO_CONCEAL"), "UPCASE") - "]["
$ root = dir - "SYS$STARTUP]" + "FINDUTILS.]"
$ if root .eqs. dir + "FINDUTILS.]"
$ then
$   write sys$error "FINDUTILS$STARTUP: expected to be in a [SYS$STARTUP] directory, not ''dir'"
$   exit 44
$ endif
$ root = root - ".000000"
$ define/system/executive_mode/translation_attributes=concealed FINDUTILS$ROOT 'dev''root'
$ if f$search("FINDUTILS$ROOT:[BIN]FIND.EXE") .eqs. ""
$ then
$   write sys$error "FINDUTILS$STARTUP: FIND.EXE not found under ''dev'''root'"
$   exit 44
$ endif
$ if mode .nes. "INSTALL" then exit 1
$ say = "write sys$output"
$ say ""
$ say "    Post-installation tasks for GNU findutils"
$ say ""
$ say "    At system startup: to define FINDUTILS$ROOT at every boot, add this line to"
$ say "    SYS$MANAGER:SYSTARTUP_VMS.COM:"
$ say "    $ @SYS$STARTUP:FINDUTILS$STARTUP.COM"
$ say "    For each user: to define the commands, add this line to LOGIN.COM:"
$ say "    $ @FINDUTILS$ROOT:[000000]FINDUTILS$SETUP.COM"
$ say ""
$ say "    PRODUCT REMOVE FINDUTILS removes the product and deassigns FINDUTILS$ROOT."
$ say ""
$ exit 1
