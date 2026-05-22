#include <linux/reboot.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/reboot.h>
#include <unistd.h>

int main(void)
{
    setvbuf(stdout, NULL, _IONBF, 0);
    setvbuf(stderr, NULL, _IONBF, 0);

    puts("CONTRACTBPF_BOOT_OK");
    puts("CONTRACTBPF_INITRAMFS_OK");

    sync();
    sleep(1);
    reboot(LINUX_REBOOT_CMD_POWER_OFF);

    for (;;) {
        pause();
    }
}

