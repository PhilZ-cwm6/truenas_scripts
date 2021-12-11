# TrueNAS Scripts

## save_config.sh

### FUNCTIONS
- Backup TrueNAS/FreeNAS configuration database and password secret encryption files (storage encryption keys)
  + config files are encrypted in openssl
  + config files can also be encrypted using rar, gpg or stored as non encrypted tar
- Decrypt/Extract an openssl, rar, gpg or tar config file

### SYNOPSIS
- Backups are performed and encrypted on the TrueNAS/FreeNAS main host
- The backups and logs are stored locally on the TrueNAS server
- The default storage locations for backup and log files are respectively `$target_mount_point/save_config` and `$target_mount_point/logs` directories
- The target local directory `$target_mount_point` can be overriden either by command line or by editing in script variable `$target_mount_point`
- The name of the local subdirectory `save_config` can be changed by editing in script variable `$backup_dir_name`

- By default, an openssl aes256 encryped backup file is generated
- Optionally, encrypted rar5 or gpg files can be generated or even a non compressed tar file
- Multiple output formats can be specified at the same time
- If no file format is specified, script will assume the openssl encryption as default
- This default file format can be changed by editing in script value `$default_encryption`

- Decrypting backup files is done with the `-d|--decrypt` option, associated with -in option
- Optional decrypting options are -out (output directory) and any input file format option `-ssl|-rar|-gpg|-tar`
- See below examples for how to decrypt

### SYNTAX
    script_name.sh [-options][Positional params]

#### USAGE
    script_name.sh [-options] [target_mount_point] [filecheck_mount_point]

#### Positional Parameters
    - target_mount_point   : Taget dataset/directory where the config files will be saved
    - filecheck_mount_point: Name of a file or directory in the root of $target_mount_point.
                             Used to verify that the target directory is properly mounted
                             `$target_mount_point/$filecheck_mount_point` must exist as a file or directory

- if omitted, you must edit below `$target_mount_point` and `$filecheck_mount_point` variables
- when provided by command line, they will override the 2 inscript variables
- backups are stored under `$target_mount_point/save_config` directory
- logs are created under a directory: `$target_mount_point/logs`

#### Options
    [-ssl|--ssl-encryption][-rar|--rar-encryption][-gpg|--gpg-encryption]
    [-tar|--unencrypted-tar][-iter|--iterations-count]
    [-?|-help]

#### Decrypt options:
    [-d|--decrypt][-in|--input-file][-out|--out-dir][one encryption option][-iter|--iterations-count]

#### Options details
    -ssl|--ssl-encryption    : generate an openssl encrypted backup
    -rar|--rar-encryption    : generate a RAR5 AES256 encrypted backup. You must install rar binary
    -gpg|--gpg-encryption    : generate a GnuPG AES256 encrypted backup (GPG)
    -tar|--unencrypted-tar   : generate a tar file with no encryption, strongly not recommended.
                               Will generate a warning to stderr
    -iter|--iterations-count : set a custom iterations count, overrides `$openssl_iter` variable
                               by default, if not set by options and `$openssl_iter` is kept as empty string in script,
                               it will use default openssl value, compatible with pfsense GUI encryption
    -d|--decrypt             : decrypt mode
    -in|--input-file         : file to decrypt
    -out|--out-dir           : directory where uncrypted files will be extracted.
                               if omitted, extracts to a `config.NNNN` directory created in local folder

- if no encryption option is specified, use default encryption set in variable `$default_encryption`

### INSTALLATION
- plan the dataset where you will copy the script, ideally to a unix dataset (not windows SMB)
- exp: /mnt/my_pool/my_dataset
- SSH / shell into TrueNAS as root
- create a directory to hold your scripts and ensure it can only be read by root to prevent access to your passwords
```
mkdir /mnt/my_pool/my_dataset/scripts
chmod 700 scripts
chown root:wheel scripts
```
- copy the save_config.sh to the scripts directory and ensure it can only be executed by root
```
cp save_config.sh /mnt/my_pool/my_dataset/scripts/
chmod 700 /mnt/my_pool/my_dataset/scripts/save_config.sh
chown root:wheel /mnt/my_pool/my_dataset/scripts/save_config.sh
```
- create the file with your passphrase and ensure it is only readable by root
```
cd /mnt/my_pool/my_dataset/scripts
touch save_config.pass
chmod 600 save_config.pass
chown root:wheel save_config.pass
```
- type in your password in the created pass file, either in nano/vi or using echo
```
echo 'my_super_pass' >save_config.pass
```

