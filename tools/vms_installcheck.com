$! VMS_INSTALLCHECK.COM <tree-dir-name> - install the FINDUTILS kit, verify, smoke-test
$! the installed image, then remove it.  Changes the system while it runs (PCSI
$! database, SYS$COMMON:[FINDUTILS], system logical FINDUTILS$ROOT); leaves it as it was.
$ set noon
$ arch = f$edit(f$getsyi("ARCH_NAME"), "UPCASE")
$ base = "I64VMS"
$ if arch .eqs. "X86_64" then base = "X86VMS"
$ tree = f$environment("DEFAULT") - "]" + "." + p1 + "]"
$ kitdir = tree - "]" + ".KIT_''arch']"
$ write sys$output "=== INSTALL from ", kitdir
$ product install FINDUTILS /producer=ISSINOHO /base_system='base' /source='kitdir' /options=noconfirm /log
$ write sys$output "=== install status ", $status
$ product show product FINDUTILS /producer=ISSINOHO
$ write sys$output "=== VERIFY"
$ write sys$output "startup procedure: [", f$search("SYS$STARTUP:FINDUTILS$STARTUP.COM"), "]"
$ show logical FINDUTILS$ROOT
$ directory/nohead/notrail FINDUTILS$ROOT:[000000...]*.*
$ @FINDUTILS$ROOT:[000000]FINDUTILS$SETUP.COM
$ show symbol find
$ show symbol xargs
$ show symbol locate
$ show symbol updatedb
$ find "--version"
$ xargs "--version"
$ locate "--version"
$ write sys$output "=== SMOKE TEST on installed image"
$ smoke = tree - "]" + ".VMS]TEST_SMOKE.COM"
$ @'smoke' FINDUTILS$ROOT:[BIN]FIND.EXE
$ write sys$output "=== REMOVE"
$ product remove FINDUTILS /producer=ISSINOHO /options=noconfirm /log
$ write sys$output "=== remove status ", $status
$ write sys$output "FINDUTILS$ROOT after removal: [", f$trnlnm("FINDUTILS$ROOT"), "]"
$ write sys$output "files after removal: [", f$search("SYS$COMMON:[FINDUTILS...]*.*"), "]"
$ write sys$output "startup after removal: [", f$search("SYS$STARTUP:FINDUTILS$STARTUP.COM"), "]"
$ product show product FINDUTILS /producer=ISSINOHO
$ delete/symbol/global find
$ delete/symbol/global xargs
$ delete/symbol/global locate
$ delete/symbol/global updatedb
