# This script reads the hardware hash from a device and uploads it to Intune for Windows Autopilot


### How to use:

1. When a device is first launched into Windows OOBE (language page), hit shift+F10.
2. Run go.cmd. If there's only one drive on the computer, this is with `D:\go.cmd`. If it does not work or there are multiple drives, run `wmic logicaldisk get name` to find the USB drive.
3. Wait for the Autopilot Registration powershell window to open, then unplug the USB. Wait until comnputer reboots, confirm device shows up in Intune.

---

### How it works:

1. go.cmd copies register.ps1 from the flash drive to a temporary folder in C:\, and then runs the script on the C:\ drive so the flash drive can be unplugged.
2. register.ps1 installs the necessary powershell modules.
3. It uses the app credentials to confirm and connect with the 365 tenant.
4. The script pulls the hardware hash from the device and begins the import to Intune.
5. Once the import is confirmed, the script will poll the deployment profile endpoint every 15 seconds to see if the device is assigned to it.
6. When the device is assigned, it will start a 60 second countdown before it runs sysprep.exe to reboot the computer.
7. After reboot, the device will land on the Autopilot OOBE page.


A try/catch statement is included for any errors, or if the device fails to be assigned. The user will be prompted accordingly.