### EXAMPLES
- Exp 1: `save_config.sh`
    - will save the config file in default openssl encrypted format and store it in local folder `$target_mount_point/save_config`
    - the default openssl iterations count is used
    - `$target_mount_point` and `$filecheck_mount_point` variables must be set in script

- Exp 2: `save_config.sh -rar -gpg -ssl -tar`
    - will save the config files in encrypted openssl format, and also to rar, gpg and tar formats
    - `$target_mount_point` and `$filecheck_mount_point` variables must be set in script

- Exp 3: `save_config.sh -rar -ssl -iter 9000000 "/mnt/pool/tank/config" ".config.online"`
    - generate an openssl and a rar encrypted backups
    - the encrypted ssl file will have 900000 iterations
    - backup files are created in `/mnt/pool/tank/config` dataset under default `save_config` directory
    - script will check if `/mnt/pool/tank/config/.config.online` file or dir exists to ensure `/mnt/pool/tank/config` is mounted
    - the log files will be saved to /mnt/media/usb_key/logs
    - this will override any $filecheck_mount_point and $target_mount_point variables in script

- Exp 4: `save_config.sh -d -in encrypted-file.aes -iter 500000`
    - decrypt the `encrypted-file.aes`, assuming default ssl format but with a custom 500000 iterations count
    - output file is created in local directory under a subdirectory named `config.NNNN`

- Exp 5: `save_config.sh -d -rar -in /path/to/encrypted-config.rar -out /home/admin/config`
    - decrypt the rar `encrypted-config.rar` file and output to the directory /home/admin/config


### Manually encrypt file using GnuPG:
* gpg [options] --symmetric file_to_encrypt
```
gpg --cipher-algo aes256 --pinentry-mode loopback --passphrase-file "path_to_passfile" -o outputfile.gpg --symmetric file_to_encrypt
```
- [--pinentry-mode loopback] : needed in new gpg for supplying unencryped passwords on command line. Else, we get the error "problem with the agent: Invalid IPC response"


### Manually Decrypt OpenSSL aes files
* use this command to extract the contents to `decrypted_tarball.tar` file:
```
openssl enc -d -aes-256-cbc -md sha512 -pbkdf2 -iter "$openssl_iter" -salt -in "$target_backup_file" -pass file:pass.txt -out decrypted_tarball.tar
```
* you can extract tar contents to an existing "existing_extract_dir" folder:
```
openssl enc -d -aes-256-cbc -md sha512 -pbkdf2 -iter "$openssl_iter" -salt -in "$target_backup_file" -pass file:pass.txt | tar -xvf - -C "existing_extract_dir"
```
* or you can extract the tar contents to current folder
```
openssl enc -d -aes-256-cbc -md sha512 -pbkdf2 -iter "$openssl_iter" -salt -in "$target_backup_file" -pass file:pass.txt | tar -xvf -
```

### Manually Decrypt GnuPG gpg files
* run gpg command without any option, it will prompt for the password:
```
gpg backup_file.gpg
```

* or run with -d (decrypt), extract to a backup_file.tar file (-o option) and and pass in the passfile (--pinentry-mode loopback --passphrase-file file)
```
gpg --pinentry-mode loopback --passphrase-file "path_to_passfile" -o backup_file.tar -d backup_file.gpg
```

* or pipe tar command and directly extract and decrypt the backup file to local folder
```
gpg --pinentry-mode loopback --passphrase-file "path_to_passfile" -d backup_file.gpg | tar -xvf -
```

* or be prompted for the password:
```
gpg -d backup_file.gpg | tar -xvf -
```


### OpenSSL info
* Script uses AES256-CBC with default 900'000 SHA512 iterations and default random salt
* You can adjust iterations by changing the `openssl_iter` variable. Increase by a few tens of thouthands depending on your system
* higher values are more secure but slower. Too slow can expose your system to DOS attacks.
* It is more secure to have a long entropy password than increasing iterations with short passwords. Iterations only add a time penalty on dictionary attacks


