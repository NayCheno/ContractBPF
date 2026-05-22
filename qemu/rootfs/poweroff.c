#include <linux/reboot.h>
#include <sys/reboot.h>
#include <unistd.h>

int main(void)
{
    sync();
    reboot(LINUX_REBOOT_CMD_POWER_OFF);
    for (;;) {
        pause();
    }
}

