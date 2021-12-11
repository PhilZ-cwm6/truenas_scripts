#!/bin/sh

# !!! THIS SCRIPT MUST RUN ON THE PFSENSE SERVER IN SH SHELL !!!
# !!! Started with root priviledges !!!

# SpellCheck validated at https://www.shellcheck.net/
# -o pipefail: is properly supported on the pfsense sh shell, unlike POSIX standard !
# - perl warning Expressions don't expand in single quotes, use double quotes for that
#   + because we secure the perl binary call using $perl instead of perl
# - getStrLen() and getStr() double quote warning: do not quote because we need IFS to split
#   + the unquoted variables are all internal
#   + the function uses set -f to disable globbing
#   + the function uses IFS for custom world splitting

# Exit on unset variables (-u), return error if any command fails in a pipe (-o pipefail)
# -f: we need globbing in the "for file in" curl loop
# -e: we do not want to exit on each error, because errors are managed in script and logged
# with -u: check if an arg is set using [ -n "${2:-}" ], that is expand to empty string if $2 is unset
set -u -o pipefail

# Script version
version=1.3.5

## pfsense_send_config.sh
#### !!! This script runs in the pfsense Server under root and sh POSIX shell !!!

: <<'README.MD'
### FUNCTIONS:
- Backup pfsense config file and optionally send it to a remote TFTP server
  + config files are encrypted in openssl with a pfsense compatible format that can be restored from the GUI
  + config files can also be encrypted using rar, gpg or stored as non encrypted tar
- Decrypt/Extract an openssl, rar, gpg or tar config file

### SYNOPSIS:
- Backups are performed and encrypted on the pfsense server
- The backups and logs are stored locally on the pfsense server
- The default storage locations for backup and log files are respectively `$target_mount_point/pfsense_send_config` and `$target_mount_point/logs` directories
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
- backups are stored under `$target_mount_point/pfsense_send_config` directory
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
README.MD

#  ** Editable paths: >>XXXX <<XXXX **
#***************************************

# Define the backup and logs local target share/dataset
# - target_mount_point: mount point target dataset or directory relative to the main freeBSD host
# - filecheck_mount_point: name of a file or directory in the root of $target_mount_point. Used to verify that the target directory is properly mounted
# >>XXXX
target_mount_point="/root"
filecheck_mount_point="scripts"
# <<XXXX

# Name of the directory where backups are stored
# - directory will be created under $target_mount_point
# >>XXXX
backup_dir_name="pfsense_send_config"
# <<XXXX


#  ** BELOW  >>XXXX <<XXXX editable paths are optional ! **
#************************************************************

# Set log file names
# >>XXXX
log_file_name="$backup_dir_name.log" # holds stdout and stderr
log_file_name_stderr="__ERROR__$log_file_name" # only stderr
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
rar="/root/bin/rar"
#rar="/usr/local/bin/rar"
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
nmap="/usr/local/bin/nmap"
mkdir="/bin/mkdir"
sed="/usr/bin/sed"
chown="/usr/sbin/chown"
chmod="/bin/chmod"
touch="/usr/bin/touch"
sleep="/bin/sleep"
curl="/usr/local/bin/curl"
tar="/usr/bin/tar"
perl="/usr/local/bin/perl"
tr="/usr/bin/tr"
#service="/usr/sbin/service"
cp="/bin/cp"
#find="/usr/bin/find"
rm="/bin/rm"
mv="/bin/mv"
tee="/usr/bin/tee"

# Array like string with all binary paths to test
# Posix workaround for missing arrays. Separate command lines by '|'
binary_paths="$openssl|$grep|$nmap|$mkdir|$sed|$chown|$chmod|$touch|$sleep|$curl|$tar|$perl|$tr|$cp|$rm|$mv|$tee"
binary_paths_delimiter="|"
# <<XXXX

# Backup source files
# - source_file: the config file to backup
# >>XXXX
source_file="/cf/conf/config.xml"
# <<XXXX

# Time in seconds to keep trying to connect to the remote TFTP server using nmap
# Used to test if the remote TFTP server is online and listening on the remote port
nmap_sleep=30 # in seconds
#nmap_sleep=1 #
nmap_retry=30 # 30 times (x30 sec = 15 mn)

# Encryption defaults
# - openssl_iter: see below section for details
# - default_encryption: any of ssl|rar|gpg|tar
#   + if no encryption option is defined by command line, use this encryption mode
#   + if set to empty or non valid value, and no file format is set by command line, script will error
# >>XXXX
openssl_iter=""
default_encryption="ssl" # allowed values: ssl,rar,gpg,tar
# <<XXXX