### RAR info
* Rar software must be separately installed
* It offers a more widely spread GUI alternative to decrypt backup files


## pfsense_config.sh

### FUNCTIONS:
- Start inetd configured TFT server to start listening from remote pfsense script
- After a default 15mn delay, turn off the TFTP server
- Move any backup and log files from the TFTP server root to the destination target

### SYNOPSIS:
- Backups are performed and encrypted on the pfsense server using pfsense_send_config.sh script on pfsense
- The script pfsense_send_config.sh script on pfsense server sends the encrypted backups and logs on a schedule to the TrueNAS local TFTP Server
- This script starts the TFTP server, waits for 15 minutes, then turns off the TFTP Server
- Once TFT server is shutoff, script checks if config and log files are present on the TFT Server root directory
- It moves any config and log files to backup dataset under `$target_mount_point/pfsense_config`
- The target local directory `$target_mount_point` can be overriden either by command line or by editing in script variable `$target_mount_point`
- The name of the local subdirectory `pfsense_config` can be changed by editing in script variable `$backup_dir_name`
- This avoids using wget to access pfsense GUI to do the backup job.
- Using wget would need to provide a password to access backup/restore php file on the firewall (security concern)
- Scheduling the TFTP server and using a storage quota for the TFTP user makes the process secure

### SYNTAX
    script_name.sh [-options][Positional params]

#### USAGE
    script_name.sh [-options] [target_mount_point] [filecheck_mount_point]

#### Positional Parameters
    - target_mount_point   : Taget dataset/directory where the config files will be saved
    - filecheck_mount_point: Name of a file or directory in the root of $target_mount_point.
                             Used to verify that the target directory is properly mounted
                             `$target_mount_point/$filecheck_mount_point` must exist as a file or directory

- if omitted, you must edit below `$target_mount_point` and `$filecheck_mount_point` variables
- when provided by command line, they will override the 2 inscript variables
- backups are stored under `$target_mount_point/save_config` directory
- logs are created under a directory: `$target_mount_point/logs`

#### Options
    [-in|--source-dir]
    [-?|-help]

#### Options details
    -in|--source-dir : directory where the remote backup and log files were sent (the tftp root directory)

- if omitted, you must specify the `$source_dir` variable in script
- command line option will override `$source_dir` variable in script

### INSTALLATION
- setup the pfsense_send_config.sh script on pfsense as in the script/readme files
- create a unix data set `/pool/data/tftp` that will be the root of teh tftp server
- create a user:group `tftp:tftp`
- set `rwx` permissions for both user and group `tftp:tftp` on `/pool/data/tftp`, public permissions should be left unset
- setupt the TFTP service in TrueNAS GUI, but do not enable "auto-start"
- the TFTP service root directory should be the unix dataset we created: `/pool/data/tftp`
- the user `tftp` must be the user specified in the TFTP service
- optionally, edit the scrip variable `$source_dir` and set it to `/pool/data/tftp`
- setup the target dataset/folder: exp: `/pool/data/backups`
- create a file or folder called `.share.online` under `/pool/data/backups`
- schedule the script to run after the pfsense backup script using
- `bash pfsense_config.sh -in "/pool/data/tftp" "/pool/data/backups" ".share.online"`
- script will start the TFTP server, wait, stop the TFTP server
- after the TFTP server is stopped, backup files are moved to `/pool/data/backups/pfsense_config` directory
- logs are moved to `/pool/data/backups/logs` directory

### EXAMPLES
- Exp 1: `pfsense_config.sh -in /pool/data/tftp`
    - move the config and log files from `/pool/data/tftp` to target directory defined in script `$target_mount_point`
    - the file/dir `$target_mount_point/$filecheck_mount_point` must exist
- Exp 2: `pfsense_config.sh /mnt/tank/dataset .online.dataset -in /pool/data/tftp`
    - check if target dataset is online using the file/dir `/mnt/tank/dataset/.online.dataset`
    - move the config and log files from `/pool/data/tftp` to `/mnt/tank/dataset`


## pfsense_send_config.sh
#### !!! This script runs in the pfsense Server under root and sh POSIX shell !!!

