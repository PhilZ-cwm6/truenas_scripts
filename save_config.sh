#!/bin/bash

# !!! THIS SCRIPT MUST RUN ON THE TRUENAS MAIN HOST, NOT A JAIL !!!
# !!! Started with root priviledges !!!

# SpellCheck validated at https://www.shellcheck.net/
# - no warnings

# Exit on unset variables (-u), return error if any command fails in a pipe (-o pipefail)
# -f: we need globbing in the "for file in" curl loop
# -e: we do not want to exit on each error, because errors are managed in script and logged
# with -u: check if an arg is set using [ -n "${2:-}" ], that is expand to empty string if $2 is unset
set -u -o pipefail

# Script version
version=1.3.4

: <<'README.MD'
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
README.MD

#  ** Editable paths: >>XXXX <<XXXX **
#***************************************

# Define the backup and logs local target share/dataset
# - target_mount_point: mount point target dataset or directory relative to the main freeBSD host
# - filecheck_mount_point: name of a file or directory in the root of $target_mount_point. Used to verify that the target directory is properly mounted
# >>XXXX
target_mount_point="/mnt/main_data/tank/settings"
filecheck_mount_point=".share.online"
# <<XXXX

# Name of the directory where backups are stored
# - directory will be created under $target_mount_point
# >>XXXX
backup_dir_name="save_config"
# <<XXXX

# Name of the temp directory (used only for the sqlite3 backup)
# >>XXXX
tmp_dir="/root/tmp/$backup_dir_name"
# <<XXXX


#  ** BELOW  >>XXXX <<XXXX editable paths are optional ! **
#************************************************************

# Set log file names
# >>XXXX
log_file_name="$backup_dir_name.log" # holds stdout and stderr
log_file_name_stderr="__ERROR__$log_file_name" # only stderr
# <<XXXX

# Option to prune archive files older than x days
# If you manually move an archive file to the target subfolder 'archive_dir_name', it will be excluded from pruning
# - keep_days: max days before deleting backup
# - archive_dir_name: dir name where backups will not be pruned if older than $keep_days
# >>XXXX
keep_days=180
archive_dir_name="keep"
# <<XXXX

# Script path and file name: used for password file name
script_path=$(dirname "$0")
script_name=$(basename "$0")

# Backup Password file path: the path for a the file containing the password for the target backup when using encryption
# - the password file is in the same folder as this script file
# - the password file name: same as the script file name, with last extension replaced by .pass
# - Edit only if password file name or path needs to be changed
# >>XXXX
pass_file_path="$script_path"
pass_file_name="${script_name%.*}.pass" # scriptname.sh becomes scriptname
# <<XXXX
pass_file="$pass_file_path/$pass_file_name"

# Paths where rar command is installed
# >>XXXX
# Paths where rar command is installed
#  - look first in default rar install path /usr/local/bin/rar
#  - then in our custom "~/bin/rar" paths for root and admin users
# >>XXXX
admin_user_home=$(grep ^admin: /etc/passwd | cut -d: -f6)
rar_paths=(
    "/usr/local/bin/rar"
    "/root/bin/rar"
    "$admin_user_home/bin/rar"
)
# <<XXXX
rar=""
for rarbin in "${rar_paths[@]}"; do
    [ -f "$rarbin" ] && rar="$rarbin" && break
done
# <<XXXX

# Path where gpg command is installed
# >>XXXX
gpg="/usr/local/bin/gpg"
# <<XXXX

# Binary paths
# Run 'command -v openssl' to properly set the paths, if they change in a freeBSD release
# >>XXXX
openssl="/usr/bin/openssl"
grep="/usr/bin/grep"
#nmap="/usr/local/bin/nmap"
mkdir="/bin/mkdir"
sed="/usr/bin/sed"
chown="/usr/sbin/chown"
chmod="/bin/chmod"
touch="/usr/bin/touch"
#sleep="/bin/sleep"
#curl="/usr/local/bin/curl"
tar="/usr/bin/tar"
#perl="/usr/local/bin/perl"
#tr="/usr/bin/tr"
#service="/usr/sbin/service"
#cp="/bin/cp"
find="/usr/bin/find"
rm="/bin/rm"
#mv="/bin/mv"
tee="/usr/bin/tee"

# Array with all binary paths to test
# - rar and gpg are optional and tested before operations
binary_paths=( "$openssl" "$grep" "$mkdir" "$sed" "$chown" "$chmod" "$touch" "$tar" "$find" "$rm" "$tee" )
# <<XXXX

# Backup source files
# >>XXXX
# - password file to backup
pwenc_dir="/data"
pwenc_file="pwenc_secret"

# - config file databse to backup
config_db_dir="/data"
config_db_name="freenas-v1.db"
# <<XXXX

# Encryption defaults
# - openssl_iter: see below section for details
# - default_encryption: any of ssl|rar|gpg|tar
#   + if no encryption option is defined by command line, use this encryption mode
#   + if set to empty or non valid value, and no file format is set by command line, script will error
# >>XXXX
openssl_iter="900000"
default_encryption="ssl" # allowed values: ssl,rar,gpg,tar
# <<XXXX


#  ** NO FURTHER EDITS ARE NEEDED BELOW **
#*******************************************

