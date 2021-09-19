#!/bin/bash

# https://github.com/PhilZ-cwm6/truenas_scripts
# Script version
version=1.1.2

# Backup TrueNAS/FreeNAS configuration database and password secret encryption files (storage encryption keys)
# - must be started as root !!
# - OPTIONAL: start by editing >>XXXX <<XXXX code parts

# Syntax: script_name.sh [Options] [Positional params]
# Usage : script_name.sh [-rar|-ssl|-gpg|-no-enc] [target_mount_point] [filecheck_mount_point]
# - Positional parameters:
#   + target_mount_point   : taget dataset/directory where the config files will be saved under a created subdir called 'save_config'
#   + filecheck_mount_point: name of a file or directory that must be in the specified 'target_mount_point'
#                          it ensures that the target path is properly mounted before doing a backup job
#   + if omitted, you must edit below 'target_mount_point' and 'filecheck_mount_point' variables
#   + when provided by command line, they will override the 2 inscript variables
#
# - Option flags:
#   + -rar|--rar-encryption     : use proprietary RAR5 AES256 encryption
#   + -ssl|--openssl-encryption : use OpenSSL AES256-CBC SHA512 PBKDF2 iterations and salt encryption
#   + -gpg|--gpg-encryption     : use GnuPG AES256 encryption (GPG)
#   + -no-enc|--no-encryption   : tar file with no encryption, strongly not recommended. Will generate a warning to stderr

# - Exp1: save_config.sh "/mnt/pool/tank/config" ".config.online"
#   + backup config file and encryption keys to /mnt/pool/tank/config dataset
#   + ensure that the dataset is properly mounted by checking if '.config.online' file/dir exists in root of the specified dataset
#   + default to openssl encryption
#
# - Exp2: save_config.sh -rar
#   + no arguments are provided: backup config file and encryption key to default in-script path $target_mount_point
#   + ensure that $target_mount_point is properly mounted by checking for existance of the file/dir $filecheck_mount_point
#   + use optional rar5 encryption (you must install rar software)
#
# - Exp3: save_config.sh --no-encryption "/mnt/pool/tank/config" ".config.online"
#   + backup config file and encryption keys to /mnt/pool/tank/config dataset
#   + ensure that the dataset is properly mounted by checking if '.config.online' file/dir exists in root of the specified dataset
#   + use no encryption

# Decrypt OpenSSL aes files :
# - use this command to extract the contents to 'decrypted_tarball.tar' file:
# openssl enc -d -aes-256-cbc -md sha512 -pbkdf2 -iter "$openssl_iter" -salt -in "$target_backup_file" -pass file:pass.txt -out decrypted_tarball.tar
#
# - you can extract tar contents to an existing "existing_extract_dir" folder:
# openssl enc -d -aes-256-cbc -md sha512 -pbkdf2 -iter "$openssl_iter" -salt -in "$target_backup_file" -pass file:pass.txt | tar -xvf - -C "existing_extract_dir"
#
# - or you can extract the tar contents to current folder
# openssl enc -d -aes-256-cbc -md sha512 -pbkdf2 -iter "$openssl_iter" -salt -in "$target_backup_file" -pass file:pass.txt | tar -xvf -

# Encrypt file using GnuPG:
# [--pinentry-mode loopback] : because of a bug in TrueNAS causing the error "problem with the agent: Invalid IPC response"
# gpg [options] --symmetric file_to_encrypt
# gpg --cipher-algo aes256 --passphrase-file "path_to_passfile" --pinentry-mode loopback -o outputfile.gpg --symmetric file_to_encrypt

# Decrypt GnuPG gpg files :
# - run gpg command without any option, it will prompt for the password:
# gpg backup_file.gpg
#
# - or run with -d (decrypt), extract to a backup_file.tar file (-o option) and and pass in the passfile (--passphrase-file option)
# gpg --passphrase-file "path_to_passfile" -o backup_file.tar -d backup_file.gpg

# - or pipe tar command and directly extract and decrypt the backup file to local folder
# gpg --passphrase-file "path_to_passfile" -d backup_file.gpg | tar -xvf -


