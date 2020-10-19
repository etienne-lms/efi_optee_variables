#!/bin/bash
set -e

exit_usage() {
	echo "build-32b.sh           Build only";
	echo "build-32b.sh --clone   Clone & build";
	exit 1
}

[ "$1" != "" ] && [ "$1" != "--clone" ] && exit_usage

if [ "$1" == "--clone" ]; then

	#[ ! -d 'u-boot' ] && git clone https://gitlab.denx.de/u-boot/custodians/u-boot-efi -b efi-2020-10 && mv u-boot-efi u-boot 
	[ ! -d 'u-boot' ] && git clone https://github.com/u-boot/u-boot.git -b master

	#[ ! -d 'edk2-platforms' ] && git clone https://git.linaro.org/people/sughosh.ganu/edk2-platforms.git -b ffa_svc_optional_on_upstream
	#[ ! -d 'edk2-platforms' ] && git clone https://git.linaro.org/people/ilias.apalodimas/edk2-platforms.git -b stmm_rpmb_ffa
	[ ! -d 'edk2-platforms' ] && git clone https://github.com/etienne-lms/edk2-platforms.git -b stmm-arm-32b

	#[ ! -d 'edk2' ] && git clone https://git.linaro.org/people/ilias.apalodimas/edk2.git -b stmm_ffa
	#[ ! -d 'edk2' ] && git clone https://git.linaro.org/people/sughosh.ganu/edk2.git -b ffa_svc_optional_on_upstream
	[ ! -d 'edk2' ] && git clone https://github.com/etienne-lms/edk2.git -b stmm-arm-32b
	pushd edk2
	git submodule init
	git submodule update --init --recursive
	popd

	# Patch in OP-TEE under review: use etienne-lms until then
	#[ ! -d 'optee_os' ] && git clone https://github.com/OP-TEE/optee_os.git -b stmm-arm-32b
	[ ! -d 'optee_os' ] && git clone https://github.com/etienne-lms/optee_os.git -b stmm-arm-32b

	[ ! -d 'arm-trusted-firmware' ] && git clone https://github.com/ARM-software/arm-trusted-firmware.git -b master

	for i in u-boot edk2 edk2-platforms optee_os; do
		pushd "$i"
		git clean -d -f
		git reset --hard
		git pull --rebase
		popd
	done

	# Some late U-boot patching
	patch -d u-boot -p1 < patches/0001-efi-efi_loader-fix-size-of-buffer-size-into-in-optee.patch
	patch -d u-boot -p1 < patches/0002-rpmb-emulation-hack.-Breaks-proper-hardware-support.patch
	patch -d u-boot -p1 < patches/0003-configs-qemu_tfa_mm32-UEFI-StMM-in-32bit-OP-TEE.patch
else
	for i in u-boot edk2 edk2-platforms optee_os; do
		[ -d $i ] || { echo No $i repository. Run './build-32b.sh --clone' fisrt, aborting...; exit 1; }
	done
fi

# Build EDK2
export WORKSPACE=$(pwd)
export PACKAGES_PATH=$WORKSPACE/edk2:$WORKSPACE/edk2-platforms
export ACTIVE_PLATFORM="Platform/StMMRpmb/PlatformStandaloneMm.dsc"
export GCC5_ARM_PREFIX=arm-linux-gnueabihf-

source edk2/edksetup.sh
make -C edk2/BaseTools
build -p $ACTIVE_PLATFORM -b RELEASE -a ARM -t GCC5 -n `nproc` -D DO_X86EMU=TRUE
#-D UART_ENABLE=YES

# Build OP-TEE
cp Build/MmStandaloneRpmb/RELEASE_GCC5/FV/BL32_AP_MM.fd optee_os
pushd optee_os
export ARCH=arm
CROSS_COMPILE32=arm-linux-gnueabihf- make -j32 \
	PLATFORM=vexpress-qemu_virt CFG_STMM_PATH=BL32_AP_MM.fd CFG_RPMB_FS=y \
	CFG_RPMB_FS_DEV_ID=1 CFG_CORE_HEAP_SIZE=524288 CFG_RPMB_WRITE_KEY=y \
	CFG_TEE_CORE_LOG_LEVEL=1 DEBUG=1 CFG_WITH_LPAE=y CFG_UNWIND=y \
	CFG_WERROR=y
popd

# Build U-Boot
export CROSS_COMPILE=arm-linux-gnueabihf-
export ARCH=arm

pushd u-boot
make qemu_tfa_mm32_defconfig
make -j$(nproc)
popd

# Build ATF
pushd arm-trusted-firmware
make PLAT=qemu ARM_ARCH_MAJOR=7 ARCH=aarch32 \
	BL33=../u-boot/u-boot.bin \
	BL32_RAM_LOCATION=tdram AARCH32_SP=optee
popd

mkdir -p output
cp arm-trusted-firmware/build/qemu/release/*.bin output
cp optee_os/out/arm-plat-vexpress/core/tee-header_v2.bin output/bl32.bin
cp optee_os/out/arm-plat-vexpress/core/tee-pager_v2.bin output/bl32_extra1.bin
cp optee_os/out/arm-plat-vexpress/core/tee-pageable_v2.bin output/bl32_extra2.bin
cp u-boot/u-boot.bin output/bl33.bin

echo 
echo "#################### BUILD DONE ####################"

echo "
# Run qemu from the binary image files directory
cd output
qemu-system-arm \\
 -nographic \\
 -serial stdio -serial tcp::5000,server,nowait \\
 -smp 2 \\
 -s -S -machine virt,secure=on -cpu cortex-a15 \\
 -d unimp -semihosting-config enable,target=native \\
 -m 1057 \\
 -device virtio-rng-pci \\
 -bios bl1.bin
"
