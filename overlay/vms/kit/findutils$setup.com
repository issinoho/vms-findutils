$! FINDUTILS$SETUP.COM - define the GNU findutils commands for a user
$!
$! Add to LOGIN.COM (or SYS$MANAGER:SYLOGIN.COM for everyone):
$!     $ @FINDUTILS$ROOT:[000000]FINDUTILS$SETUP.COM
$!
$! Quote upper-case options, or SET PROCESS/PARSE_STYLE=EXTENDED: traditional DCL
$! parsing changes the case of unquoted arguments; batch jobs use the traditional style.
$!
$ if f$trnlnm("FINDUTILS$ROOT") .eqs. ""
$ then
$   write sys$error "FINDUTILS$SETUP: FINDUTILS$ROOT is not defined; run FINDUTILS$STARTUP.COM first"
$   exit 44
$ endif
$ find :== $FINDUTILS$ROOT:[BIN]FIND.EXE
$ xargs :== $FINDUTILS$ROOT:[BIN]XARGS.EXE
$ exit 1