#  ** NO FURTHER EDITS ARE NEEDED BELOW **
#*******************************************

# Global variables for the functions
# - target_dir: directory path where the backup files will be stored ($target_mount_point/$backup_dir_name)
#   encrypted config files will be kept here until they are uploaded
# - log_path: directory path where log files will be stored ($target_mount_point/logs)
# - log_file: path to stdout+stderr log file ($log_path/$log_file_name)
# - log_file_stderr: path to stderr log file ($log_path/$log_file_name_stderr)
target_dir=""
log_path=""
log_file=""
log_file_stderr=""

# Global variables for remote TFTP upload of config and log files
# - remote_host: remote host/IP where the config files will be sent
#   + [-host|--remote-host]: override in-script value by command line args
#   + Default: without -host option, script will only backup locally, like when using -u option
#   + Note: if set here, we can disable uploading by calling script with '-host ""' option
# - remote_host_dir: can be set here or you can append it to remote_host in command line arguments (-host remote_host/remote_dir)
#   + NOTE: if set here, it is not overridden by command line arguments and will be appended to any remote_host/remote_dir path set by command line
# - remote_port: set the default remote server listening port
#   + [-p|--port]: override in-script value by command line args
# - remote_target_path: $remote_host/$remote_host_dir/
remote_host=""
remote_host_dir=""
remote_port=69
remote_target_path=""

# Encryption option settings.
# - If none is specified, use default output format specified in $default_encryption variable
# - If set here to true, they cannot be toggled off by command line option
# - If $upload_only is true, the options will be ignored
# - openssl_crypt [-ssl|--ssl-encryption]:
#   + generate an encrypted openssl backup file
#   + default is compatible with native pfsense encryption
# - openssl_iter [-iter|--iterations-count]: an integer
#   + pbkdf2 iterations: start with 300000 and increase depending on your CPU speed
#   + significant only if openssl_crypt is true
#   + set to empty string for default openssl pbkdf2 iteration count, currently of 10000 as per source code (too low, security wise)
#   + !!! changing this will break native pfsense import of the xml encrypted file !!!
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

# Uplaod/Backup only modes default values
# - upload_only: if set to 'true', no backup is created. Only previous backup/log files are uploaded to TFTP server
#   + enabled by command line option: -u|--upload-only
# - backup_only: if set to 'true', only backup is created. No uploads are done if a host server is specified in script or by command line
#   + enabled by command line option: -b|--backup-only|--no-upload
# >>XXXX
upload_only="false"
backup_only="false"
# <<XXXX

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
setBackupPaths() {
    echo ""
    echo "Setting backup and log paths..."

    # Set the remote target path
    # - remove trailing '/'
    remote_host="${remote_host%/}"
    remote_host_dir="${remote_host_dir%/}"

    # - construct the remote path: if $remote_host is left empty, no upload is done
    remote_target_path=""
    if [ -n "$remote_host" ]; then
        remote_target_path="$remote_host/"
        [ -n "$remote_host_dir" ] && remote_target_path="$remote_host/$remote_host_dir/"
    fi

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
    echo "> Remote host target: $remote_target_path"
    echo "> Log file          : $log_file"
    echo "> Error log file    : $log_file_stderr"
    echo ""
}

# main(): only for config backup, not for decrypting
# ALL BELOW SCRIPT HAS ITS OUTPUT REDIRECTED TO LOG FILES DEFINED ABOVE
# $0 is always the script name and not the function name
main() {
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
    $chown root:wheel "$target_dir" || show_error $? "ERROR setting owner of target directory: $target_dir"
    [ "$error_exit" -eq 0 ] || exit "$error_exit"

    $chmod 700 "$target_dir" || show_error $? "ERROR setting permissions of target directory: $target_dir"
    [ "$error_exit" -eq 0 ] || exit "$error_exit"

    echo ""
    echo "Starting pfSense config files backup"
    if [ "$upload_only" = "true" ]; then
        echo ""
        echo "---Upload only mode. Skipping config files backup---"
    else
        save_config
    fi

    # Optionally upload log files to a remote TFTP server
    # if using backup_only option, or remote_host was not set either by command line or in script: skip upload
    if [ "$backup_only" = "true" ] || [ -z "$remote_host" ]; then
        echo ""
        echo "---Skipping Upload of config files to remote server---"
    else
        send_config
        send_logs
    fi

    echo ""
    echo "Log file: $log_file"
    echo "pfSense settings backup completed"

    date
    echo ""
}

