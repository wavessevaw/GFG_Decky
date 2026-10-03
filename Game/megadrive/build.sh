#!/usr/bin/env bash
# Builds the Mega Drive ROM "Саундчек мёртвых" (out/soundcheck.bin).
#
# Needs: a 68000 GCC (m68k-elf-gcc or m68k-linux-gnu-gcc), Java (for SGDK's rescomp/sizebnd),
# Python 3 with numpy and Pillow, git. SGDK is fetched at a pinned commit into .sgdk/.
#   Ubuntu: apt install gcc-m68k-linux-gnu binutils-m68k-linux-gnu default-jre-headless python3-numpy python3-pil
set -euo pipefail
cd "$(dirname "$0")"

SGDK_COMMIT=ee6870a6010b1e341ca36078f581a68a26c9a543
SGDK=${SGDK:-$PWD/.sgdk}
if [ ! -f "$SGDK/lib/libmd.a" ]; then
  rm -rf "$SGDK"
  git clone --filter=blob:none https://github.com/Stephane-D/SGDK.git "$SGDK"
  git -C "$SGDK" checkout -q "$SGDK_COMMIT"
fi

if command -v m68k-elf-gcc >/dev/null; then P=m68k-elf-; else P=m68k-linux-gnu-; fi
CC=${P}gcc

# The prebuilt libmd.a targets m68k-elf. Other toolchains (m68k-linux-gnu returns pointers in a0, not d0)
# need the library rebuilt from source with the same compiler; SGDK's Z80 tools are built for that.
# -mstrict-align: the 68000 faults on word access at odd addresses (68020+ toolchains assume it is fine).
if [ "$P" != m68k-elf- ] && [ ! -f "$SGDK/lib/.built-with-$P" ]; then
  mkdir -p "$SGDK/hostbin"
  gcc -O2 -w -o "$SGDK/hostbin/bintos" "$SGDK/tools/bintos/src/bintos.c"
  g++ -O2 -w -DMAX_PATH=4096 -o "$SGDK/hostbin/sjasm" "$SGDK"/tools/sjasm/src/*.cpp
  (cd "$SGDK" && rm -rf out && PATH="$SGDK/hostbin:$PATH" make -s -f makelib.gen GDK=. PREFIX=$P EXTRA_FLAGS=-mstrict-align release >/dev/null)
  touch "$SGDK/lib/.built-with-$P"
fi
OUT=out
rm -rf "$OUT/obj"; mkdir -p "$OUT/obj" res src

if [ "${SKIP_ASSETS:-0}" != 1 ]; then
  python3 tools/build_assets.py
fi

FLAGS="${EXTRA_CFLAGS:-} -DSGDK_GCC -m68000 -mstrict-align -Wall -Wextra -Wno-shift-negative-value -Wno-main -Wno-unused-parameter -fno-builtin
       -ffunction-sections -fdata-sections -fms-extensions -O2 -fomit-frame-pointer -fno-lto -fno-jump-tables
       -I$SGDK/inc -I$SGDK/res -Isrc -Ires"
AFLAGS="-x assembler-with-cpp -Wa,--register-prefix-optional,--bitwise-or"

# Resources (sprite sheets) through SGDK's rescomp.
for r in res/*.res; do
  n=$(basename "$r" .res)
  java -jar "$SGDK/bin/rescomp.jar" "$r" "$OUT/$n.s" 2>&1 | grep -iv "JAVA_TOOL_OPTIONS\|^$" | grep -i "error\|warn" || true
  mv "$OUT/$n.h" "res/${n}_res.h"
  $CC $AFLAGS $FLAGS -c "$OUT/$n.s" -o "$OUT/obj/res_$n.o"
done

# ROM header and boot code.
$CC $FLAGS -c src/boot/rom_header.c -o "$OUT/rom_header.o"
${P}objcopy -O binary "$OUT/rom_header.o" "$OUT/rom_header.bin"
cp "$SGDK/src/boot/sega.s" "$OUT/sega.s"
$CC $AFLAGS $FLAGS -c "$OUT/sega.s" -o "$OUT/sega.o"

OBJS=()
for f in src/*.c; do
  o="$OUT/obj/$(basename "$f" .c).o"
  $CC $FLAGS -c "$f" -o "$o"
  OBJS+=("$o")
done

# Guard: no word/long access at an odd displacement in our code (address error on a real 68000).
for o in "${OBJS[@]}"; do
  if ${P}objdump -d "$o" --no-show-raw-insn | grep -E "^\s+[0-9a-f]+:\s+[a-z]+\.?[wl]\s.*%a[0-7]@\(-?[0-9]*[13579][,)]"; then
    echo "odd-address word access in $o" >&2; exit 1
  fi
done

$CC -m68000 -n -T "$SGDK/md.ld" -nostdlib -fno-use-linker-plugin "$OUT/sega.o" "$OUT"/obj/*.o \
  "$SGDK/lib/libmd.a" "$SGDK/lib/libgcc.a" -o "$OUT/rom.out" \
  -Wl,--gc-sections,--build-id=none,-z,noexecstack 2>&1 | grep -v "GNU-stack\|deprecated" || true
${P}objcopy -O binary "$OUT/rom.out" "$OUT/soundcheck.bin"
java -jar "$SGDK/bin/sizebnd.jar" "$OUT/soundcheck.bin" -sizealign 131072 -checksum >/dev/null 2>&1
ls -l "$OUT/soundcheck.bin"
# INSTALL=1: ship the ROM inside SSMT (the hidden launcher opens it in an emulator).
if [ "${INSTALL:-0}" = 1 ]; then
  cp "$OUT/soundcheck.bin" ../../App/SSMT/Resources/Game/soundcheck.bin
fi
