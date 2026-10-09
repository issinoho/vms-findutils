#!/usr/bin/env bash
# prepare.sh - build a VMS-ready source tree in staging/<name>-<version>/
#
#   1. fetch + verify the upstream tarball
#   2. extract it, apply patches/series, lay overlay/ over the top
#   3. run the upstream configure on this host, with every platform answer
#      taken from VMS probe results (probed.site) or hand-settled values
#      (vms-manual.site) instead of from Linux
#   4. generate gnulib's headers and config.h, copy them into the tree
#   5. write the MMS source lists and the configuration snapshot
#
# Nothing in staging/ is ever edited by hand: fix things in patches/ or overlay/.
set -euo pipefail

top=$(cd "$(dirname "$0")/.." && pwd)
. "$top/upstream.conf"
name=$UPSTREAM_NAME-$UPSTREAM_VERSION
tarball=$top/cache/$(basename "$UPSTREAM_URL")
stage=$top/staging/$name
hostcfg=$top/cache/hostcfg-$name
cfgdir=$top/overlay/vms/config
snapshot=$top/snapshot
# Configuration answers come from this node's VSI C run; both architectures
# share one CRTL feature set (see docs/vms-environment.md).
PRIMARY_NODE=${PRIMARY_NODE:-ia64}
PRIMARY_TRIPLET=ia64-hp-openvms

step() { echo "prepare: $*"; }
die() { echo "prepare: error: $*" >&2; exit 1; }

"$top/tools/fetch.sh" >/dev/null

# --- 2. extract, patch, overlay -------------------------------------------
step "extracting $name"
rm -rf "$stage"
mkdir -p "$top/staging"
tar -xJf "$tarball" -C "$top/staging"
[ -d "$stage" ] || die "tarball did not unpack to $stage"

while read -r p; do
    case $p in ''|'#'*) continue ;; esac
    step "patch $p"
    patch -d "$stage" -p1 -s --no-backup-if-mismatch -F0 < "$top/patches/$p" ||
        die "patch $p does not apply cleanly"
done < "$top/patches/series"

# overlay/ may only add files; changes to upstream files belong in patches/.
(cd "$top/overlay" && find . -type f) | while read -r f; do
    [ -e "$stage/$f" ] && die "overlay/$f would replace an upstream file; use a patch"
    true
done
cp -a "$top/overlay/." "$stage/"

# --- 3. host configure with VMS answers ----------------------------------
step "configure (host, VMS answers)"
rm -rf "$hostcfg"
mkdir -p "$hostcfg"
site=$hostcfg/vms.site
# Answers: the VSI C configure run (vms_configure.sh) if there is one, else the
# function/header probes; vms-manual.site last so it always wins.
answers=$cfgdir/configure-$PRIMARY_NODE.cache
if [ ! -f "$answers" ]; then
    # First pass of a new release: stage the tree for vms_configure.sh, which
    # writes the answers.  The result is not buildable on VMS yet.
    answers=$hostcfg/no-answers.site; : > "$answers"
    step "WARNING: no $(basename "$cfgdir")/configure-$PRIMARY_NODE.cache yet:" \
         "Linux answers (run tools/vms_configure.sh, then prepare again)"
fi
step "answers from $(basename "$answers")"
python3 "$top/tools/nextheaders_site.py" "$stage/configure" "$cfgdir/crtl_modules.txt" \
    > "$cfgdir/next-headers.site"
cat "$answers" "$cfgdir/next-headers.site" "$cfgdir/vms-manual.site" > "$site"
mapfile -t cfgargs < <(grep -v -e '^#' -e '^$' "$cfgdir/configure.args")
# Same --host as vms_configure.sh so configure takes the same code paths.
(cd "$hostcfg" && CONFIG_SITE=$site "$stage/configure" -q -C \
    --build="$("$stage/build-aux/config.guess")" --host=$PRIMARY_TRIPLET CC=gcc "${cfgargs[@]}" \
    > configure.out 2>&1) || { tail -20 "$hostcfg/configure.out"; die "configure failed"; }

# --- 4. generated headers and config.h -------------------------------------
printvar() {  # printvar <dir> <make variable>
    make -s -C "$hostcfg/$1" -f Makefile -f "$top/tools/printvar.mk" "print-$2"
}
# findutils' gnulib is in gl/lib (libgnulib.a); its own helpers are libfind.a
# in lib/ and libfindtools.a in find/.
gl=gl/lib
built=$(printvar $gl BUILT_SOURCES)
step "generating $(echo $built | wc -w) gnulib headers"
make -s -C "$hostcfg/$gl" $built >/dev/null
for h in $built; do
    # Some are shipped in the source tree and not rebuilt (unicase tables).
    [ -f "$hostcfg/$gl/$h" ] || { [ -f "$stage/$gl/$h" ] && continue; die "no generated $h"; }
    mkdir -p "$stage/$gl/$(dirname "$h")"
    cp "$hostcfg/$gl/$h" "$stage/$gl/$h"