#  ** Editable paths: >>XXXX <<XXXX **
#***************************************


# Define the backup and logs target share/dataset
# You can omit them if you supply the path in command line (will override below $target_mount_point and $filecheck_mount_point)
# - target_mount_point: mount point target dataset or directory relative to the main freeBSD host
# - filecheck_mount_point: name of a file or directory in the root of $target_mount_point. Used to verify that the target directory is properly mounted
# - backup_dir_name: name of the directory where backups and logs are stored
# - target_dir: directory path where the backup files will be stored
# - tmp_dir: temp directory used only for the sqlite3 backup
# >>XXXX
target_mount_point=""
filecheck_mount_point=""
backup_dir_name="save_config"
# <<XXXX
target_dir="$target_mount_point"/"$backup_dir_name"
tmp_dir="/root/tmp/$backup_dir_name"


#  ** BELOW  >>XXXX <<XXXX editable paths are optional ! **
#************************************************************


# Define some global variables for our functions
# - eventually edit openssl_iter variable if your CPU is slower/faster
rar_crypt="false" # -rar|--rar-encryption flag
openssl_crypt="false" # -ssl|--openssl-encryption flag
gpg_crypt="false" # -gpg|--gpg-encryption flag
openssl_iter=100000 # openssl pbkdf2 iterations: start with 100000 and increase depending on your CPU speed
no_encryption="false" # -no-enc|--no-encryption flag

# Set the target mount point for backup files and logging
target_mount_point="${target_mount_point%/}" # remove trailing / from target_mount_point name

# Set log file variable
# >>XXXX
log_path="$target_mount_point"/logs
log_file_name="$backup_dir_name".log # holds stdout and stderr
log_file_name_err=__ERROR__"$log_file_name" # only stderr
# <<XXXX
log_file="$log_path"/"$log_file_name"
log_file_stderr="$log_path"/"$log_file_name_err"

# Option to prune archive files older than x days
# If you manually move an archive file to the target subfolder 'archive_dir_name', it will be excluded from pruning
# - keep_days: max days before deleting backup
# - archive_dir_name: dir name where backups will not be pruned if older than $keep_days
# >>XXXX
keep_days=180
archive_dir_name="keep"
# <<XXXX

# Script path and file name
script_path=$(dirname "$0")
script_name=$(basename "$0")

# Backup Password file path: the path for a the file containing the password for the target backup when using encryption
# - the password file is in the same folder as this script file
# - the password file name: same as the script file name, with last extension replaced by .pass
# - Edit only if password file name or path needs to be changed
# >>XXXX
pass_file_path="$script_path"
pass_file_name="${script_name%.*}".pass # scriptname.sh becomes scriptname
# <<XXXX
pass_file="$pass_file_path/$pass_file_name"

# Paths where rar command is installed
# - look first in default rar install path /usr/local/bin/rar
# - then in some custom "~/bin/rar" paths for root and admin users
# - customize below path if you install rar elsewhere
# >>XXXX
admin_user_home=$(grep ^admin: /etc/passwd | cut -d: -f6)
rar_paths=(
    "/usr/local/bin/rar"
    "/root/bin/rar"
    "$admin_user_home/bin/rar"
)
# <<XXXX

# Backup source files [should not be edited]:
# - password file to backup
pwenc_dir="/data"
pwenc_file="pwenc_secret"

# - config file databse to backup
config_db_dir="/data"
config_db_name="freenas-v1.db"


#  ** NO FURTHER EDITS ARE NEEDED BELOW **
#*******************************************


# Some global variables for the functions
declare target_mount_point # target mount point for backup files and logging
declare target_backup_file # generated target backup file with path
declare log_file log_file_stderr
declare POSITIONAL_PARAMS= # any other arguments without "-" prefix: not used

# Return value used to keep success/error code status of commands ($?)
# - used to exit on a command error after calling show_error() function
error_exit=0