# Global variables for the functions
# - target_dir: directory path where the backup files will be stored ($target_mount_point/$backup_dir_name)
# - log_path: directory path where log files will be stored ($target_mount_point/logs)
# - log_file: path to stdout+stderr log file ($log_path/$log_file_name)
# - log_file_stderr: path to stderr log file ($log_path/$log_file_name_stderr)
declare target_dir
declare log_path
declare log_file
declare log_file_stderr
declare -a POSITIONAL_PARAMS # any other arguments without "-" prefix

# Encryption option settings.
# - If none is specified, use default output format specified in $default_encryption variable
# - If set here to true, they cannot be toggled off by command line option
# - openssl_crypt [-ssl|--ssl-encryption]:
#   + generate an encrypted openssl backup file
# - openssl_iter [-iter|--iterations-count]: an integer
#   + pbkdf2 iterations: start with 300000 and increase depending on your CPU speed
#   + significant only if openssl_crypt is true
#   + set to empty string for default openssl pbkdf2 iteration count, currently of 10000 as per source code (too low, security wise)
# - rar_crypt [-rar|--rar-encryption]:
#   + generate a rar encrypted config file
# - gpg_crypt  [-gpg|--gpg-encryption]:
#   + generate a gpg encrypted config file
# - tar_no_crypt [-tar|--unencrypted-tar]:
#   + generate a non encrypted tar backup file, not recommended
openssl_crypt="false"
#openssl_iter="900000" # defined above in user custom options
rar_crypt="false"
gpg_crypt="false"
tar_no_crypt="false"

# Decrypt mode options
# - decrypt_mode [-d|--decrypt]
#   + set by command line options to decrypt a config file
# - input_file [-in|--input-file]
#   + path to config file to decrypt
# - out_path [-out|--out-dir]
#   + optional directory path to output decrypted config files
#   + if omitted, config files are extracted in current directory under a config.$$ subdirectory
#   + if out directory config.$$ already exists, decryption fails
# - openssl_iter [-iter|--iterations-count]
#   + cf. above, relevant if a custom iterations count was set to encrypt the xml file in ssl
# - -ssl, -rar, -gpg, -tar: to specify the encryption format of input file
# - if encryption format is not specified, use format set by $default_encryption variable
decrypt_mode="false"
input_file=""
out_path=""

# Return value from show_error() used to keep success/error code status of commands ($?)
# - used to exit on a command error after calling show_error() function
# - only modified by show_error() function
error_exit=0

# Config and log files are tagged with current date
curr_date=""

# Check if target and log paths are writable
# - create the log path so that we can log further script actions
# - output is not logged to a file but to stderr because the log file is not yet properly set !
# - errors echo: redirect stdout to stderr for cronjob error alert using show_error()
# - receives only positional arguments, not option flags (not used currently)
function setBackupPaths() {
    echo ""
    echo "Setting backup and log paths..."

: <<'DEBUG_CODE'
    i=0
    for arg in "$@"; do
        echo "arg $i = $arg"
        ((i++))
    done
    exit
DEBUG_CODE
    # Set the target and log paths.
    # - remove trailing / from target_mount_point name. Will not accept '/' as mount point
    target_mount_point="${target_mount_point%/}"

    # - ensure that target path was set either by command line args or in the script variables
    if [ -z "$target_mount_point" ] || [ -z "$filecheck_mount_point" ]; then
        show_error 1 "ERROR: syntax error" \
            "Script needs [target_mount_point] and [filecheck_mount_point] to be set by command line" \
            "Optionally, you can set the two variables in script"
        exit 1
    fi

    # - ensure the target mount point is properly mounted before creating any files on the target
    if [ ! -f "$target_mount_point/$filecheck_mount_point" ] && [ ! -d "$target_mount_point/$filecheck_mount_point" ]; then
        show_error 1 "ERROR: TARGET DIRECTORY NOT MOUNTED" \
            "ensure the directory is properly mounted and the below file/dir exists at its root:" \
            "$target_mount_point/$filecheck_mount_point"
        exit 1
    fi

    # - ensure the target directory is writable
    if [ ! -w "$target_mount_point" ]; then
        show_error 1 "ERROR: TARGET DIRECTORY NOT WRITABLE" \
            "ensure the directory is properly mounted and writable by current user:" \
            "$target_mount_point"
        exit 1
    fi

    # - set the target and log paths
    target_dir="$target_mount_point/$backup_dir_name"
    log_path="$target_mount_point/logs"
    log_file="$log_path/$log_file_name"
    log_file_stderr="$log_path/$log_file_name_stderr"

    # Create the log path
    # - it is needed to be able to use it as a redirect at the end of our script block
    # - it is important to preserve stderr so that the cron job can send an email with stderr if job fails
    $mkdir -p "$log_path" || show_error 1 "ERROR: Failed to create log directory: $log_path"
    [ "$error_exit" -eq 0 ] || exit "$error_exit"

    $touch "$log_file" || show_error 1 "ERROR: Failed to access log file: $log_file"
    [ "$error_exit" -eq 0 ] || exit "$error_exit"

    [ ! -e "$log_file_stderr" ] && $touch "$log_file_stderr"
    [ -f "$log_file_stderr" ] || show_error 1 "ERROR: Failed to access error log file: $log_file_stderr"
    [ "$error_exit" -eq 0 ] || exit "$error_exit"

    echo "> Target mountpoint : $target_mount_point/$filecheck_mount_point"
    echo "> Target directory  : $target_dir"
    echo "> Log file          : $log_file"
    echo "> Error log file    : $log_file_stderr"
    echo ""
}