### FUNCTIONS:
- Backup pfsense config file and optionally send it to a remote TFTP server
  + config files are encrypted in openssl with a pfsense compatible format that can be restored from the GUI
  + config files can also be encrypted using rar, gpg or stored as non encrypted tar
- Decrypt/Extract an openssl, rar, gpg or tar config file

### SYNOPSIS:
- Backups are performed and encrypted on the pfsense server
- The backups and logs are stored locally on the pfsense server
- The default storage locations for backup and log files are respectively `$target_mount_point/save_config` and `$target_mount_point/logs` directories
- Default paths defined in script are respectively for logs and backups `/root/pfsense_send_config` and `/root/logs`
- The target local directory `$target_mount_point` can be overriden either by command line or by editing in script variable `$target_mount_point`
- The name of the local subdirectory `pfsense_send_config` can be changed by editing in script variable `$backup_dir_name`

- If the `$remote_host` variable is set in script or by `-host` option, the backup and log files are MOVED to a remote TFTP Server
- Script will wait 15mn for the remote TFTP server to be online. The delay can be changed by editing the variables nmap_sleep and nmap_retry
- If the TFTP remote host is offline, backup and log files will be uploaded on next script run if the remote host is specified
- If the `$remote_host` variable is not set in script or by command options, upload to a remote server is skipped
- If the `-u|--upload-only` option is used, script will skip backup and only try to upload any previous backups and logs
- If the `-b|--backup-only|--no-upload` option is used, skip upload

- By default, an openssl aes256 encryped backup file is generated
- The backup file is by default an encrypted xml compatible pfsense restore from GUI
- Optionally, encrypted rar5 or gpg files can be generated or even a non compressed tar file
- Multiple output formats can be specified at the same time
- If no file format is specified, script will assume the openssl encryption as default
- This default file format can be changed by editing in script value `$default_encryption`

- Upload is done using curl locally. This avoids running wget from a remote host to access pfsense GUI to do the backup job.
- using wget/ssh from a remote server to access backup/restore function in the firewall, would expose a pfsense admin priviledged user/password on a remote server
- more options like using scp to ssh into a remote host, or curl sftp are left to the user developement if needed

- Decrypting backup files is done with the `-d|--decrypt` option, associated with -in option
- Optional decrypting options are -out (output directory) and any input file format option (-ssl|-rar|-gpg|-tar)
- See below examples for how to decrypt

### SYNTAX
    script_name.sh [-options][Positional params]

### USAGE
    script_name.sh [-options] [target_mount_point] [filecheck_mount_point]

#### Positional Parameters
    - target_mount_point   : Taget dataset/directory where the config files will be saved
    - filecheck_mount_point: Name of a file or directory in the root of $target_mount_point.
                             Used to verify that the target directory is properly mounted
                             `$target_mount_point/$filecheck_mount_point` must exist as a file or directory

- if omitted, you must edit below `$target_mount_point` and `$filecheck_mount_point` variables
- when provided by command line, they will override the 2 inscript variables
- backups are stored under `$target_mount_point/save_config` directory
- logs are created under a directory: `$target_mount_point/logs`

#### Options
    [-ssl|--ssl-encryption][-rar|--rar-encryption][-gpg|--gpg-encryption]
    [-tar|--unencrypted-tar][-iter|--iterations-count]
    [-?|-help]

#### Decrypt options:
    [-d|--decrypt][-in|--input-file][-out|--out-dir][one encryption option][-iter|--iterations-count]

#### Upload options:
    [-host|--remote-host][-p|--port][-u|--upload-only][-b|--backup-only|--no-upload]

#### Options details
    -ssl|--ssl-encryption    : generate an openssl encrypted backup
    -rar|--rar-encryption    : generate a RAR5 AES256 encrypted backup. You must install rar binary
    -gpg|--gpg-encryption    : generate a GnuPG AES256 encrypted backup (GPG)
    -tar|--unencrypted-tar   : generate a tar file with no encryption, strongly not recommended.
                               Will generate a warning to stderr
    -iter|--iterations-count : set a custom iterations count, overrides `$openssl_iter` variable
                               by default, if not set by options and `$openssl_iter` is kept as empty string in script,
                               it will use default openssl value, compatible with pfsense GUI encryption
    -d|--decrypt             : decrypt mode
    -in|--input-file         : file to decrypt
    -out|--out-dir           : directory where uncrypted files will be extracted.
                               if omitted, extracts to a `config.NNNN` directory created in local folder
    -host|--remote-host      : the remote tftp server to which files are sent. Overrides `$remote_host` variable
    -p|--port                : the remote tftp server port. Overrides `$remote_port` variable
    -u|--upload-only         : only upload previous backup and log files without creating a new backup
    -b|--backup-only|--no-upload : only backup, do not try to upload to defined `$remote_port`

