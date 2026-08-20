#!/bin/bash
echo ""
echo "LineageOS 16.x Treble Buildbot"
echo "ATTENTION: this script syncs repo on each run"
echo "Executing in 5 seconds - CTRL-C to exit"
echo ""
sleep 5

# Abort early on error
set -eE
trap '(\
echo;\
echo \!\!\! An error happened during script execution;\
echo \!\!\! Please check console output for bad sync,;\
echo \!\!\! failed patch application, etc.;\
echo\
)' ERR

START=`date +%s`
BUILD_DATE="$(date +%Y%m%d)"
BL=$PWD/treble_build_los

echo "Preparing local manifest"
mkdir -p .repo/local_manifests
cp $BL/manifest.xml .repo/local_manifests/manifest.xml
echo ""

echo "Syncing repos"
repo sync -c --force-sync --no-clone-bundle --no-tags -j$(nproc --all)
echo ""

echo "Setting up build environment"
source build/envsetup.sh &> /dev/null
echo ""

echo ">>> Downloading custom InputReader.cpp..."
wget -q -O frameworks/native/services/inputflinger/InputReader.cpp https://github.com/amaxsky/los16.0gsi/raw/refs/heads/main/InputReader.cpp

if [ -s frameworks/native/services/inputflinger/InputReader.cpp ]; then
    echo "InputReader.cpp replaced successfully"
else
    echo "WARNING: InputReader.cpp download failed or empty!"
fi

echo ''
echo '>>> Displaying inputflinger directory contents...'
ls -la frameworks/native/services/inputflinger/
echo ''
echo '>>> File size check:'
wc -l frameworks/native/services/inputflinger/InputReader.cpp
echo ''
echo '>>> First 10 lines of InputReader.cpp:'
head -10 frameworks/native/services/inputflinger/InputReader.cpp
echo ''

echo "Applying PHH patches"
cd frameworks/base
git am $BL/patches/0001-Squashed-revert-of-LOS-FOD-implementation.patch || echo "  -> Skipping failed patch: Squashed-revert-of-LOS-FOD-implementation"
cd ../..
rm -f device/*/sepolicy/common/private/genfs_contexts
cd device/phh/treble
git clean -fdx
bash generate.sh lineage
cd ../../..
bash ~/treble_experimentations/apply-patches.sh treble_patches/patches || echo "  -> Some PHH patches failed, continuing..."
echo ""

echo "Applying universal patches"
cd frameworks/base
git am $BL/patches/0001-Disable-vendor-mismatch-warning.patch || echo "  -> Skipping failed patch: Disable-vendor-mismatch-warning"
git am $BL/patches/0001-Keyguard-Show-shortcuts-by-default.patch || echo "  -> Skipping failed patch: Keyguard-Show-shortcuts-by-default"
git am $BL/patches/0001-core-Add-support-for-MicroG.patch || echo "  -> Skipping failed patch: core-Add-support-for-MicroG"
cd ../..
cd lineage-sdk
git am $BL/patches/0001-sdk-Invert-per-app-stretch-to-fullscreen.patch || echo "  -> Skipping failed patch: sdk-Invert-per-app-stretch-to-fullscreen"
cd ..
cd packages/apps/LineageParts
git am $BL/patches/0001-LineageParts-Invert-per-app-stretch-to-fullscreen.patch || echo "  -> Skipping failed patch: LineageParts-Invert-per-app-stretch-to-fullscreen"
cd ../../..
cd vendor/lineage
git am $BL/patches/0001-vendor_lineage-Log-privapp-permissions-whitelist-vio.patch || echo "  -> Skipping failed patch: vendor_lineage-Log-privapp-permissions-whitelist-vio"
cd ../..
echo ""

echo "Applying GSI-specific patches"
cd build/make
git am $BL/patches/0001-Revert-Enable-dyanmic-image-size-for-GSI.patch || echo "  -> Skipping failed patch: Revert-Enable-dyanmic-image-size-for-GSI"
cd ../..
cd device/phh/treble
git revert 82b15278bad816632dcaeaed623b569978e9840d --no-edit || echo "  -> Skipping failed revert: Update lineage.mk for LineageOS 16.0"
git am $BL/patches/0001-Remove-fsck-SELinux-labels.patch || echo "  -> Skipping failed patch: Remove-fsck-SELinux-labels"
git am $BL/patches/0001-treble-Add-overlay-lineage.patch || echo "  -> Skipping failed patch: treble-Add-overlay-lineage"
git am $BL/patches/0001-treble-Don-t-specify-config_wallpaperCropperPackage.patch || echo "  -> Skipping failed patch: treble-Don-t-specify-config_wallpaperCropperPackage"
git am $BL/patches/0001-Increase-system-partition-size-for-arm_ab.patch || echo "  -> Skipping failed patch: Increase-system-partition-size-for-arm_ab"
cd ../../..
cd external/tinycompress
git revert fbe2bd5c3d670234c3c92f875986acc148e6d792 --no-edit || echo "  -> Skipping failed revert: tinycompress: Use generated kernel headers"
cd ../..
cd vendor/interfaces
git revert 0611b67d96f7f7f71b12079a1b345022fe7bd323 --no-edit || echo "  -> Skipping failed revert: Include Samsung Q camera provider"
cd ../..
cd vendor/lineage
git am $BL/patches/0001-build_soong-Disable-generated_kernel_headers.patch || echo "  -> Skipping failed patch: build_soong-Disable-generated_kernel_headers"
cd ../..
cd vendor/qcom/opensource/cryptfs_hw
git revert 6a3fc11bcc95d1abebb60e5d714adf75ece83102 --no-edit || echo "  -> Skipping failed revert: cryptfs_hw: Use generated kernel headers"
git am $BL/patches/0001-Header-hack-to-compile-for-8974.patch || echo "  -> Skipping failed patch: Header-hack-to-compile-for-8974"
cd ../../../..
echo ""

echo "All patches applied (failures skipped)"
sleep 5
echo ""

export WITHOUT_CHECK_API=true
export WITH_SU=true
mkdir -p ~/build-output/

buildVariant() {
	lunch ${1}-userdebug
	make installclean
	make -j$(nproc --all) systemimage
	make vndk-test-sepolicy
	mv $OUT/system.img ~/build-output/lineage-16.0-$BUILD_DATE-UNOFFICIAL-${1}.img
}

buildVariant treble_arm_avN
buildVariant treble_arm_bvN
buildVariant treble_a64_avN
buildVariant treble_a64_bvN
buildVariant treble_arm64_avN
buildVariant treble_arm64_bvN
ls ~/build-output | grep 'lineage'

END=`date +%s`
ELAPSEDM=$(($(($END-$START))/60))
ELAPSEDS=$(($(($END-$START))-$ELAPSEDM*60))
echo "Buildbot completed in $ELAPSEDM minutes and $ELAPSEDS seconds"
echo ""