# main(): only for config backup, not for decrypting
# ALL BELOW SCRIPT HAS ITS OUTPUT REDIRECTED TO LOG FILES DEFINED ABOVE
# $0 is always the script name and not the function name
function main() {
    # Print version
    echo ""
    echo "-------------------------------------------------"
    echo ""

    date
    printVersion

    # Create the backup target
    $mkdir -p "$target_dir" || show_error $? "ERROR creating target directory: $target_dir"
    [ "$error_exit" -eq 0 ] || exit "$error_exit"

    # chmod/chown the target_dir so that only root can access it
    # - left to the user to respect any SMB/ACLs existing permissions
    #$chown root:wheel "$target_dir" || show_error $? "ERROR setting owner of target directory: $target_dir"
    #[ "$error_exit" -eq 0 ] || exit "$error_exit"

    #$chmod 700 "$target_dir" || show_error $? "ERROR setting permissions of target directory: $target_dir"
    #[ "$error_exit" -eq 0 ] || exit "$error_exit"

    # Create the temp directory to store the sql database backup (the password file is never stored unencrypted anywhere)
    $mkdir -p "$tmp_dir" || show_error $? "ERROR creating temporary directory: $tmp_dir"
    [ "$error_exit" -eq 0 ] || exit "$error_exit"

    # chmod/chown the temp dir so that only root can access it
    $chmod 700 "$tmp_dir" || show_error $? "ERROR setting permissions of temp directory: $tmp_dir"
    [ "$error_exit" -eq 0 ] || exit "$error_exit"

    $chown root:wheel "$tmp_dir" || show_error $? "ERROR setting owner of temp directory: $tmp_dir"
    [ "$error_exit" -eq 0 ] || exit "$error_exit"

    echo ""
    echo "Starting config file and passwords backup"
    save_config
    rm_old_backups

    echo ""
    echo "Config file and encryption keys saved to $target_dir"
    echo "Log file: $log_file"
    echo "TrueNAS settings backup completed"

    date
    echo ""

} > >($tee -a "$log_file") 2> >($tee -a "$log_file_stderr" | $tee -a "$log_file" >&2)
    # 1rst tee writes {script block} STDOUT (} >) to a file + we preserve it on STDOUT
    # 2nd tee writes {script block} STDERR (2>) to a different file + we redirect 2nd tee STDOUT (actually {script block} STDERR) to 3rd tee
    # 3rd tee writes STDERR to our main log file so that it contains all the screen equivalent output (stdout + stderr)
    # 3d tee redirects its STDOUT back to STDERR so that we preserve {script block} STDERR on the terminal STDERR