# Check if target and log paths are mounted and writable
# - output is not logged to a file but to stderr because the log file is not yet properly set !
# - redirect stdout to stderr for cronjob error alert
# - receives only positional arguments, not option flags (not used currently)
function checkBackupPaths() {
: <<'DEBUG_CODE'
    echo "arg1=$1   arg2=$2"
    for arg in "$@"; do
        echo arg="$arg"
    done
    exit
DEBUG_CODE
    # - ensure that taget path was set either by command line args or in the script variables
    if [ -z "$target_mount_point" ] || [ -z "$filecheck_mount_point" ]; then
        show_error 1 "ERROR: syntax error" \
            "Script needs 2 arguments" \
            "Usage: $script_name [target_mount_point] [filecheck_mount_point]" \
            "Optionally, you can edit in script variables 'target_mount_point' and 'filecheck_mount_point'"
        exit 1
    fi

    # Ensure the target mount point is properly mounted before creating any files on the target
    if [ ! -f "$target_mount_point"/"$filecheck_mount_point" ] && [ ! -d "$target_mount_point"/"$filecheck_mount_point" ] ; then
        show_error 1 "ERROR: TARGET DIRECTORY NOT MOUNTED" \
            "ensure the directory is properly mounted and the below file exists at its root:" \
            "$target_mount_point"/"$filecheck_mount_point"
        exit 1
    fi

    # Ensure the target directory is writable
    if [ ! -w "$target_mount_point" ]; then
        show_error 1 "ERROR: TARGET DIRECTORY NOT WRITABLE" \
            "ensure the directory is properly mounted and writable by current user:" \
            "$target_mount_point"
        exit 1
    fi

    # Create the log path
    # - it is needed to be able to use it as a redirect at the end of our script block
    # - it is important to preserve stderr so that the cron job can send an email with stderr if job fails
    mkdir -p "$log_path" || show_error 1 "ERROR: Failed to create log di: $log_path"
    [ "$error_exit" -eq 0 ] || exit "$error_exit"

    touch "$log_file" || show_error 1 "ERROR: Failed to access log file: $log_file"
    [ "$error_exit" -eq 0 ] || exit "$error_exit"

    [ ! -f "$log_file_stderr" ] && touch "$log_file_stderr"
    [ -f "$log_file_stderr" ] || show_error 1 "ERROR: Failed to access error log file: $log_file_stderr"
    [ "$error_exit" -eq 0 ] || exit "$error_exit"
}

