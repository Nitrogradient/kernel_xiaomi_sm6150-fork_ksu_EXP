#!/bin/bash

set -e

# ===== COLORS =====
green='\033[0;32m'
red='\033[0;31m'
yellow='\033[0;33m'
white='\033[0m'


# ===== DEVICE CONFIG =====
DEVICE_TYPE=${DEVICE_TYPE:-davinci}

case $DEVICE_TYPE in
  davinci)
    DEVICE="Redmi K20"
    CODENAME="davinci"
    DEFCONFIG="vendor/davinci_a16_defconfig"
    ;;
  raphael)
    DEVICE="Redmi K20 Pro"
    CODENAME="raphael"
    DEFCONFIG="vendor/raphael_defconfig"
    ;;
  *)
    echo -e "${red}Unknown device${white}"
    exit 1
    ;;
esac

# ===== BUILD INFO =====
KERNEL_NAME="NitroKernel"
DATE=$(date +"%Y%m%d-%H%M")
OUT_DIR=out

# ===== CLEAN =====
echo -e "${green}==> Cleaning${white}"
rm -rf $OUT_DIR error.log fake_include
mkdir -p $OUT_DIR

# ===== ENV =====
echo -e "${green}==> Setting environment${white}"

export ARCH=arm64
export SUBARCH=arm64

# Оптимизации для скорости
export CC="clang"
export LD="ld.lld"
export LLVM=1
export LLVM_IAS=1

# Кросс-компиляция
export CROSS_COMPILE="aarch64-linux-android-"
export CROSS_COMPILE_ARM32="arm-linux-androideabi-"
export CLANG_TRIPLE="aarch64-linux-gnu-"

# Ускорение компиляции
export HOSTCFLAGS="-O2 -pipe"
export HOSTCXXFLAGS="-O2 -pipe"
export RUSTFLAGS="-C opt-level=2"

# Параллельная линковка (быстрее)
export LDFLAGS="-Wl,--threads -Wl,--thread-count=$(nproc)"

# Используем ccache если доступен (кеширует компиляцию)
if command -v ccache &> /dev/null; then
    export CC="ccache clang"
    export LD="ccache ld.lld"
    echo -e "${green}ccache enabled - second builds will be faster${white}"
fi

export KBUILD_BUILD_USER="nitro"
export KBUILD_BUILD_HOST="bazzite"

# ===== CHECK CLANG =====
echo -e "${green}==> Checking clang${white}"
clang --version || { echo -e "${red}clang not found${white}"; exit 1; }

# ===== DEFCONFIG =====
echo -e "${green}==> Loading defconfig (${DEFCONFIG})${white}"
make O=$OUT_DIR $DEFCONFIG

# ===== BUILD =====
echo -e "${yellow}==> Building kernel${white}"

START=$(date +"%s")

make -j$(nproc) O=$OUT_DIR \
    CC=clang \
    LD=ld.lld \
    LLVM=1 \
    LLVM_IAS=1 \
    HOSTCFLAGS="$HOSTCFLAGS" \
    Image.gz dtbs dtbo.img 2>&1 | tee error.log

END=$(date +"%s")
DIFF=$((END - START))

# ===== CHECK =====
IMG="$OUT_DIR/arch/arm64/boot/Image.gz"

if [ ! -f "$IMG" ]; then
    echo -e "${red}Build failed${white}"
    exit 1
fi

echo -e "${green}Build success in $((DIFF / 60))m $((DIFF % 60))s${white}"

# ===== OPTIONAL PACK =====
echo -e "${green}==> Preparing zip${white}"

rm -rf zip
git clone --depth=1 https://github.com/osm0sis/AnyKernel3.git zip

cp $IMG zip/
cp $OUT_DIR/arch/arm64/boot/dtbo.img zip/ 2>/dev/null || true

cd zip
ZIP_NAME="${KERNEL_NAME}-${CODENAME}-${DATE}.zip"
zip -r9 $ZIP_NAME * -x .git README.md

echo -e "${green}ZIP created: zip/$ZIP_NAME${white}"
