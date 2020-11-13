# Run terminals for Qemu/Arm secure and non-secure worlds console
# Relies on soc_term built from OP-TEE/Qemu release.
nc -z 127.0.0.1 54320 || gnome-terminal --execute ./soc_term 54320 &
nc -z 127.0.0.1 54321 || gnome-terminal --execute ./soc_term 54321 &
while ! nc -z 127.0.0.1 54320 || ! nc -z 127.0.0.1 54321; do sleep 1; done

cd output
qemu-system-arm  -nographic  -serial tcp:localhost:54320 -serial tcp:localhost:54321  -smp 2  -s -S -machine virt,secure=on -cpu cortex-a15  -d unimp -semihosting-config enable,target=native  -m 1057  -device virtio-rng-pci  -bios bl1.bin