# ALL BELOW SCRIPT HAS ITS OUTPUT REDIRECTED TO LOG FILES DEFINED ABOVE
# $0 is always the script name and not the function name
function main() {
    # Print version
    date
    printVersion

    # Check if source files to backup exist
    # - passwords file
    [ ! -f "$pwenc_dir/$pwenc_file" ] && show_error 1 "Password file not found: $pwenc_dir/$pwenc_file"
    [ "$error_exit" -eq 0 ] || exit "$error_exit"

    # -config database file to backup
    [ ! -f "$config_db_dir/$config_db_name" ] && show_error 1 "Config file database not found: $config_db_dir/$config_db_name"
    [ "$error_exit" -eq 0 ] || exit "$error_exit"

    # Create the backup target and temp directories
    # chmod/chown the temp dir so that only root can access it
    mkdir -p "$target_dir" || show_error $? "ERROR creating target directory: $target_dir"
    [ "$error_exit" -eq 0 ] || exit "$error_exit"

    mkdir -p "$tmp_dir" || show_error $? "ERROR creating temporary directory: $tmp_dir"
    [ "$error_exit" -eq 0 ] || exit "$error_exit"

    chown root:wheel "$tmp_dir" || show_error $? "ERROR setting owner of temp directory: $tmp_dir"
    chmod 700 "$tmp_dir" || show_error $? "ERROR setting permissions of temp directory: $tmp_dir"

    # When using encryption, error and exit if we have an empty password
    # - if no passfile is found: cat will output an error to stderr and $password remains unset/empty
    # - if we use a prompt for password mode like rar -p"", the
    #   script would hang in cron job waiting for password to be entered by user
    # - Note: using 'cat' will remove any trailing new lines from the passfile !!
    if [ "$no_encryption" != "true" ]; then
        #password=$(<"$pass_file") # bash only
        password=$(cat "$pass_file")
        [ -z "$password" ] && show_error 1 "ERROR: no password was set" "you must specify a password in $pass_file"
        [ "$error_exit" -eq 0 ] || exit "$error_exit"
    fi

    # If using rar compression, ensure rar binary exists
    rar=""
    if [ "$rar_crypt" = "true" ]; then
        for rarbin in "${rar_paths[@]}"; do
            [ -f "$rarbin" ] && rar="$rarbin"
        done

        # error and exit if rar binary was not found
        # array[*] : merges all array items in one item, so that they are shown in one line
        [ -z "$rar" ] && show_error 1 "ERROR: rar binary not found in:" "${rar_paths[@]}"
        [ "$error_exit" -eq 0 ] || exit "$error_exit"
    fi

    save_config "$@"
    rm_old_backups

    echo ""
    echo "Config file and encryption keys saved to $target_dir"
    echo "Log file: $log_file"
    echo ""

    # Print decryption info if openssl was used
    if [ "$openssl_crypt" = "true" ]; then
        echo "OpenSSL AES Decryption Instructions:"
        echo " - decrypt to a tar file:"
        echo "openssl enc -d -aes-256-cbc -md sha512 -pbkdf2 -iter '$openssl_iter' -salt -in '$target_backup_file' -pass file:passfile.pass -out decrypted_tarball.tar"
        echo ""
        echo " - decrypt and extract files to current dir:"
        echo "openssl enc -d -aes-256-cbc -md sha512 -pbkdf2 -iter '$openssl_iter' -salt -in '$target_backup_file' -pass file:passfile.pass | tar -xvf -"
    fi

    echo ""
    echo ""
    echo "TrueNAS settings backup completed"

    date

    echo ""
    echo "-------------------------------------------------"
    echo ""
} > >(tee -a "$log_file") 2> >(tee -a "$log_file_stderr" | tee -a "$log_file" >&2)
    # 1rst tee writes {script block} STDOUT (} >) to a file + we preserve it on STDOUT
    # 2nd tee writes {script block} STDERR (2>) to a different file + we redirect 2nd tee STDOUT (actually {script block} STDERR) to 3rd tee
    # 3rd tee writes STDERR to our main log file so that it contains all the screen equivalent output (stdout + stderr)
    # 3d tee redirects its STDOUT back to STDERR so that we preserve {script block} STDERR on the terminal STDERR