# Backup pfSense config file
save_config() {
    echo ""
    echo "---Saving config files---"

    curr_date=$(date +"%Y%m%d%H%M%S")

    # Note: changing file extensions will need code editing in send_config()
    target_ssl="$target_dir/config-pfSense.intranet-$curr_date.xml"
    target_rar="$target_dir/config-pfSense.intranet-$curr_date.rar"
    target_gpg="$target_dir/config-pfSense.intranet-$curr_date.gpg"
    target_tar="$target_dir/config-pfSense.intranet-$curr_date.tar"

    # Check if source file to backup exists and can be read
    if ! [ -f "$source_file" ] || ! [ -r "$source_file" ]; then
        show_error 1 "ERROR: Cannot find/read config file: $source_file"
        exit 1
    fi

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
# Use base64 encoding and generate a compatible pfsense encrypted xml if iterations count is set to default
save_openssl() {
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

    # Encrypted openssl xml
    # ${openssl_iter:+-iter}: If $openssl_iter is null or unset, nothing is substituted, otherwise the expansion of '-iter' word is substituted.
    # - using "$openssl_iter" causes openssl error 'empty string option'
    # - instead of using $openssl_iter unquoted, we use 'unquoted expansion with an alternate value'
    #   it allows the unquoted empty default value without error, while the non empty $openssl_iter is quoted
    #   https://github.com/koalaman/shellcheck/wiki/SC2086
    # - Note: do not double quote perl argument and keep the single unexpandable quotes
    $openssl enc -e -aes-256-cbc -salt -md sha256 -pbkdf2 ${openssl_iter:+-iter} ${openssl_iter:+"$openssl_iter"} -in "$source_file" -pass file:"$pass_file" | $openssl base64 | $tr -d '\n' | $perl -0xff -pe 's/(.{64})/$1\n/sg' > "$target_ssl"
    command_status=$?
    [ "$command_status" -eq 0 ] || show_error "$command_status" "ERROR encrypting config file: $target_ssl"
    [ "$error_exit" -eq 0 ] || exit "$error_exit"

    echo '---- BEGIN config.xml ----' | cat - "$target_ssl" > "$target_dir/tmp_xml" && $mv "$target_dir/tmp_xml" "$target_ssl"
    command_status=$?
    [ "$command_status" -eq 0 ] || show_error "$command_status" "ERROR adding header to encrypted config file: $target_ssl"
    [ "$error_exit" -eq 0 ] || exit "$error_exit"

    printf "\n%s" '---- END config.xml ----' >>"$target_ssl"
    command_status=$?
    [ "$command_status" -eq 0 ] || show_error "$command_status" "ERROR adding foot section to encrypted config file: $target_ssl"
    [ "$error_exit" -eq 0 ] || exit "$error_exit"

    echo "- File saved: $target_ssl"
}

# RAR encrypted backup file
save_rar() {
    echo ""
    echo "> RAR backup to $target_dir"

    # Check if rar binary is available
    [ -f "$rar" ] || show_error 1 "ERROR: cannot find rar commad: $rar"
    [ "$error_exit" -eq 0 ] || exit "$error_exit"

    # Get the encryption password and assign it to $password
    password=""
    get_password

    $rar a -ow -@ -rr10 -s- -ep -m3 -ma -p"$password" "$target_rar" "$source_file" | $sed -e 's/     .*OK/ OK/' -e 's/     .*100%/ 100%/'
    command_status=$?
    [ "$command_status" -eq 0 ] || show_error "$command_status" "ERROR creating rar encrypted backup: $target_rar"
    [ "$error_exit" -eq 0 ] || exit "$error_exit"

    echo "- File saved: $target_rar"
}

# GnuPG encrypted backup file
save_gpg() {
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
    source_dir=$(dirname "$source_file")
    source_file_name=$(basename "$source_file")
    $tar -cf - -C "$source_dir" "$source_file_name" \
        | $gpg --cipher-algo aes256 --pinentry-mode loopback --passphrase-file "$pass_file" -o "$target_gpg" --symmetric
          # [--pinentry-mode loopback] : needed in new gpg for supplying unencryped passwords on command line. Else, we get the error "problem with the agent: Invalid IPC response"

    command_status=$?
    [ "$command_status" -eq 0 ] || show_error "$command_status" "ERROR creating gpg encrypted backup: $target_gpg"
    [ "$error_exit" -eq 0 ] || exit "$error_exit"

    echo "- File saved: $target_gpg"
}

# TAR non-encrypted backup file
save_decrypted() {
    echo ""
    echo "> Non-encrypted backup to $target_dir"

    # Print warning to stderr
    show_error 0 "- WARNING: backup using no encryption..."

    # no encryption is selected, only create a tarball
    # freeBSD tar defaults verbose messages to stderr and always uses stdout as archive destination (pipe)
    # unlike some installers where tar only outputs archive to stdout if we specify '-' as filename or no "-f filename"
    # do not use verbose (tar -cvf), else stderr gets populated with filenames and cron job sends an error
    source_dir=$(dirname "$source_file")
    source_file_name=$(basename "$source_file")
    $tar -cf "$target_tar" -C "$source_dir" "$source_file_name"

    command_status=$?
    [ "$command_status" -eq 0 ] || show_error "$command_status" "ERROR creating non-encrypted backup: $target_tar"
    [ "$error_exit" -eq 0 ] || exit "$error_exit"

    echo "- File saved: $target_tar"
}

# Send config to the remote tftp server
send_config() {
    echo ""
    echo "---Uploading config files to remote server---"
    echo "> Waiting for remote TFTP server to be online"

    # Validate args
    [ -z "$remote_host" ] && show_error 1 "ERROR: Internal error: send_config() called with no remote_host"
    is_integer "$remote_port" || show_error 1 "ERROR: No valid TFTP server port found:  port=$remote_port"
    [ "$error_exit" -eq 0 ] || exit "$error_exit"

    # We wait for the TFTP server to be online using nmap, before trying an upload using curl
    # - nmap: tries to actively conect to a spectifc port service
    # - Wait for remote host tftpd daemon to start listening on defined port
    # -sU: UDP port
    # -p: port to connect to
    command_status=1
    while [ "$nmap_retry" -gt 0 ]
    do
        $nmap -sU -p "$remote_port" "$remote_host" | $grep "$remote_port/udp open"
        command_status=$?
        [ "$command_status" -eq 0 ] && break
        #sudo wake ixl0 b0:b9:8a:43:3d:7a
        #sudo wake ixl0 b0:b9:8a:43:3d:7b
        $sleep "$nmap_sleep"
        nmap_retry=$((nmap_retry - 1))
    done

    [ "$command_status" -eq 0 ] || show_error "$command_status" "ERROR: TFTP server is unreachable ($remote_host:$remote_port)"
    [ "$error_exit" -eq 0 ] || exit "$error_exit"

    echo ""
    echo "> Uplaoding config files to server: $remote_target_path"
    # Use curl to upload to TFTP server
    # --no-progress-meter: disable progress bar because it is printed alwys to stderr when we redirect output
    # --connect-timeout $curl_conn_timeout:
    #   max time to establish connection
    # --retry $curl_retry_count:
    #   max retry number on transient errors during connection or transfer.
    #   Setting the number to 0 makes curl do no retries (which  is  the default)
    #   Transient error means either: a timeout, an FTP 4xx response code or an HTTP 408, 429, 500, 502, 503 or 504 response code.
    # --retry-delay $curl_retry_delay:
    #   Sleep this amount of time before each retry when a transfer has failed with a transient error
    #   Only useful with --retry option
    # --max-time, -m $curl_max_time:
    #   Maximum time in seconds that you allow the  whole  operation  to take.
    #   Prevents batch jobs from hang-ing for hours due to slow networks or links going down.
    curl_conn_timeout="10"
    curl_retry_count="60"
    curl_retry_delay="5"
    curl_max_time="900" # 15mn

    for file in "$target_dir"/*; do
        # if it is not a file, skip it
        if [ ! -f "$file" ]; then
            show_error 0 "WARNING: skipped not file entry: $file"
            continue
        fi

        # Check if it is a valid backup file name extension and upload it
        # Delete the local file if upload was successful
        case "$file" in
            *".xml"|*".rar"|*".gpg"|*".tar")
                echo "- Uploading file: $(basename "$file")"
                $curl \
                    --no-progress-meter \
                    --connect-timeout "$curl_conn_timeout" \
                    --retry "$curl_retry_count" \
                    --retry-delay "$curl_retry_delay" \
                    --max-time "$curl_max_time" \
                    -T "$file" "tftp://$remote_target_path" \
                && printf "%s" "- Deleting uploaded file " \
                && $rm -v "$file"

                command_status=$?
                [ "$command_status" -eq 0 ] || show_error "$command_status" "ERROR: failed to upload config file: $file"
                [ "$error_exit" -eq 0 ] || exit "$error_exit"

                echo ""
            ;;

            *)
                # skip non valid backup files, but print a warning to stderr
                show_error 0 "WARNING: skipped non-backup file: $file"
                continue
            ;;
        esac
    done

    echo ""
    echo "> Config files uploaded successefully to $remote_target_path"
}

# Send the log files to remote server
# !! script should be started like "stdbuf -oL -eL -iL script_name" to force flushing on every line !!
#    else, the current session pfsense logs could be only sent on next script run
send_logs() {
    echo ""
    echo "---Uploading log files to remote server---"

    # Validate args
    [ -z "$remote_host" ] && show_error 1 "ERROR: Internal error: send_logs() called with no remote_host"
    is_integer "$remote_port" || show_error 1 "ERROR: Internal error: send_logs() called with inavlid port num: $remote_port"
    [ "$error_exit" -eq 0 ] || exit "$error_exit"

    echo "> Renaming current log files"
    # !!! AFTER THIS, ALL OUTPUT IS ADDED TO NEWLY CREATED LOG FILES, AND WILL BE UPLOADED ON NEXT SCRIPT RUN !!!
    # Copy the log files to a unique filename with current date of config backup
    # This is to avoid overwriting target remote log files already uploaded
    # We will concatenate the uploaded logs later on the target server
    # Note: the verbose output from cp -v below is not appended to log files (files emptied by below printf)
    #       instead, it is printed to terminal
    $cp -v "$log_file" "$log_path/$curr_date.$log_file_name" \
        && $cp -v "$log_file_stderr" "$log_path/$curr_date.$log_file_name_stderr"

    command_status=$?
    [ "$command_status" -eq 0 ] || show_error "$command_status" "ERROR: Failed to local copy log files !!"
    [ "$error_exit" -eq 0 ] || exit "$error_exit"

    # Empty the current log files
    # use 'printf "" > file', equivalent to 'rm -v file && touch file'
    printf "" > "$log_file"
    printf "" > "$log_file_stderr"

    # Print the previous cp -v stdout to the log file (for a more proper way, redirect cp -v stdout and stderr to temp log files)
    echo "$log_file -> $log_path/$curr_date.$log_file_name" >"$log_file"
    echo "$log_file_stderr -> $log_path/$curr_date.$log_file_name_stderr" >>"$log_file"

    # All logging is now redirected to the emptied $log_file and $log_file_stderr
    # It will be uploaded to server on next script run
    echo ""
    echo "> Uplaoding log files to remote server"
    for file in "$log_path"/*; do
        # If it is not a file, skip it
        if [ ! -f "$file" ]; then
            show_error 0 "WARNING: skipped not file entry: $file"
            continue
        fi

        # Upload any date stamped log files, but not the current log files
        # then, delete the local files if upload was successful
        case "$file" in
            *".$log_file_name"|*".$log_file_name_stderr")
                echo "- Uploading log file: $(basename "$file")"
                $curl \
                    --no-progress-meter \
                    --connect-timeout 10 \
                    --retry 3 \
                    --retry-delay 5 \
                    --max-time 300 \
                    -T "$file" "tftp://$remote_target_path" \
                && printf "%s" "- Deleting uploaded log file " \
                && $rm -v "$file"

                command_status=$?
                [ "$command_status" -eq 0 ] || show_error "$command_status" "ERROR: failed to upload log file: $file"
                [ "$error_exit" -eq 0 ] || exit "$error_exit"

                echo ""
            ;;

            "$log_file"|"$log_file_stderr")
                # current log files
                continue
            ;;

            *)
                # skip non valid log files, but print a warning to stderr
                show_error 0 "WARNING: skipped non-log file: $file"
            ;;
        esac
    done

    echo ""
    echo "> Log files uploaded successefully to $remote_target_path"
}

# Decrypt config file
decrypt_config() {
    echo ""
    echo "---Decrypting config files---"
    echo "> Input file: $input_file"

    # Check decryption options
    [ "$decrypt_mode" != "true" ] && show_error 1 "INTERNAL ERROR: decrypt_config(): decrypt_mode=$decrypt_mode"
    [ "$error_exit" -eq 0 ] || exit "$error_exit"

    [ -z "$input_file" ] && show_error 1 "INTERNAL ERROR: decrypt_config(): empty input_file"
    [ "$error_exit" -eq 0 ] || exit "$error_exit"

    # Check that there are no multiple decryption formats set to true (in script edits)
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

extract_openssl() {
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
    outfile=$(basename "$input_file")
    out_path="${out_path%/}"  # remove trailing /
    $grep -v "config.xml" "$input_file" | $openssl base64 -d | $openssl enc -d -aes-256-cbc -salt -md sha256 -pbkdf2 ${openssl_iter:+-iter} ${openssl_iter:+"$openssl_iter"} -out "$out_path/$outfile" -pass file:"$pass_file"
    command_status=$?
    [ "$command_status" -eq 0 ] || show_error "$command_status" "ERROR: failed decrypting $input_file"
    [ "$error_exit" -eq 0 ] || exit "$error_exit"
}

extract_rar() {
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
    out_path="${out_path%/}"  # remove trailing /
    $rar x -p"$password" "$input_file" "$out_path/"

    command_status=$?
    [ "$command_status" -eq 0 ] || show_error "$command_status" "ERROR: failed decrypting $input_file"
    [ "$error_exit" -eq 0 ] || exit "$error_exit"
}

extract_gpg() {
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

extract_tar() {
    echo "> Extracting tar file to $out_path"
    echo ""

    # Extract config file
    $tar -xvf "$input_file" -C "$out_path"

    command_status=$?
    [ "$command_status" -eq 0 ] || show_error "$command_status" "ERROR: failed extracting $input_file"
    [ "$error_exit" -eq 0 ] || exit "$error_exit"
}

# Check the password if encryption is set
get_password() {
    #password=$(<"$pass_file") # bash only
    password=$(cat "$pass_file")
    [ -z "$password" ] && show_error 1 "ERROR: no password was set" "you must specify a password in $pass_file"
    [ "$error_exit" -eq 0 ] || exit "$error_exit"
}

# Check if a received arg is an integer (exclude -/+ signs)
is_integer() {
    command_status=1
    [ $# -ne 1 ] && show_error 1 "ERROR: Internal error: is_integer() needs one argument"
    [ "$error_exit" -eq 0 ] || exit "$error_exit"

    # Bash only
    #[[ "$1" =~ ^[0-9]+$ ]] && command_status=0 # is an integer
    #return "$command_status"

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
}

# Log passed args to stderr and preserve error code from caller
# - call syntax: show_error $? "error msg 1" "error message 2"...
# - after function call, use this line of code: [ "$error_exit" -eq 0 ] || exit "$error_exit"
#   this will exit with "$error_exit" code if previous command failed
# - we do not exit here else stderr gets flushed after the command prompt display
show_error() {
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
# - Accepts two args: binary_paths=$1 and delimiter=$2
checkBinaries() {
    # Save old IFS
    OLDIFS=$IFS             # Save old IFS
    ${IFS+':'} unset OLDIFS # If IFS is unset, expands to empty string, enabling next 'unset OLDIFS' command.
                            # If it is set even to empty string, expand to ':', which disables next 'unset OLDIFS' command.
    IFS="$2"                # Specify separator between elements
    set -f                  # Disable file name expansion (globbing), so '*' is not replaced with a list of files

    # Define some array like functions because posix doesn't support arrays
    # getStr index str: returns the str[index] sub string
    getStr() {
        shift "$(( $1 + 1 ))"; printf '%s' "$1"
    }

    #getLastStr str: returns the last sub string from str
    getLastStr() {
        getStr "$(( $(length "$@") - 1 ))" "$@"
    }

    #getStrLen str: returns the number of substring elements in str
    getStrLen() {
        printf '%s' "$#"
    }

    err_msg=""
    len=$(getStrLen $1)
    i=0
    while [ $i -lt "$len" ]
    do
        suffix=", " # a separator between bad paths printed in our error message
        [ -z "$err_msg" ] && suffix=""
        bin_path=$(getStr $i $1)
        [ -f "$bin_path" ] || err_msg="$err_msg$suffix$bin_path"
        i=$((i + 1))
    done

    # Reset IFS to its original state, even if it was unset
    IFS=$OLDIFS
    ${OLDIFS+':'} unset IFS
    unset OLDIFS
    set +f

    [ -z "$err_msg" ] || show_error 1  "ERROR: could not find commands: $err_msg" "Please fix the variables in script with the proper paths"
    [ "$error_exit" -eq 0 ] || exit "$error_exit"
}

# Process command line arguments
# - output is not logged to a file but to stderr because the log file is not yet properly set !
# - argument errors are sent to stderr, so that a cron job alert can be triggered even at this stage
parseArguments() {
    # Args class count
    # Used to check if specific encryption options were set while the -d decrypt mode was specified
    pos_args=0 # positional args count
    enc_options=0 # encryption args count
    dec_options=0 # decryption args count
    host_options=0 # # upload args count

    # Bash:
    #while (( "$#" )); do
    # Posix sh:
    while [ $# -ne 0 ]; do
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
            -host|--remote-host)
                # First char of $str: $(printf %.1s "$str")
                if [ -n "${2:-}" ] && [ "$(printf %.1s "$2")" != "-" ]; then
                    remote_host="$2"
                    host_options=$((host_options + 1))
                    shift 2
                else
                    show_error 1 "ERROR: Argument for $1 is missing" "Usage: $script_name [-options] [target_mount_point] [filecheck_mount_point]"
                    exit 1
                fi
                ;;
            -p|--port)
                # First char of $str: $(printf %.1s "$str")
                if [ -n "${2:-}" ] && [ "$(printf %.1s "$2")" != "-" ]; then
                    is_integer "$2" || show_error 1 "ERROR: syntax error" "Port number must be a number" "Usage: $script_name [-options] [target_mount_point] [filecheck_mount_point]"
                    [ "$error_exit" -eq 0 ] || exit "$error_exit"

                    remote_port="$2"
                    host_options=$((host_options + 1))
                    shift 2
                else
                    show_error 1 "ERROR: Argument for $1 is missing" "Usage: $script_name [-options] [target_mount_point] [filecheck_mount_point]"
                    exit 1
                fi
                ;;
            -u|--upload-only)
                upload_only="true"
                host_options=$((host_options + 1))
                shift
                ;;
            -b|--backup-only|--no-upload)
                backup_only="true"
                shift
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
                #POSITIONAL_PARAMS+=("$1")
                shift
                ;;
        esac
    done

    # Bash:
    # Set positional arguments in their proper place
    #set -- "${POSITIONAL_PARAMS[@]}"

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

    # Case upload only and backup only options are set at the same time
    [ "$upload_only" = "true" ] && [ "$backup_only" = "true" ] \
        && show_error 1 "ERROR: syntax error" "Backup Only and Upload Only options cannot be used together" "Usage: $script_name [-options] [target_mount_point] [filecheck_mount_point]"
    [ "$error_exit" -eq 0 ] || exit "$error_exit"

    # Case backup only or upload only options with decrypt options
    # - checked below if dec_options are set

    # Case backup only option with remote host options set: harmless but meaningless
    [ "$backup_only" = "true" ] && [ $host_options -ne 0 ] && show_error 1 "ERROR: syntax error" \
        "Backup Only option cannot be used with remote upload options" \
        "Usage: $script_name [-options] [target_mount_point] [filecheck_mount_point]"
    [ "$error_exit" -eq 0 ] || exit "$error_exit"

    # Case upload only option is specified
    # - if -u|--upload-only: script will skip backup and only upload any previous backup/log files to provided tftp server host
    # - else set a default encryption/decryption format if none is specified
    if [ "$upload_only" = "true" ]; then
        [ -z "$remote_host" ] && show_error 1 "ERROR: syntax error" "No remote host specified" "Usage: $script_name [-options] [target_mount_point] [filecheck_mount_point]"
        is_integer "$remote_port" || show_error 1 "ERROR: syntax error" "No valid remote port specified" "Usage: $script_name [-options] [target_mount_point] [filecheck_mount_point]"
        [ $enc_options -ne 0 ] && show_error 1 "ERROR: syntax error" "Encryption options are not used in upload only mode" "Usage: $script_name [-options] [target_mount_point] [filecheck_mount_point]"
        [ $dec_options -ne 0 ] && show_error 1 "ERROR: syntax error" "Decryption options are not used in upload only mode" "Usage: $script_name [-options] [target_mount_point] [filecheck_mount_point]"
        # case -iter option is set, just ignore it
        [ "$error_exit" -eq 0 ] || exit "$error_exit"
    fi

    # Case no file format option is provided, either for encryption or decryption
    if [ $enc_options -eq 0 ] && [ "$upload_only" != "true" ]; then
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

        # uplaod and backup only options has no meaning in decrypt mode
        if [ "$upload_only" = "true" ] || [ "$backup_only" = "true" ]; then
            show_error 1 "ERROR: syntax error" "Decryption options are not used in upload/backup only modes" "Usage: $script_name [-options] [target_mount_point] [filecheck_mount_point]"
            exit 1
        fi

        # upload host options has no meaning in decrypt mode
        [ $host_options -ne 0 ] && show_error 1 "ERROR: syntax error: Remote host options cannot be specified for decryption" "Usage: $script_name [-options] [target_mount_point] [filecheck_mount_point]"
        [ "$error_exit" -eq 0 ] || exit "$error_exit"

    #else
        # backup/upload mode
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
    echo "  - remote host       : $remote_host"
    echo "  - remote port       : $remote_port"
    echo "  - upload only mode  : $upload_only"
    echo "  - backup only mode  : $backup_only"
}

# Print version and syntax
printVersion() {
    echo ""
    echo "$script_name version $version"
    echo "usage: $script_name.sh [-options] [target_mount_point] [filecheck_mount_point]"
    echo "- target_mount_point   : target dataset/directory for the local pfsense backup"
    echo "- filecheck_mount_point: file/dir in 'target_mount_point' to ensure that the target is properly mounted"
    echo "- Options : [-ssl|--ssl-encryption][-rar|--rar-encryption][-gpg|--gpg-encryption]"
    echo "            [-tar|--unencrypted-tar][-iter|--iterations-count]"
    echo "            [-host|--remote-host][-p|--port][-u|--upload-only][-b|--backup-only|--no-upload]"
    echo "            [-?|-help]"
    echo "- Decrypt : [-d|--decrypt][-in|--input-file][-out|--out-dir][encryption option]"
    echo "- Defaults: backup using $default_encryption encryption to in-script path $target_mount_point"
}

# Parse script arguments
parseArguments "$@" || show_error $? "ERROR parsing script arguments"
[ "$error_exit" -eq 0 ] || exit "$error_exit"

# Check if all the binary paths are properly set
# - ! do not quote $binary_paths !
checkBinaries $binary_paths "$binary_paths_delimiter"

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
#
# POSIX sh doesn't support bash like process substitution. Instead:
# - mkfifo: we create temporary fifo files for stdout and stderr in $log_path (or /tmp if $log_path is empty string)
# - trap: on exit or sigterm (Ctrl^C...) of script, always delete the FIFO files (use TRAP so if script crashes, fifo files are still deleted)
# - main "$@" >"$pfout_fifo" 2>"$pferr_fifo" : redirect main() stdout and stderr to their respective fifo files
# - tee -a "$log_file_stderr" < "$pferr_fifo" >>"$pfout_fifo":
#   + $pferr_fifo is redirected to both $pfout_fifo in append mode (>>"$pfout_fifo")
#     and to $log_file_stderr (tee -a "$log_file_stderr"), also in append mode (tee -a)
#   + $pfout_fifo file will contain both stdout and stderr
#   + $log_file_stderr: will hold stderr (from $pferr_fifo, appended by tee -a command)
#   + stderr is also sent to terminal through the tee command
# - tee -a "$log_file" < "$pfout_fifo":
#   + finally, $pfout_fifo is appended to $log_file using the tee -a command
#   + and also it is sent to terminal using the same tee command
# - & : run each command line in parallel
#
# Notes:
# - after an 'mv -v $log_file', the pfout_fifo will be redirected to the new moved file !
# - so, instead we copy the $log_file to a new file, we empty it, and next script stdout will be written to the empty $log_file
# - we then upload the $log_file copy, we remove the copy, and on next script run, the $log_file will be uploaded with its remaining data
pfout_fifo="${log_path:-/tmp}/pfout_fifo.$$"
pferr_fifo="${log_path:-/tmp}/pferr_fifo.$$"

echo "DEBUG: pfout_fifo=$pfout_fifo - pferr_fifo=$pferr_fifo"
mkfifo "$pfout_fifo" "$pferr_fifo" || show_error $? "ERROR creating fifo files" "- pfout_fifo=$pfout_fifo" "- pferr_fifo=$pferr_fifo"
[ "$error_exit" -eq 0 ] || exit "$error_exit"

trap '$rm "$pfout_fifo" "$pferr_fifo"' INT EXIT

$tee -a "$log_file" < "$pfout_fifo" &
    $tee -a "$log_file_stderr" < "$pferr_fifo" >>"$pfout_fifo" &
    main "$@" >"$pfout_fifo" 2>"$pferr_fifo"; exit