- if no encryption option is specified, use default encryption set in variable `$default_encryption`
- if no remote host is specified by command line and `$remote_port` variable is empty, equivalent to `--backup-only`

### INSTALLATION:
- SSH into pfsense
```
mkdir /root/scripts
chown root:wheel /root/scripts
chmod 700 /root/scripts
```
- pfSense GUI: Diagnostics / Command Prompt / Upload File
- upload the pfsense_send_config.sh script from the GUI dialog
- Back in the CLI shell
```
mv /tmp/pfsense_send_config.sh /root/scripts/
chown root:wheel /root/scripts/pfsense_send_config.sh
chmod 600 /root/scripts/pfsense_send_config.sh
ee /root/scripts/pfsense_send_config.pass
```
- type in your password in the ee editor, in a single line, Type Esc and Save
- optional: install cron package from the GUI to schedule the script
- optional: for uploading to remote server: install `nmap` package from the GUI
- optional: for uploading to remote server: enable a firewall rule to allow traffic to/from the remote server
- optional: for rar encryption, copy the `rar` binary and `rarreg.key` files in `/root/bin` and `/root` respectively
- optional: for gpg encryption, install the gnuppg package
- check the script options to run in backup only mode, backup and upload modes or upload only mode

### EXAMPLES:
- Exp 1: `pfsense_send_config.sh`
    - will save the config file in openssl encrypted format and store it in local folder '$target_mount_point/pfsense_send_config'
    - the encrypted xml is compatible with restore from pfsense GUI
    - '$target_mount_point' and '$filecheck_mount_point' variables must be set in script
    - default is '/root/pfsense_send_config' and the folder '/root/scripts' must exist
    - if remote_host and remote_port variables are specified in script, it will move backups and logs to the specified TFTP server

- Exp 2: `pfsense_send_config.sh -host truenas.local -rar -gpg -ssl -tar`
    - will save the config files in pfsense compatible xml encrypted openssl format, and also to rar, gpg and tar formats
    - config and log files are then moved to the tftp server `truenas.local` on default port 69

- Exp 3: `pfsense_send_config.sh -host 192.168.30.30/config -p 750`
    - will save the config file as a pfsense compatible openssl encrypted file
    - it will move the backup and logs to the tftp server `192.168.30.30/config/` on port 750

- Exp 4: `pfsense_send_config.sh -host truenas.local -u`
    - No backup files will be created
    - Any previous backup and log files will be moved to the tftp server `truenas.local` on default port 69

- Exp 5: `pfsense_send_config.sh -host 192.168.30.30 -rar -ssl -iter 9000000 /mnt/media/usb_key .pfsense.key`
    - suppose we want to save the backups and logs on an USB key mounted in pfsense under the directory /mnt/media/usb_key
    - this command will save the config files as both an encrypted xml and rar format
    - the encrypted ssl file will have 900000 iterations (you cannot restore it using pfsense GUI)
    - script will check for the existance of a file or directory named /mnt/media/usb_key/.pfsense.key to ensure the target path is mounted
    - the config files will be saved to local folder /mnt/media/usb_key/pfsense_send_config
    - the log files will be saved to /mnt/media/usb_key/logs
    - config and log files will be moved to the tftp server `192.168.30.30` on defaukt port 69

- Exp 6: `pfsense_send_config.sh -d -in encrypted-file.xml -iter 500000`
    - decrypt the 'encrypted-file.xml', assuming default ssl format but with a custom 500000 iterations count
    - output file is created in local directory under a subdirectory named 'config.NNNN'

- Exp 7: `pfsense_send_config.sh -d -rar -in /path/to/encrypted-config.rar -out /home/admin/config`
    - decrypt the rar 'encrypted-config.rar' file and output to the directory /home/admin/config