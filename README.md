# True NAS Scripts

## save_config.sh

Backup TrueNAS/FreeNAS configuration database and password secret encryption files (storage encryption keys)

* Script must be started as root !!
* Script can be run without editing and only by supplying script arguments on command line
* When started without editing target path, only the two `target_mount_point` and `filecheck_mount_point` parameters are needed
* OPTIONAL: editing >>XXXX <<XXXX code parts in top of script. Read in-script comments for a detailed help
* When using encryption, script doesn't store at anytime any unencrypted copy of the password file
* Only a temporary file of the config databse file (not the passwords) is created in a folder with root:wheel only access
* The temporary database file is deleted after execution
* When using no encryption, script will always issue a warning to stderr, causing an alert if script is scheduled through a cronjob task

**Installation**
* think the dataset where you will copy the script, ideally to a unix dataset (not windows SMB)
exp: ```/mnt/my_pool/my_dataset```

* SSH / shell into TrueNAS as root

* create a directory to hold your scripts and ensure it can only be read by root to prevent access to your passwords
exp:
```mkdir /mnt/my_pool/my_dataset/scripts
chmod 700 scripts
chown root:wheel scripts
```

* copy the save_config.sh to the scripts directory and ensure it can only be executed by root
```cp save_config.sh /mnt/my_pool/my_dataset/scripts/
chmod 700 /mnt/my_pool/my_dataset/scripts/save_config.sh
chown root:wheel /mnt/my_pool/my_dataset/scripts/save_config.sh
```

* create the file with your passphrase and ensure it is only readable by root
```cd /mnt/my_pool/my_dataset/scripts
touch save_config.pass
chmod 600 save_config.pass
chown root:wheel save_config.pass
```

* type in your password in the created pass file, either in nano/vi or using echo
```echo 'my_super_pass >save_config.pass```


**Syntax :**

```script_name.sh [Options] [Positional params]```


**Usage :**

```script_name.sh [-rar|-ssl|-no-enc] [target_mount_point] [filecheck_mount_point]```

**Positional parameters :**
* target_mount_point   : taget dataset/directory where the config files will be saved under a created subdir called 'save_config'
* filecheck_mount_point: name of a file or directory that must be in the specified 'target_mount_point'
it ensures that the target path is properly mounted before doing a backup job
* if omitted, you must edit below 'target_mount_point' and 'filecheck_mount_point' variables
* when provided by command line, they will override the 2 inscript variables

**Option flags**
* ```-rar|--rar-encryption flag``` : use proprietary RAR5 AES256 encryption
* ```-ssl|--openssl-encryption flag``` : use OpenSSL AES256-CBC SHA512 PBKDF2 iterations and salt encryption
* ```-no-enc|--no-encryption flag``` : tar file with no encryption, strongly not recommended. Will generate a warning to stderr

**Expample 1** 
```save_config.sh "/mnt/pool/tank/config" ".config.online"```
* backup config file and encryption keys to /mnt/pool/tank/config dataset
* ensure that the dataset is properly mounted by checking if '.config.online' file/dir exists in root of the specified dataset
* default to openssl encryption

**Expample 2**
```save_config.sh -rar```
* no arguments are provided: backup config file and encryption key to default in-script path $target_mount_point
* ensure that $target_mount_point is properly mounted by checking for existance of the file/dir $filecheck_mount_point
* use optional rar5 encryption (you must install rar software)

**Expample 3**
```save_config.sh --no-encryption "/mnt/pool/tank/config" ".config.online"```
* backup config file and encryption keys to /mnt/pool/tank/config dataset
* ensure that the dataset is properly mounted by checking if '.config.online' file/dir exists in root of the specified dataset
* use no encryption

**To decrypt OpenSSL aes files**
* use this command to extract the contents to 'decrypted_tarball.tar' file:
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


**OpenSSL info**
* Script uses AES256-CBC with default 100'000 SHA512 iterations and default random salt
* You can adjust iterations by changing the `openssl_iter` variable. Increase by a few tens of thouthands depending on your system
* higher values are more secure but slower. Too slow can expose your system to DOS attacks.
* It is more secure to have a long entropy password than increasing iterations with short passwords. Iterations only add a time penalty on dictionary attacks


**RAR info**
* Rar software must be separately installed
* It offers a more widely spread GUI alternative to decrypt backup files