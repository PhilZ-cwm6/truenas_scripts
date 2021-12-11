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

- Decrypting backup files is done with the "-d" option, associated with -in option
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
    -ssl|--ssl-encryption   : generate an openssl encrypted backup
    -rar|--rar-encryption   : generate a RAR5 AES256 encrypted backup. You must install rar binary
    -gpg|--gpg-encryption   : generate a GnuPG AES256 encrypted backup (GPG)
    -tar|--unencrypted-tar  : generate a tar file with no encryption, strongly not recommended.
                              Will generate a warning to stderr
    -iter|--iterations-count: set a custom iterations count, overrides `$openssl_iter` variable
    -d|--decrypt            : decrypt mode
    -in|--input-file        : file to decrypt
    -out|--out-dir          : directory where uncrypted files will be extracted.
                              If omitted, extracts to a `config.NNNN` directory created in local folder

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
```
gpg --cipher-algo aes256 --pinentry-mode loopback --passphrase-file "path_to_passfile" -o outputfile.gpg --symmetric file_to_encrypt
```
- [--pinentry-mode loopback] : needed in new gpg for supplying unencryped passwords on command line. Else, we get the error "problem with the agent: Invalid IPC response"
- gpg [options] --symmetric file_to_encrypt
- gpg --cipher-algo aes256 --pinentry-mode loopback --passphrase-file "path_to_passfile" -o outputfile.gpg --symmetric file_to_encrypt

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