# Backup TrueNAS settings
function save_config() {
    echo "Starting config file and passwords backup"

    # Get current OS version (used to set the target backup file name)
    # - output is in the form of: TrueNAS-12.0-U5.1 (6c639bd48a)
    # - include into () to transform the string into an array of space separated strings
    freenas_version=()
    IFS=" " read -r -a freenas_version < <( grep -i truenas /etc/version )
    if [ ${#freenas_version[@]} -eq 0 ]; then
        IFS=" " read -r -a freenas_version < <( grep -i freenas /etc/version )
    fi

    if [ ${#freenas_version[@]} -eq 0 ] || [ -z "${freenas_version[0]}" ]; then
        freenas_version[0]="UNKNOWN"
    fi

    # Form a unique, timestamped filename for the backup configuration database and tarball
    P1=$(hostname -s)
    P2="${freenas_version[0]}" # we only keep the part: TrueNAS-12.0-U5.1 and omit the build code (6c639bd48a)
    P3=$(date +%Y%m%d%H%M%S)
    backup_archive_name="$P1"-"$P2"-"$P3"

    # Delete any old temporary file:
    echo ""
    echo "---Deleting old temporary files---"
    #find "$tmp_dir" -type f -name '*.db' -print
    find "$tmp_dir" -type f -name '*.db' -exec rm -v {} \;

    # Backup the config database file to the temporary directory
    echo ""
    echo "---Backing up config database---"

    /usr/local/bin/sqlite3 "$config_db_dir/$config_db_name" ".backup main '$tmp_dir/$config_db_name'"

    command_status=$?
    [ "$command_status" -eq 0 ] || show_error "$command_status" "ERROR backing up sqlite database"
    [ "$error_exit" -eq 0 ] || exit "$error_exit"

    echo ""
    echo "> config database backup completed: $tmp_dir/$config_db_name"

    # Check integrity of the sqlite3 backup databse
    echo ""
    echo "---Checking config database backup file integrity---"

    command_status=$(sqlite3 "$tmp_dir/$config_db_name" "pragma integrity_check;")

    if [ "$command_status" = "ok" ]; then
        echo ""
        echo "> config database backup integrity check ok"
    else
        show_error 1 "> config database backup file was corrupted !"
        exit 1
    fi

    target_backup_tarball="$target_dir/$backup_archive_name".tar
    target_backup_sslfile="$target_dir/$backup_archive_name".aes
    target_backup_rarfile="$target_dir/$backup_archive_name".rar
    target_backup_gpgfile="$target_dir/$backup_archive_name".gpg
    target_backup_file=""

    # Compress the TrueNAS password file and config database into a restorable tar file
    # Use encryption if not unset by user
    echo ""
    echo "---Archiving config databse and encryption keys---"

    if [ "$openssl_crypt" = "true" ]; then
        # Encrypted openssl tarball
        echo ""
        echo "> backup using openssl encryption..."

        target_backup_file="$target_backup_sslfile"
        tar -cf - \
            -C "$pwenc_dir" "$pwenc_file" \
            -C "$tmp_dir" "$config_db_name" \
            | openssl enc -e -aes-256-cbc -md sha512 -pbkdf2 -iter "$openssl_iter" -salt -pass file:"$pass_file" -out "$target_backup_file"
        command_status=$?
    elif [ "$rar_crypt" = "true" ]; then
        # Encrypted rar5 tarball
        echo ""
        echo "> backup using rar5 encryption..."

        target_backup_file="$target_backup_rarfile"
        tar -cf - \
            -C "$pwenc_dir" "$pwenc_file" \
            -C "$tmp_dir" "$config_db_name" \
            | $rar a -@ -rr10 -s- -ep -m3 -ma -p"$password" -ilog"$log_file_stderr" "$target_backup_file" -si"$backup_archive_name".tar | sed -e 's/     .*OK/ OK/' -e 's/     .*100%/ 100%/'
              # we run two replace script iterations on the same command "-e", first to keep the last OK and second to keep the last 100%
        command_status=$?
    elif [ "$gpg_crypt" = "true" ]; then
        # Encrypted GnuPG tarball
        echo ""
        echo "> backup using GPG encryption..."

        target_backup_file="$target_backup_gpgfile"
        tar -cf - \
            -C "$pwenc_dir" "$pwenc_file" \
            -C "$tmp_dir" "$config_db_name" \
            | gpg --cipher-algo aes256 --passphrase-file "$pass_file" --pinentry-mode loopback -o "$target_backup_file" --symmetric
              # [--pinentry-mode loopback] option : because of a bug in TrueNAS causing the error "problem with the agent: Invalid IPC response"
              
        command_status=$?
    else
        # Non encrypted backup
        echo ""
        show_error 0 "> WARNING: backup using no encryption..."

        # no encryption is selected, only create a tarball
        # freeBSD tar defaults verbose messages to stderr and always uses stdout as archive destination (pipe)
        # unlike some installers where tar only outputs archive to stdout if we specify '-' as filename or no "-f filename"
        # do not use verbose (tar -cvf), else stderr gets populated with filenames and cron job sends an error
        target_backup_file="$target_backup_tarball"
        tar -cf "$target_backup_file" \
            -C "$pwenc_dir" "$pwenc_file" \
            -C "$tmp_dir" "$config_db_name"
        command_status=$?
    fi

    [ "$command_status" -eq 0 ] || show_error "$command_status" "ERROR backing up settings to $target_backup_file"
    [ "$error_exit" -eq 0 ] || exit "$error_exit"

    echo ""
    echo "> created $target_backup_file"
    echo "    added $pwenc_file"
    echo "    added $config_db_name"

    # Delete temporary files:
    echo ""
    echo "---Deleting temporary files---"
    #find "$tmp_dir" -type f -name '*.db' -print
    find "$tmp_dir" -type f -name '*.db' -exec rm -v {} \;
}

# Remove files older than $keep_days except if in the directory $archive_dir_name
function rm_old_backups() {
    echo ""
    echo "---Pruning backups older than $keep_days days---"
    echo "> searching $target_dir"

    #find "$target_dir" -type f -not -path "*/$archive_dir_name/*" \( -name '*.tar' -o -name '*.aes' -o -name '*.rar' -o -name '*.gpg' \) -mtime +"$keep_days" -print
    find "$target_dir" -type f -not -path "*/$archive_dir_name/*" \( -name '*.tar' -o -name '*.aes' -o -name '*.rar' -o -name '*.gpg' \) -mtime +"$keep_days" -exec rm -v {} \;
}

# Log passed args to stderr and preserve error code from caller
# - call syntax: show_error $? "error msg 1" "error message 2"...
# - after function call, use this line of code: [ "$error_exit" -eq 0 ] || exit "$error_exit"
#   this will exit with "$error_exit" code if previous command failed
# - we do not exit here else stderr gets flushed after the command prompt display
function show_error() {
    # $1 must be an integer value because it is used as a return/exit code
    error_exit="$1"
    if ! [[ "$error_exit" =~ ^[0-9]+$ ]]; then
        {
            echo "INTERNAL ERROR IN FUNCTION show_error()"
            echo "function arg1=$1"
            echo "expected: integer value for arg1"
            date

            echo "-------------------------------------------------"
            echo ""
        } >&2
        exit 1 # fatal error, exit
    fi

    # ensure the function is called with at least two args and that there is an error message to display
    if [ "$#" -lt  2 ] || [ -z "$2" ]; then
        {
            echo "INTERNAL ERROR IN FUNCTION show_error()"
            echo "function arg2 not found or empty string"
            echo "expected arg2 to be a string with error message"
            date

            echo "-------------------------------------------------"
            echo ""
        } >&2
        exit 1 # fatal error, exit
    fi

    # print to stderr each arg (error message) in a separate line
    shift # $1 is now the first error message
    {
        for error_msg in "$@"; do
            echo "$error_msg"
        done

        date

        echo "-------------------------------------------------"
        echo ""
    } >&2

    return "$error_exit" # preserves $? from failed command
}

# Process command line arguments
# - output is not logged to a file but to stderr because the log file is not yet properly set !
# - redirect stdout to stderr for cronjob error alert
function parseArguments() {
    while (( "$#" )); do
        case "$1" in # this will skip and drop any empty argument !
            -rar|--rar-encryption)
                rar_crypt="true"
                shift
                ;;
            -ssl|--openssl-encryption)
                openssl_crypt="true"
                shift
                ;;
            -gpg|--gpg-encryption)
                gpg_crypt="true"
                shift
                ;;
            -no-enc|--no-encryption)
                no_encryption="true"
                shift
                ;;
            -*) # unsupported flags
                show_error 1 "ERROR: Unsupported flag $1"
                exit 1
                ;;
            *) # preserve positional arguments
                POSITIONAL_PARAMS="$POSITIONAL_PARAMS $1"
                shift
                ;;
        esac
    done

    # Set positional arguments in their proper place
    eval set -- "$POSITIONAL_PARAMS"

    # Check arguments logic to avoid redundant / non consistent parameters
    # - error if more than one encryption option is enabled
    encryption_args=("$rar_crypt" "$openssl_crypt" "$gpg_crypt" "$no_encryption")
    count=0
    for flag in "${encryption_args[@]}"; do
        [ "$flag" = "true" ] && ((count++))
    done

    # no encryption option was set, default to openssl encryption
    if [ "$count" -eq 0 ]; then
        openssl_crypt="true"
        echo "Using default openssl encryption"
    fi

    if [ "$count" -gt 1 ]; then
        show_error 1 "ERROR: you cannot enable more than one encryption option '-rar|-ssl|-gpg|-no-enc'"
        exit "$error_exit"
    fi

    # - warn if no encryption is enabled
    #   show_error 0: will cause print to stderr but keep $error_exit to 0
    [ "$no_encryption" = "true" ] && show_error 0 "WARNING: using no encryption is not secure"

    # Parse remaining positional args [target_mount_point] and [filecheck_mount_point]
    # - either we have 2 or no positional arguments (target_mount_point and filecheck_mount_point)
    if [ "$#" -ne 0 ]; then
        [ "$#" -gt 2 ] && show_error 1 "ERROR: syntax error" "Only 2 positional arguments are allowed" "Usage: $script_name [-options] [target_mount_point] [filecheck_mount_point]"
        [ "$error_exit" -eq 0 ] || exit "$error_exit"

        # case using one arg without the other
        [ "$#" -lt 2 ] && show_error 1 "ERROR: syntax error" "'target_mount_point' and 'filecheck_mount_point' cannot be used one without the other" "Usage: $script_name [-options] [target_mount_point] [filecheck_mount_point]"
        [ "$error_exit" -eq 0 ] || exit "$error_exit"

        # case smart *** using: save_config.sh '' '' (never true because 'case "$1" in # ' above will drop any empty argument !)
        [ -z "$1" ] && [ -z "$2" ] && show_error 1 "ERROR: syntax error" "Do not use empty parameters !" "Usage: $script_name [-options] [target_mount_point] [filecheck_mount_point]"
        [ "$error_exit" -eq 0 ] || exit "$error_exit"

        # case using something like: save_config.sh '' "file_name" (never true because 'case "$1" in # ' above will drop any empty argument !)
        [ -n "$1" ] && [ -z "$2" ] && show_error 1 "ERROR: syntax error" "You cannot specify 'target_mount_point' without 'filecheck_mount_point'" "Usage: $script_name [-options] [target_mount_point] [filecheck_mount_point]"
        [ -z "$1" ] && [ -n "$2" ] && show_error 1 "ERROR: syntax error" "You cannot specify 'filecheck_mount_point' without 'target_mount_point'" "Usage: $script_name [-options] [target_mount_point] [filecheck_mount_point]"
        [ "$error_exit" -eq 0 ] || exit "$error_exit"
    fi

    # - override target path if set by positional arguments when calling the script
    if [ -n "$1" ] && [ -n "$2" ]; then
        target_mount_point="$1"
        filecheck_mount_point="$2"
    fi

    # Show effective parameters
    echo "> Flag --rar-encryption=$rar_crypt"
    echo "> Flag --openssl-encryption=$openssl_crypt"
    echo "> Flag --gpg-encryption=$gpg_crypt"
    echo "> Flag --no-encryption=$no_encryption"
    echo "> Positional args=$POSITIONAL_PARAMS"
    echo "> Target mountpoint: $target_mount_point/$filecheck_mount_point"
    echo "> Target directory : $target_mount_point/$backup_dir_name"

    return $?
}

# Print version and syntax
function printVersion() {
    echo ""
    echo "save_config version $version"
    echo "https://github.com/PhilZ-cwm6/truenas_scripts"
    echo "usage: save_config.sh [-options] [target_mount_point] [filecheck_mount_point]"
    echo "- target_mount_point   : target dataset/directory for the backup"
    echo "- filecheck_mount_point: file/dir in 'target_mount_point' to ensure that the target is properly mounted"
    echo "- options : [-rar|--rar-encryption][-ssl|--openssl-encryption][-gpg|--gpg-encryption][-no-enc|--no-encryption]"
    echo "- defaults: backup using openSSL encryption to in-script path 'target_mount_point'"
    echo ""
}

# Parse script arguments
parseArguments "$@" || show_error $? "ERROR parsing script arguments"
[ "$error_exit" -eq 0 ] || exit "$error_exit"

# Check if target and log paths are mounted and writable
# - preserve positional params args (not used currently)
checkBackupPaths $POSITIONAL_PARAMS || show_error $? "ERROR setting backup paths"
[ "$error_exit" -eq 0 ] || exit "$error_exit"

# Start script main function
main "$@"; exit