done
cp "$hostcfg/config.h" "$stage/config.h"   # AC_CONFIG_HEADERS([config.h])
# Link tests that keep no cache variable run again here, on Linux.  One of
# them finds glibc's program_invocation_name and program_invocation_short_name;
# VSI C has neither (vms-tar: "undefined symbol program_invocation_name"),
# so gnulib must supply them.
sed -i -e 's|^#define HAVE_PROGRAM_INVOCATION_NAME 1$|/* #undef HAVE_PROGRAM_INVOCATION_NAME */|' \
       -e 's|^#define HAVE_PROGRAM_INVOCATION_SHORT_NAME 1$|/* #undef HAVE_PROGRAM_INVOCATION_SHORT_NAME */|' \
    "$stage/config.h"
# VSI C cannot #include a name with two dots: generated malloc/*.gl.h
# become *_gl.h, and the gnulib headers that include them (scratch_buffer.h,
# dynarray.h) are rewritten to use the new names.
for f in "$stage"/$gl/malloc/*.gl.h; do
    [ -e "$f" ] || continue
    sed 's|<malloc/\([a-z_-]*\)\.gl\.h>|<malloc/\1_gl.h>|g' "$f" > "${f%.gl.h}_gl.h"
    rm "$f"
done
for f in "$stage"/$gl/*.h "$stage"/$gl/*.c; do
    grep -q '<malloc/[a-z_-]*\.gl\.h>' "$f" || continue
    sed -i 's|<malloc/\([a-z_-]*\)\.gl\.h>|<malloc/\1_gl.h>|g' "$f"
done
# struct scratch_buffer aligns its buffer with a union member named __align,
# a reserved word in VSI C (DEC C's alignment qualifier): "invalid
# declarator".  The member is never used by name; rename it.
for f in "$stage"/$gl/malloc/scratch_buffer_gl.h "$stage"/$gl/malloc/scratch_buffer.h; do
    [ -f "$f" ] && sed -i 's/max_align_t __align;/max_align_t __gl_align;/' "$f"
done

# --- 5. MMS source lists ---------------------------------------------------
# Objects for libgnulib: automake sources after conditionals, plus LIBOBJS.
lib_srcs=$( { printvar $gl libgnulib_a_SOURCES
              printvar $gl libgnulib_a_LIBADD | tr ' ' '\n' | sed -n 's/^libgnulib_a-//; s/\.o$/.c/p'
            } | tr ' ' '\n' | sed 's/\.y$/.c/' | grep '\.c$' | sort -u)
# Leave out what cannot work on VMS (overlay/vms/lib-exclude.txt, with reasons).
while read -r pat; do
    case $pat in ''|'#'*) continue ;; esac
    lib_srcs=$(echo "$lib_srcs" | while read -r f; do
        case $(basename "$f") in $pat) ;; *) echo "$f" ;; esac; done)
done < "$top/overlay/vms/lib-exclude.txt"
cfiles() { printvar "$1" "$2" | tr ' ' '\n' | grep '\.c$' | sort -u; }
# SRC is find itself (ftsfind.c plus libfindtools); the other programs and
# libfind are groups of their own.  All their objects share $(OBJ).
src_srcs=$( { cfiles find find_SOURCES; cfiles find libfindtools_a_SOURCES; } | sort -u)
libfind_srcs=$(cfiles lib libfind_a_SOURCES)
xargs_srcs=$(cfiles xargs xargs_SOURCES)
locate_srcs=$(cfiles locate locate_SOURCES)
# frcode shares word_io.c with locate; it is compiled once, in LOCATE.
frcode_srcs=$(comm -23 <(cfiles locate frcode_SOURCES) <(echo "$locate_srcs"))
dups=$(printf '%s\n' "$src_srcs" "$libfind_srcs" "$xargs_srcs" "$locate_srcs" "$frcode_srcs" \
           $(grep -v '^#' "$top/overlay/vms/extra-sources.txt") | grep . | xargs -n1 basename | sort | uniq -d)
[ -z "$dups" ] || die "duplicate object names in \$(OBJ): $dups"
dups=$(echo "$lib_srcs" | xargs -n1 basename | sort | uniq -d)
[ -z "$dups" ] || die "duplicate object names in libgnulib: $dups"

mkdir -p "$stage/vms"
echo "$lib_srcs" > "$hostcfg/lib-sources.txt"
echo "$src_srcs" > "$hostcfg/src-sources.txt"
echo "$libfind_srcs" > "$hostcfg/libfind-sources.txt"
echo "$xargs_srcs" > "$hostcfg/xargs-sources.txt"
echo "$locate_srcs" > "$hostcfg/locate-sources.txt"
echo "$frcode_srcs" > "$hostcfg/frcode-sources.txt"
cp "$top/overlay/vms/extra-sources.txt" "$hostcfg/extra-sources.txt"
GEN_MMS_LIB_BASE=$gl GEN_MMS_SRC_BASE=find GEN_MMS_CONFIG_DIR= python3 "$top/tools/gen_mms.py" \
    "$cfgdir/ccflags.txt" "$hostcfg/lib-sources.txt" "$hostcfg/src-sources.txt" "$hostcfg/extra-sources.txt" \
    LIBFIND=lib:"$hostcfg/libfind-sources.txt" XARGS=xargs:"$hostcfg/xargs-sources.txt" \
    LOCATE=locate:"$hostcfg/locate-sources.txt" FRCODE=locate:"$hostcfg/frcode-sources.txt" \
    > "$stage/vms/sources.mms"

if [ -d "$stage/vms/kit" ]; then
step "PCSI kit inputs"
: "${KIT_PRODUCER:=ISSINOHO}"
# Versions: 4.11.0 -> V4.11-0 (a two-part one gets update 0); our VMS patch level is the
# ECO, so $UPSTREAM_VERSION-vms$VMS_PATCH_LEVEL is V<major>.<minor>-<update>E<level>.
IFS=. read -r major minor update _ <<< "$UPSTREAM_VERSION"
pcsiversion="V$major.$minor-${update:-0}E$VMS_PATCH_LEVEL"
kitversion="$UPSTREAM_VERSION-vms$VMS_PATCH_LEVEL"
kit=$stage/vms/kit
subst() {
    sed -e "s/@PRODUCER@/$KIT_PRODUCER/g" -e "s/@BASE@/$1/g" \
        -e "s/@PCSIVERSION@/$pcsiversion/g" -e "s/@VERSION@/$UPSTREAM_VERSION/g" \
        -e "s/@KITVERSION@/$kitversion/g" -e "s/@ARCH@/$2/g"
}
for base in I64VMS X86VMS; do
    subst $base "" < "$kit/findutils.pcsi\$desc_template" > "$kit/FINDUTILS-$base.PCSI\$DESC"
    subst $base "" < "$kit/findutils.pcsi\$text_template" > "$kit/FINDUTILS-$base.PCSI\$TEXT"
done
rm -f "$kit/findutils.pcsi\$desc_template" "$kit/findutils.pcsi\$text_template"
mv "$kit/findutils\$startup.com" "$kit/FINDUTILS\$STARTUP.COM"
mv "$kit/findutils\$setup.com" "$kit/FINDUTILS\$SETUP.COM"
subst "" "IA64 and x86-64" < "$kit/readme.vms" > "$kit/README.VMS"; rm -f "$kit/readme.vms"
mkdir -p "$kit/doc"
cp "$stage/COPYING" "$kit/doc/COPYING."
cp "$stage/NEWS" "$kit/doc/NEWS."
for man in find/find.1 xargs/xargs.1; do
    up=$(basename "$man" .1 | tr a-z A-Z)
    cp "$stage/$man" "$kit/doc/$up.1"
    groff -man -Tascii -P-cbou "$stage/$man" > "$kit/doc/$up.TXT" 2>/dev/null
    [ -s "$kit/doc/$up.TXT" ] || die "groff did not render $man"
done
printf 'KIT_PRODUCER=%s\nPCSI_VERSION=%s\nKIT_VERSION=%s\n' "$KIT_PRODUCER" "$pcsiversion" \
    "$kitversion" > "$kit/kit.env"
fi

# --- snapshot: the resolved configuration, committed and reviewed ----------
mkdir -p "$snapshot"
cp "$hostcfg/config.h" "$snapshot/config.h"
echo "$lib_srcs" > "$snapshot/lib-sources.txt"
{ echo "# find (SRC)"; echo "$src_srcs"; echo "# libfind"; echo "$libfind_srcs"
  echo "# xargs"; echo "$xargs_srcs"; echo "# locate"; echo "$locate_srcs"
  echo "# frcode"; echo "$frcode_srcs"; } > "$snapshot/src-sources.txt"
# Every cached answer, and where it came from.
cat "$cfgdir/next-headers.site" "$cfgdir/vms-manual.site" > "$hostcfg/manual.site"
python3 "$top/tools/cfgreport.py" "$hostcfg/config.cache" "$answers" \
    "$hostcfg/manual.site" > "$snapshot/cache-answers.txt"
step "inherited-from-Linux answers: $(grep -c ' host$' "$snapshot/cache-answers.txt" || true)" \
     "(see snapshot/cache-answers.txt)"

step "staged $stage"
if ! git -C "$top" diff --quiet -- snapshot 2>/dev/null; then
    step "snapshot/ changed - review with: git diff -- snapshot"
fi
