# Debugging Notes

Record failures instead of hiding them. Each failure entry should include:

- exact command;
- exit status;
- relevant log path;
- immediate hypothesis;
- next narrow validation.

For QEMU boot failures, start with console configuration, initramfs contents, init permissions, and whether the kernel was vanilla or patched.