# Backup TrueNAS settings
function save_config() {
    echo ""
    echo "---Generating backup file name---"

    # Get current OS version (used to set the target backup file name)
    # - output is in the form of: TrueNAS-12.0-U5.1 (6c639bd48a)
    # - include into () to transform the string into an array of space separated strings
    truenas_version=()
    IFS=" " read -r -a truenas_version < <( grep -i truenas /etc/version )
    if [ ${#truenas_version[@]} -eq 0 ]; then
        IFS=" " read -r -a truenas_version < <( grep -i freenas /etc/version )
    fi

    if [ ${#truenas_version[@]} -eq 0 ] || [ -z "${truenas_version[0]}" ]; then
        truenas_version[0]="UNKNOWN"
        show_error 0 "> WARNING: could not find the current OS version !!"
    fi

    # Form a unique, timestamped filename for the backup configuration database and tarball
    P1=$(hostname -s)
    P2="${truenas_version[0]}" # we only keep the part: TrueNAS-12.0-U5.1 and omit the build code (6c639bd48a)
    P3=$(date +%Y%m%d%H%M%S)
    backup_archive_name="$P1"-"$P2"-"$P3"

    # Note: changing file extensions will not need code editing
    target_ssl="$target_dir/$backup_archive_name.aes"
    target_rar="$target_dir/$backup_archive_name.rar"
    target_gpg="$target_dir/$backup_archive_name.gpg"
    target_tar="$target_dir/$backup_archive_name.tar"

    echo "> Backup filename: $backup_archive_name"

    # Delete any old temporary file:
    echo ""
    echo "---Deleting old temporary files---"
    #find "$tmp_dir" -type f -name '*.db' -print
    $find "$tmp_dir" -type f -name '*.db' -exec $rm -v {} \;

    # Check if source file to backup exists and can be read
    # - passwords file
    if ! [ -f "$pwenc_dir/$pwenc_file" ] || ! [ -r "$pwenc_dir/$pwenc_file" ]; then
        show_error 1 "ERROR: Cannot find/read password file: $pwenc_dir/$pwenc_file"
        [ "$error_exit" -eq 0 ] || exit "$error_exit"
    fi

    # - config database file to backup
    if ! [ -f "$config_db_dir/$config_db_name" ] || ! [ -r "$config_db_dir/$config_db_name" ]; then
        show_error 1 "ERROR: Cannot find/read Config file database: $config_db_dir/$config_db_name"
        [ "$error_exit" -eq 0 ] || exit "$error_exit"
    fi

    # Backup the config database file to the temporary directory
    echo ""
    echo "---Creating temporary backup of sqlite database---"

    /usr/local/bin/sqlite3 "$config_db_dir/$config_db_name" ".backup main '$tmp_dir/$config_db_name'"

    command_status=$?
    [ "$command_status" -eq 0 ] || show_error "$command_status" "ERROR backing up sqlite database"
    [ "$error_exit" -eq 0 ] || exit "$error_exit"

    echo ""
    echo "> Config database saved to $tmp_dir/$config_db_name"

    # Check integrity of the sqlite3 backup databse
    echo ""
    echo "> Checking saved database file integrity---"

    command_status=$(/usr/local/bin/sqlite3 "$tmp_dir/$config_db_name" "pragma integrity_check;")

    [ "$command_status" = "ok" ] || show_error 1 "> ERROR: config database backup file was corrupted !"
    [ "$error_exit" -eq 0 ] || exit "$error_exit"

    echo "> Config database integrity check ok"

    # Archieve the config database and password file
    echo ""
    echo "---Backing up config and password files---"

    [ "$openssl_crypt" = "true" ] && save_openssl
    [ "$rar_crypt" = "true" ] && save_rar
    [ "$gpg_crypt" = "true" ] && save_gpg
    [ "$tar_no_crypt" = "true" ] && save_decrypted

    [ "$openssl_crypt" != "true" ] && [ "$rar_crypt" != "true" ] \
        && [ "$gpg_crypt" != "true" ] && [ "$tar_no_crypt" != "true" ] \
        && show_error 1 "ERROR: Internal ERROR: save_config(): No output format provided !"

    [ "$error_exit" -eq 0 ] || exit "$error_exit"

    echo ""
    echo "> Backup config files saved to $target_dir"
}

# OpenSSL encrypted backup file
function save_openssl() {
    echo ""
    echo "> Openssl backup to $target_dir"

    # Get the encryption password and assign it to $password
    # - for openssl, we only need to check if pass file exists
    #password=""
    get_password

    # Check iterations count if set in script or by command line option
    # - case iter_count is empty string: use default openssl command iterations count
    if [ -n "$openssl_iter" ]; then
        # ensure the specified iter count is an integer
        is_integer "$openssl_iter" || show_error 1 "ERROR: iteration count invalid option: $openssl_iter"
        [ "$error_exit" -eq 0 ] || exit "$error_exit"
    fi

    # Encrypted openssl tarball
    # ${openssl_iter:+-iter}: If $openssl_iter is null or unset, nothing is substituted, otherwise the expansion of '-iter' word is substituted.
    # - using "$openssl_iter" causes openssl error 'empty string option'
    # - instead of using $openssl_iter unquoted, we use 'unquoted expansion with an alternate value'
    #   it allows the unquoted empty default value without error, while the non empty $openssl_iter is quoted
    #   https://github.com/koalaman/shellcheck/wiki/SC2086
    $tar -cf - \
        -C "$pwenc_dir" "$pwenc_file" \
        -C "$tmp_dir" "$config_db_name" \
        | $openssl enc -e -aes-256-cbc -md sha512 -pbkdf2 ${openssl_iter:+-iter} ${openssl_iter:+"$openssl_iter"} -salt -pass file:"$pass_file" -out "$target_ssl"

    command_status=$?
    [ "$command_status" -eq 0 ] || show_error "$command_status" "ERROR creating openssl encrypted backup: $target_ssl"
    [ "$error_exit" -eq 0 ] || exit "$error_exit"

    echo "- File saved: $target_ssl"
}

# RAR encrypted backup file
function save_rar() {
    echo ""
    echo "> RAR backup to $target_dir"

    # Check if rar binary is available
    [ -f "$rar" ] || show_error 1 "ERROR: cannot find rar commad: $rar"
    [ "$error_exit" -eq 0 ] || exit "$error_exit"

    # Get the encryption password and assign it to $password
    password=""
    get_password

    # Encrypted rar5 tarball
    $tar -cf - \
        -C "$pwenc_dir" "$pwenc_file" \
        -C "$tmp_dir" "$config_db_name" \
        | $rar a -@ -rr10 -s- -ep -m3 -ma -p"$password" -ilog"$log_file_stderr" "$target_rar" -si"$backup_archive_name".tar | $sed -e 's/     .*OK/ OK/' -e 's/     .*100%/ 100%/'
          # we run two replace script iterations on the same command "-e", first to keep the last OK and second to keep the last 100%
          # do not use -ow to preserve ownership, since we're piping the input from tar and the rar will not find the input tar file

    command_status=$?
    [ "$command_status" -eq 0 ] || show_error "$command_status" "ERROR creating rar encrypted backup: $target_rar"
    [ "$error_exit" -eq 0 ] || exit "$error_exit"

    echo "- File saved: $target_rar"
}

# GnuPG encrypted backup file
function save_gpg() {
    echo ""
    echo "> GPG backup to $target_dir"

    # Check if gpg binary is available
    [ -f "$gpg" ] || show_error 1 "ERROR: cannot find gpg commad: $gpg"
    [ "$error_exit" -eq 0 ] || exit "$error_exit"

    # Get the encryption password and assign it to $password
    # - for gpg, we only need to check if pass file exists
    #password=""
    get_password

    # Encrypted GnuPG tarball
    $tar -cf - \
        -C "$pwenc_dir" "$pwenc_file" \
        -C "$tmp_dir" "$config_db_name" \
        | $gpg --cipher-algo aes256 --pinentry-mode loopback --passphrase-file "$pass_file" -o "$target_gpg" --symmetric
          # [--pinentry-mode loopback] : needed in new gpg for supplying unencryped passwords on command line. Else, we get the error "problem with the agent: Invalid IPC response"

    command_status=$?
    [ "$command_status" -eq 0 ] || show_error "$command_status" "ERROR creating gpg encrypted backup: $target_gpg"
    [ "$error_exit" -eq 0 ] || exit "$error_exit"

    echo "- File saved: $target_gpg"
}

# TAR non-encrypted backup file
function save_decrypted() {
    echo ""
    echo "> Non-encrypted backup to $target_dir"

    # Print warning to stderr
    show_error 0 "- WARNING: backup using no encryption..."

    # no encryption is selected, only create a tarball
    # freeBSD tar defaults verbose messages to stderr and always uses stdout as archive destination (pipe)
    # unlike some installers where tar only outputs archive to stdout if we specify '-' as filename or no "-f filename"
    # do not use verbose (tar -cvf), else stderr gets populated with filenames and cron job sends an error
    $tar -cf "$target_tar" \
        -C "$pwenc_dir" "$pwenc_file" \
        -C "$tmp_dir" "$config_db_name"

    command_status=$?
    [ "$command_status" -eq 0 ] || show_error "$command_status" "ERROR creating non-encrypted backup: $target_tar"
    [ "$error_exit" -eq 0 ] || exit "$error_exit"

    echo "- File saved: $target_tar"
}

# Decrypt config file
function decrypt_config() {
    echo ""
    echo "---Decrypting config files---"
    echo "> Input file: $input_file"

    # Check decryption options
    [ "$decrypt_mode" != "true" ] && show_error 1 "INTERNAL ERROR: decrypt_config(): decrypt_mode=$decrypt_mode"
    [ "$error_exit" -eq 0 ] || exit "$error_exit"

    [ -z "$input_file" ] && show_error 1 "INTERNAL ERROR: decrypt_config(): empty input_file"
    [ "$error_exit" -eq 0 ] || exit "$error_exit"

    # Check that there are no multiple decryption formats set to true
    count=0
    [ "$openssl_crypt" = "true" ] && count=$((count + 1))
    [ "$rar_crypt" = "true" ] && count=$((count + 1))
    [ "$gpg_crypt" = "true" ] && count=$((count + 1))
    [ "$tar_no_crypt" = "true" ] && count=$((count + 1))
    [ $count -ne 1 ] && show_error 1 "ERROR: Internal error: decrypt_config(): $count encryption formats specified"
    [ "$error_exit" -eq 0 ] || exit "$error_exit"

    if [ ! -f "$input_file" ] || ! [ -r "$input_file" ]; then 
        show_error 1 "ERROR: Cannot find/read input file: $input_file"
        [ "$error_exit" -eq 0 ] || exit "$error_exit"
    fi

    # If no output directory is specified, set one in local directory
    [ -z "$out_path" ] && out_path="config.$$"

    # Check if output directory exists
    [ -e "$out_path" ] && show_error 1 "ERROR: output directory already exists: $out_path" "Specify a different directory usinng -out dir_path"
    [ "$error_exit" -eq 0 ] || exit "$error_exit"

    # Create output directory
    $mkdir -p "$out_path"
    [ -d "$out_path" ] || show_error 1 "ERROR: Failed to create output directory: $out_path"
    [ "$error_exit" -eq 0 ] || exit "$error_exit"

    if [ "$openssl_crypt" = "true" ]; then extract_openssl
    elif [ "$rar_crypt" = "true" ]; then extract_rar
    elif [ "$gpg_crypt" = "true" ]; then extract_gpg
    elif [ "$tar_no_crypt" = "true" ]; then extract_tar
    else show_error 1 "ERROR: Internal error: decrypt_config(): input file format not specified"
    fi

    [ "$error_exit" -eq 0 ] || exit "$error_exit"
    
    echo "> Config file decrypted in $out_path"
    echo ""
}

function extract_openssl() {
    echo "> Decrypting openssl file to $out_path"
    echo ""

    # Get the encryption password and assign it to $password
    # - for openssl, we only need to check if pass file exists
    #password=""
    get_password

    # Check iterations count if set in script or by command line option
    # - case iter_count is empty string: use default openssl command iterations count
    if [ -n "$openssl_iter" ]; then
        # ensure the specified iter count is an integer
        is_integer "$openssl_iter" || show_error 1 "ERROR: iteration count invalid option: $openssl_iter"
        [ "$error_exit" -eq 0 ] || exit "$error_exit"
    fi

    # Decrypt config file
    $openssl enc -d -aes-256-cbc -salt -md sha512 -pbkdf2 ${openssl_iter:+-iter} ${openssl_iter:+"$openssl_iter"} -in "$input_file" -pass file:"$pass_file" | $tar -xvf - -C "$out_path"
    command_status=$?
    [ "$command_status" -eq 0 ] || show_error "$command_status" "ERROR: failed decrypting $input_file"
    [ "$error_exit" -eq 0 ] || exit "$error_exit"
}

function extract_rar() {
    echo "> Decrypting rar file to $out_path"
    echo ""

    # Check if rar binary is available
    [ -f "$rar" ] || show_error 1 "ERROR: cannot find rar commad: $rar"
    [ "$error_exit" -eq 0 ] || exit "$error_exit"

    # Get the encryption password and assign it to $password
    # - for openssl, we only need to check if pass file exists
    password=""
    get_password

    # Decrypt config file
    # - rar p: extract file to stdout
    # - -inul: do not print any message to stdout (only file is printed to stdout with 'p' command)
    $rar p -inul -p"$password" "$input_file" | $tar -xvf - -C "$out_path"

    command_status=$?
    [ "$command_status" -eq 0 ] || show_error "$command_status" "ERROR: failed decrypting $input_file"
    [ "$error_exit" -eq 0 ] || exit "$error_exit"
}

function extract_gpg() {
    echo "> Decrypting gpg file to $out_path"
    echo ""

    # Check if gpg binary is available
    [ -f "$gpg" ] || show_error 1 "ERROR: cannot find gpg commad: $gpg"
    [ "$error_exit" -eq 0 ] || exit "$error_exit"

    # Check if gpg binary is available
    [ -f "$gpg" ] || show_error 1 "ERROR: cannot find gpg commad: $gpg"
    [ "$error_exit" -eq 0 ] || exit "$error_exit"

    # Get the encryption password and assign it to $password
    # - for openssl, we only need to check if pass file exists
    #password=""
    get_password

    # Decrypt config file
    $gpg --pinentry-mode loopback --passphrase-file "$pass_file" -d "$input_file" | $tar -xvf - -C "$out_path"

    command_status=$?
    [ "$command_status" -eq 0 ] || show_error "$command_status" "ERROR: failed decrypting $input_file"
    [ "$error_exit" -eq 0 ] || exit "$error_exit"
}

function extract_tar() {
    echo "> Extracting tar file to $out_path"
    echo ""

    # Extract config file
    $tar -xvf "$input_file" -C "$out_path"

    command_status=$?
    [ "$command_status" -eq 0 ] || show_error "$command_status" "ERROR: failed extracting $input_file"
    [ "$error_exit" -eq 0 ] || exit "$error_exit"
}

# Remove files older than $keep_days except if in the directory $archive_dir_name
function rm_old_backups() {
    echo ""
    echo "---Pruning backups older than $keep_days days---"
    echo "> Searching $target_dir"

    #$find "$target_dir" -type f -not -path "*/$archive_dir_name/*" \( -name '*.aes' -o -name '*.rar' -o -name '*.gpg' -o -name '*.tar' \) -mtime +"$keep_days" -print
    $find "$target_dir" -type f -not -path "*/$archive_dir_name/*" \( -name '*.aes' -o -name '*.rar' -o -name '*.gpg' -o -name '*.tar' \) -mtime +"$keep_days" -exec $rm -v {} \;
}

# Check the password if encryption is set
function get_password() {
    #password=$(<"$pass_file") # bash only
    password=$(cat "$pass_file")
    [ -z "$password" ] && show_error 1 "ERROR: no password was set" "you must specify a password in $pass_file"
    [ "$error_exit" -eq 0 ] || exit "$error_exit"
}

# Check if a received arg is an integer (exclude -/+ signs)
function is_integer() {
    command_status=1
    [ $# -ne 1 ] && show_error 1 "ERROR: Internal error: is_integer() needs one argument"
    [ "$error_exit" -eq 0 ] || exit "$error_exit"

    # Bash only
    [[ "$1" =~ ^[0-9]+$ ]] && command_status=0 # is an integer

    return "$command_status"

: <<'DEBUG_CODE'
    # Posix compatible
    case "$1" in
        *[!0-9]*|'')
            # Not an integer
            return "$command_status"
            ;;
        *)
            # is a valid integer
            command_status=0
            return "$command_status"
            ;;
    esac
DEBUG_CODE
}

# Log passed args to stderr and preserve error code from caller
# - call syntax: show_error $? "error msg 1" "error message 2"...
# - after function call, use this line of code: [ "$error_exit" -eq 0 ] || exit "$error_exit"
#   this will exit with "$error_exit" code if previous command failed
# - we do not exit here else stderr gets flushed after the command prompt display
function show_error() {
    # $1 must be an integer value because it is used as a return/exit code
    error_exit="$1"
    curr_date=$(date)

    # Bash option:
    # if ! [[ "$error_exit" =~ ^[0-9]+$ ]]; then echo "ERROR: Not an integer"; done

    # Posix sh:
    case ${error_exit#[-+]} in
        *[!0-9]*|'')
            {
                echo "INTERNAL ERROR IN FUNCTION show_error()"
                echo "function arg1=$1"
                echo "expected: integer value for arg1"

                printf "!!!! %s !!!!\n" "$curr_date"
                echo ""
            } >&2
            exit 1 # fatal error, exit
            ;;
#       *)
#           echo it is a number;;
    esac

    # Ensure the function is called with at least two args and that there is an error message to display
    if [ "$#" -lt  2 ] || [ -z "$2" ]; then
        {
            echo "INTERNAL ERROR IN FUNCTION show_error()"
            echo "function arg2 not found or empty string"
            echo "expected arg2 to be a string with error message"

            printf "!!!! %s !!!!\n" "$curr_date"
            echo ""
        } >&2
        exit 1 # fatal error, exit
    fi

    # Print to stderr each arg (error message) in a separate line
    shift # $1 is now the first error message
    {
        for error_msg in "$@"; do
            echo "$error_msg"
        done

        printf "!!!! %s !!!!\n" "$curr_date"
        echo ""
    } >&2

    return "$error_exit" # preserves $? from failed command
}

# Check if binary paths are properly set
function checkBinaries() {
    err_msg=""
    for bin_path in "$@"; do
        suffix=", " # a separator between bad paths printed in our error message
        [ -z "$err_msg" ] && suffix=""
        [ -f "$bin_path" ] || err_msg="$err_msg$suffix$bin_path"
    done

    [ -z "$err_msg" ] || show_error 1  "ERROR: could not find commands: $err_msg" "Please fix the variables in script with the proper paths"
    [ "$error_exit" -eq 0 ] || exit "$error_exit"
}

# Process command line arguments
# - output is not logged to a file but to stderr because the log file is not yet properly set !
# - argument errors are sent to stderr, so that a cron job alert can be triggered even at this stage
function parseArguments() {
    # Args class count
    # Used to check if specific encryption options were set while the -d decrypt mode was specified
    pos_args=0 # positional args count
    enc_options=0 # encryption args count
    dec_options=0 # decryption args count

    # Posix sh:
    #while [ $# -ne 0 ]; do
    # Bash:
    while (( "$#" )); do
        case "$1" in # this will allow empty arguments !
            # Do not allow commands with following chars: &;({<>`|*
            *\&*|*\;*|*\(*|*\{*|*\<*|*\>*|*\`*|*\|*|*\**)
                show_error 1  "ERROR: non allowed chars in $1" "Usage: $script_name [-options] [target_mount_point] [filecheck_mount_point]"
                exit 1
                ;;
            -ssl|--ssl-encryption)
                openssl_crypt="true"
                enc_options=$((enc_options + 1))
                shift
                ;;
            -rar|--rar-encryption)
                rar_crypt="true"
                enc_options=$((enc_options + 1))
                shift
                ;;
            -gpg|--gpg-encryption)
                gpg_crypt="true"
                enc_options=$((enc_options + 1))
                shift
                ;;
            -tar|--unencrypted-tar)
                tar_no_crypt="true"
                enc_options=$((enc_options + 1))
                shift
                ;;
            -iter|--iterations-count)
                # First char of $str: $(printf %.1s "$str")
                if [ -n "${2:-}" ] && [ "$(printf %.1s "$2")" != "-" ]; then
                    is_integer "$2" || show_error 1 "ERROR: syntax error" "Iterations count must be a number" "Usage: $script_name [-options] [target_mount_point] [filecheck_mount_point]"
                    [ "$error_exit" -eq 0 ] || exit "$error_exit"

                    openssl_iter="$2"
                    shift 2
                else
                    show_error 1 "ERROR: Argument for $1 is missing" "Usage: $script_name [-options] [target_mount_point] [filecheck_mount_point]"
                    exit 1
                fi
                ;;
            -d|--decrypt)
                decrypt_mode="true"
                dec_options=$((dec_options + 1))
                shift
                ;;
            -in|--input-file)
                # First char of $str: $(printf %.1s "$str")
                if [ -n "${2:-}" ] && [ "$(printf %.1s "$2")" != "-" ]; then
                    input_file="$2"
                    dec_options=$((dec_options + 1))
                    shift 2
                else
                    show_error 1 "ERROR: Argument for $1 is missing" "Usage: $script_name [-options] [target_mount_point] [filecheck_mount_point]"
                    exit 1
                fi
                ;;
            -out|--out-dir)
                # First char of $str: $(printf %.1s "$str")
                if [ -n "${2:-}" ] && [ "$(printf %.1s "$2")" != "-" ]; then
                    out_path="$2"
                    dec_options=$((dec_options + 1))
                    shift 2
                else
                    show_error 1 "ERROR: Argument for $1 is missing" "Usage: $script_name [-options] [target_mount_point] [filecheck_mount_point]"
                    exit 1
                fi
                ;;
            -?|-help)
                printVersion
                exit
                ;;
            -*) # Unsupported flags
                show_error 1 "ERROR: Unsupported option $1" "Usage: $script_name [-options] [target_mount_point] [filecheck_mount_point]"
                exit 1
                ;;
            *) # A Positional arg: override default options
                [ -z "$1" ] && show_error 1 "ERROR: syntax error" "Do not use empty parameters !" "Usage: $script_name [-options] [target_mount_point] [filecheck_mount_point]"
                [ "$error_exit" -eq 0 ] || exit "$error_exit"

                pos_args=$((pos_args + 1))
                [ $pos_args -eq 1 ] && target_mount_point="$1"
                [ $pos_args -eq 2 ] && filecheck_mount_point="$1"

                [ $pos_args -gt 2 ] && show_error 1 "ERROR: syntax error" "Only two positional args are supported" "Usage: $script_name [-options] [target_mount_point] [filecheck_mount_point]"
                [ "$error_exit" -eq 0 ] || exit "$error_exit"

                # Bash:
                #preserve positional arguments in an array variable
                POSITIONAL_PARAMS+=("$1")
                shift
                ;;
        esac
    done

    # Bash:
    # Set positional arguments in their proper place
    set -- "${POSITIONAL_PARAMS[@]}"

    # Case backup mode AND no positional args were provided
    # - use default in script filecheck_mount_point and target_mount_point variables
    # - if they are empty, error on check in setBackupPaths()

    # Case only one positional parameter is provided
    if [ $pos_args -eq 1 ]; then
        show_error 1 "ERROR: syntax error" \
            "'target_mount_point' and 'filecheck_mount_point' cannot be used one without the other" \
            "Usage: $script_name [-options] [target_mount_point] [filecheck_mount_point]"

        [ "$error_exit" -eq 0 ] || exit "$error_exit"
    fi

    # Case more than two positional arguments:
    # - checked in above case:esac

    # Case no file format option is provided, either for encryption or decryption
    if [ $enc_options -eq 0 ]; then
        if [ "$default_encryption" = "ssl" ]; then  openssl_crypt="true"
        elif [ "$default_encryption" = "rar" ]; then  rar_crypt="true"
        elif [ "$default_encryption" = "gpg" ]; then  gpg_crypt="true"
        elif [ "$default_encryption" = "tar" ]; then  tar_no_crypt="true"
        else show_error 1 "ERROR: syntax error: No encryption option selected." \
                "Select at least one output format or define a default option in script" \
                "Usage: $script_name [-options] [target_mount_point] [filecheck_mount_point]"
        fi

        [ "$error_exit" -eq 0 ] || exit "$error_exit"

        echo "> Using default file format: $default_encryption"
        echo ""

        enc_options=$((enc_options + 1))
    fi

    # Some useless, non harmful associations in backup/decrypt modes
    # -iter without -ssl in backup mode: will be ignored

    # Specific encryption/decryption options rules
    if [ $dec_options -ne 0 ]; then
        # decryption option must be used (-d|--decrypt)
        [ "$decrypt_mode" != "true" ] && show_error 1 "ERROR: syntax error" "in/out options need --decrypt option" "Usage: $script_name [-options] [target_mount_point] [filecheck_mount_point]"
        [ "$error_exit" -eq 0 ] || exit "$error_exit"

        # input file is mandatory
        [ -z "$input_file" ] && show_error 1 "ERROR: syntax error: Missing input file to decrypt" "Usage: $script_name [-options] [target_mount_point] [filecheck_mount_point]"
        [ "$error_exit" -eq 0 ] || exit "$error_exit"

        # positional args are not allowed
        [ $pos_args -ne 0 ] && show_error 1 "ERROR: syntax error: Positional arguments cannot be used in decryption mode" "Usage: $script_name [-options] [target_mount_point] [filecheck_mount_point]"
        [ "$error_exit" -eq 0 ] || exit "$error_exit"

        # only one input format can be specified
        # note: if more than a default format option was altered in script, check it in decrypt_config()
        [ $enc_options -gt 1 ] && show_error 1 "ERROR: syntax error: Only one input format can be specified for decryption" "Usage: $script_name [-options] [target_mount_point] [filecheck_mount_point]"
        [ "$error_exit" -eq 0 ] || exit "$error_exit"
    #else
        # backup mode
    fi

    # Show effective parameters
    echo "> Using below options:"
    echo "  - target mount point: $target_mount_point"
    echo "  - mount point check : $filecheck_mount_point"
    echo "  - openssl encryption: $openssl_crypt"
    echo "  - rar encryption    : $rar_crypt"
    echo "  - gpg encryption    : $gpg_crypt"
    echo "  - tar compression   : $tar_no_crypt"
    echo "  - custom iterations : $openssl_iter"
    echo "  - decrypt mode      : $decrypt_mode"
    echo "    + input file      : $input_file"
    echo "    + output directory: $out_path"
}

# Print version and syntax
function printVersion() {
    echo ""
    echo "$script_name version $version"
    echo "https://github.com/PhilZ-cwm6/truenas_scripts"
    echo "usage: $script_name.sh [-options] [target_mount_point] [filecheck_mount_point]"
    echo "- target_mount_point   : target dataset/directory for the backup"
    echo "- filecheck_mount_point: file/dir in 'target_mount_point' to ensure that the target is properly mounted"
    echo "- Options : [-ssl|--ssl-encryption][-rar|--rar-encryption][-gpg|--gpg-encryption]"
    echo "            [-tar|--unencrypted-tar][-iter|--iterations-count]"
    echo "            [-?|-help]"
    echo "- Decrypt : [-d|--decrypt][-in|--input-file][-out|--out-dir][encryption option]"
    echo "- Defaults: backup using openSSL encryption to in-script path 'target_mount_point'"
    echo "            format=$default_encryption | target root=$target_mount_point"
}

# Parse script arguments
parseArguments "$@" || show_error $? "ERROR parsing script arguments"
[ "$error_exit" -eq 0 ] || exit "$error_exit"

# Check if all the binary paths are properly set
checkBinaries "${binary_paths[@]}"

# If we are decrypting a config file, no logging or other tasks are processed
if [ "$decrypt_mode" = "true" ]; then
    decrypt_config
    exit $?
fi

# Check if target and log paths are mounted and writable
# - preserve positional params args (not used currently)
setBackupPaths "$@" || show_error $? "ERROR setting backup and log paths"
[ "$error_exit" -eq 0 ] || exit "$error_exit"

# Start script main function for backup of config files
# - we redirect stdout to $log_file AND terminal
# - we redirect stderr to $log_file_stderr, $log_file AND terminal
# - terminal and $log_file have both stdout and stderr, while $log_file_stderr only holds stderr
main "$@"; exit
