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
version=1.3.5

: <<'README.MD'
## pfsense_config.sh

### FUNCTIONS:
- Start inetd configured TFT server to start listening from remote pfsense script
- After a default 15mn delay, turn off the TFTP server
- Move any backup and log files from the TFTP server root to the destination target

### SYNOPSIS:
- Backups are performed and encrypted on the pfsense server using pfsense_send_config.sh script on pfsense
- The pfsense_send_config.sh script on pfsense server sends the encrypted backups and logs on a schedule to the TrueNAS local TFTP Server
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
- backups are stored under `$target_mount_point/pfsense_config` directory
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
README.MD


#  ** Editable paths: >>XXXX <<XXXX **
#***************************************

# Define the backup and logs local target share/dataset
# - target_mount_point: mount point target dataset or directory relative to the main freeBSD host
# - filecheck_mount_point: name of a file or directory in the root of $target_mount_point. Used to verify that the target directory is properly mounted
# >>XXXX
target_mount_point=""
filecheck_mount_point=""
# <<XXXX

# Name of the directory where backups are stored
# - directory will be created under $target_mount_point
# >>XXXX
backup_dir_name="pfsense_config"
# <<XXXX

# TFTP root folder (where source files are sent from pfsense)
# >>XXXX
source_dir=""
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

# Script path and file name
#script_path=$(dirname "$0")
script_name=$(basename "$0")

# Binary paths
# Run 'command -v openssl' to properly set the paths, if they change in a freeBSD release
# >>XXXX
#openssl="/usr/bin/openssl"
#grep="/usr/bin/grep"
#nmap="/usr/local/bin/nmap"
mkdir="/bin/mkdir"
#sed="/usr/bin/sed"
#chown="/usr/sbin/chown"
#chmod="/bin/chmod"
touch="/usr/bin/touch"
sleep="/bin/sleep"
#curl="/usr/local/bin/curl"
#tar="/usr/bin/tar"
#perl="/usr/local/bin/perl"
#tr="/usr/bin/tr"
service="/usr/sbin/service"
cp="/bin/cp"
find="/usr/bin/find"
rm="/bin/rm"
#mv="/bin/mv"
tee="/usr/bin/tee"

# Array with all binary paths to test
binary_paths=( "$mkdir" "$touch" "$sleep" "$service" "$cp" "$find" "$rm" "$tee" )
# <<XXXX

# Backup source files:
# - The temporary remote pfsense logfiles, in the format of yyyymmddhhmmss.$remote_log_filename
#   + configFilenameStartsWith: only files which name starts with this array strings will be copied
#   + configFilenameEndsWith: only files which name ends with this array strings will be copied
#   + remoteLogFilenameEndsWith: the pfsense stdout AND stderr log files are in the format of: *pfsense_send_config.log
#   + remoteErrLogFilenameContains: the pfsense stderr log files are in the format of: __ERROR__*pfsense_send_config.log
configFilenameStartsWith=( "config-pfSense.intranet-" )
configFilenameEndsWith=( ".xml" ".rar" ".gpg" ".tar" )
remoteLogFilenameEndsWith=( "pfsense_send_config.log" )
remoteErrLogFilenameContains=( "__ERROR__" )
#
# - The log files from the remote pfsense_send_config.sh script
remote_log_filename="pfsense_send_config.log"
remote_log_filename_stderr="__ERROR__$remote_log_filename"

# Warn if TFTP server contains more than the specified files number
warn_max_files=20

# Time in seconds to keep the TFTP service listening for new config files
# After elapsed time, tftp service is stopped and the script resumes saving any sent remote config files
tftp_service_timer="900" # 15 minutes
#tftp_service_timer="30"


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

# Return value from show_error() used to keep success/error code status of commands ($?)
# - used to exit on a command error after calling show_error() function
# - only modified by show_error() function
error_exit=0

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
    remote_log_file="$log_path/$remote_log_filename"
    remote_log_file_stderr="$log_path/$remote_log_filename_stderr"

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

    echo ""
    echo "Starting pfSense config files backup"
    tftp_service_listener
    save_config
    save_remote_logfiles
    rm_old_backups

    echo ""
    echo "pfSense config files saved to $target_dir"
    echo "Log file: $log_file"
    echo "pfSense settings backup completed"

    date
    echo ""

} > >($tee -a "$log_file") 2> >($tee -a "$log_file_stderr" | $tee -a "$log_file" >&2)
    # 1rst tee writes {script block} STDOUT (} >) to a file + we preserve it on STDOUT
    # 2nd tee writes {script block} STDERR (2>) to a different file + we redirect 2nd tee STDOUT (actually {script block} STDERR) to 3rd tee
    # 3rd tee writes STDERR to our main log file so that it contains all the screen equivalent output (stdout + stderr)
    # 3d tee redirects its STDOUT back to STDERR so that we preserve {script block} STDERR on the terminal STDERR

# Backup TrueNAS settings
function save_config() {
    # Copy all config files to target directory
    echo ""
    echo "---Saving config files---"
    echo "> Processing config files in $source_dir"

    # Check if source directory exists and can be read
    if ! [ -d "$source_dir" ] || ! [ -r "$source_dir" ]; then
        show_error 1 "ERROR: Cannot find/read source directory: $source_dir"
        [ "$error_exit" -eq 0 ] || exit "$error_exit"
    fi

    # Remove trailing /
    source_dir_new="${source_dir%/}"

    # Start moving config files
    copied_files=0
    for file in "$source_dir_new"/*; do
        # Ensure the returned $file exists in case directory $source_dir does not exist or is empty
        # - in that case, $file gets assigned the "$source_files" literal string
        #   to avoid this, we can also use "shopt -s nullglob" before the loop, then "shopt -u nullglob" after
        filename=$(basename "$file")
        if [ ! -f "$file" ] && [ ! -d "$file" ]; then
            show_error 1 "ERROR: Empty source folder $source_dir"
            exit 1
        fi

        # If it is a directory, continue (non recursive script !)
        if [ -d "$file" ]; then
            show_error 0 "> WARNING: skipped directory $filename"
            continue
        fi

        # If it is a log file, skip it, we will save it later
        if [[ "$file" == *".log" ]]; then
            echo ""
            echo "> Skipped log file for later processing: $filename"
            continue
        fi

        # Ensure files have the proper filename to be considered pfsense config files
        valid_file="false"
        for startStr in "${configFilenameStartsWith[@]}"; do
            # File must start with $startStr
            if [[ "$filename" != "$startStr"* ]]; then
                continue
            fi

            # File must end with a string in $configFilenameEndsWith() array
            for endStr in "${configFilenameEndsWith[@]}"; do
                if [[ "$filename" != *"$endStr" ]]; then
                    continue
                else
                    valid_file="true"
                    break
                fi
            done

            if [ "$valid_file" = "true" ]; then
                echo ""
                echo "> Found valid config file to backup: $filename"
                break
            fi
        done

        if [ "$valid_file" != "true" ]; then
            show_error 0 "> WARNING: skipped an invalid config file: $filename"
            continue
        fi

        # Move the config file to target directory
        # -n: do not ovewrite
        # -v: verbose
        printf "%s" "- Copying config file: "
        $cp -vn "$file" "$target_dir" \
            && printf "%s" "- Deleting old file: " \
            && $rm -v "$file"
        command_status=$?
        [ "$command_status" -eq 0 ] || show_error "$command_status" "ERROR moving config file: $file"
        [ "$error_exit" -eq 0 ] || exit "$error_exit"

        # File saved successfully
        echo "- Properly saved: $filename"
        ((copied_files++))
    done

    # No valid files were found
    if [ "$copied_files" -eq 0 ]; then
        show_error 1 "> ERROR: found no valid config files to backup in $source_dir"
        exit 1
    fi

    # Warn if there are too many files copied
    if [ "$copied_files" -gt "$warn_max_files" ]; then
        show_error 0 "> WARNING: copied too many files: $copied_files"
    fi

    echo ""
    echo "> Moved $copied_files pfSense config files to $target_dir"
}

# TFTP Service start, wait to receive files, then stop
function tftp_service_listener() {
    echo ""
    echo "---Listening for remote config files to be sent---"

    # Check TFTP service status:
    echo "> Starting TFTP service"
    $service inetd onestatus
    command_status=$?

    # Start the TFTP service
    if [ "$command_status" -ne 0 ]; then
        $service inetd onestart
        command_status=$?
        [ "$command_status" -eq 0 ] || show_error "$command_status" "ERROR starting TFTP Service"
        [ "$error_exit" -eq 0 ] || exit "$error_exit"
    else 
        show_error 0 "WARNING: TFTP service already started !"
    fi

    # Wait to receive files
    echo ""
    echo "> TFTP service started, waiting $tftp_service_timer seconds to receive files"
    $sleep "$tftp_service_timer"

    # Stop the service
    echo ""
    echo "> Stopping TFTP service and resuming backup"

    $service inetd onestatus
    command_status=$?
    if [ "$command_status" -eq 0 ]; then
        $service inetd onestop
        command_status=$?
        [ "$command_status" -eq 0 ] || show_error 0 "ERROR: Could not stop TFTP service. Continuing anyway !"
    else 
        show_error 0 "WARNING: TFTP service already stopped !"
    fi
}

# Save log files
function save_remote_logfiles() {
    echo ""
    echo "---Saving pfsense remote log files---"

    # Check if source directory exists and can be read
    if ! [ -d "$source_dir" ] || ! [ -r "$source_dir" ]; then
        show_error 1 "ERROR: Cannot find/read source directory: $source_dir"
        [ "$error_exit" -eq 0 ] || exit "$error_exit"
    fi

    # Remove trailing /
    source_dir_new="${source_dir%/}"

    # Start moving log files
    copied_files=0
    for file in "$source_dir_new"/*; do
        filename=$(basename "$file")
        # Ensure the returned $file exists in case $source_dir is empty directory
        # - in that case, $file gets assigned the "$source_files" literal string
        #   to avoid this, we can also use "shopt -s nullglob" before the loop, then "shopt -u nullglob" after
        if [ ! -f "$file" ] && [ ! -d "$file" ]; then
            show_error 1 "ERROR: Empty source folder $source_dir"
            exit 1
        fi

        # If it is a directory, continue (non recursive script !)
        if [ -d "$file" ]; then
            show_error 0 "> WARNING: skipped directory $file"
            continue
        fi

        # Ensure files have the proper filename to be considered pfsense remote log files
        # If it is a log file, check if it is stdout or stderr log file
        isError_logfile="false"
        for endStr in "${remoteLogFilenameEndsWith[@]}"; do
            # File must end with $endStr to be considered a log file
            if [[ "$filename" != *"$endStr" ]]; then
                show_error 0 "> WARNING: file $file is not a valid remote log file !!"
                continue
            fi

            # We have a valid log file:
            # - If file contains a string in $remoteErrLogFilenameContains() array, it is an error log file
            for errStr in "${remoteErrLogFilenameContains[@]}"; do
                [[ "$filename" == *"$errStr"* ]] && isError_logfile="true"
            done

            break
        done

        # Append log files. Note that files should be listed in natural order,
        # which should be the chronological order because they start with yyyymmddhhmmss
        target_logfile="$remote_log_file"
        [ "$isError_logfile" = "true" ] && target_logfile="$remote_log_file_stderr"

        echo ""
        echo "> Appending $filename to $target_logfile"
        cat "$file" >>"$target_logfile" \
            && printf "%s" "- Deleting uploaded file " \
            && $rm -v "$file"

        command_status=$?
        [ "$command_status" -eq 0 ] || show_error "$command_status" "ERROR appending logfile: $file"
        [ "$error_exit" -eq 0 ] || exit "$error_exit"

        # File saved successfully
        echo "- Properly saved log file $filename"
        ((copied_files++))
    done

    # No valid log files were found
    [ "$copied_files" -eq 0 ] && show_error 1 "> ERROR: found no valid log files to backup in $source_dir"
    [ "$error_exit" -eq 0 ] || exit "$error_exit"

    # Warn if there are too many files copied
    [ "$copied_files" -gt "$warn_max_files" ] && show_error 0 "> WARNING: appended too many log files: $copied_files"

    echo ""
    echo "> Moved $copied_files pfSense log files to $log_path"
}

# Remove files older than $keep_days except if in the directory $archive_dir_name
function rm_old_backups() {
    echo ""
    echo "---Pruning backups older than $keep_days days---"
    echo "> Searching $target_dir"

    #$find "$target_dir" -type f -not -path "*/$archive_dir_name/*" \( -name '*.xml' -o -name '*.rar' -o -name '*.gpg' -o -name '*.tar' \) -mtime +"$keep_days" -print
    $find "$target_dir" -type f -not -path "*/$archive_dir_name/*" \( -name '*.xml' -o -name '*.rar' -o -name '*.gpg' -o -name '*.tar' \) -mtime +"$keep_days" -exec $rm -v {} \;
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
    pos_args=0 # positional args count

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
            -in|--source-dir)
                # First char of $str: $(printf %.1s "$str")
                if [ -n "${2:-}" ] && [ "$(printf %.1s "$2")" != "-" ]; then
                    source_dir="$2"
                    shift 2
                else
                    show_error 1 "ERROR: Argument for $1 is missing" "Usage: $script_name [-options] [target_mount_point] [filecheck_mount_point]"
                    exit 1
                fi
                ;;
            -?|-help)
                printVersion
                shift
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

    # Case no positional args were provided
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

    # Case source dir is not set by arguments or by script variable:
    [ -z "$source_dir" ] && show_error 1 "ERROR: syntax error" "No source directory was specified !" "Usage: $script_name [-options] [target_mount_point] [filecheck_mount_point]"
    [ "$error_exit" -eq 0 ] || exit "$error_exit"

    # Show effective parameters
    echo "> Using below options:"
    echo "  - target mount point: $target_mount_point"
    echo "  - mount point check : $filecheck_mount_point"
    echo "  - source directory  : $source_dir"
}

# Print version and syntax
function printVersion() {
    echo ""
    echo "$script_name version $version"
    echo "https://github.com/PhilZ-cwm6/truenas_scripts"
    echo "usage: $script_name.sh [-options] [target_mount_point] [filecheck_mount_point]"
    echo "- target_mount_point   : target dataset/directory for the backup"
    echo "- filecheck_mount_point: file/dir in 'target_mount_point' to ensure that the target is properly mounted"
    echo "- Options : [-in|--source-dir][-?|-help]"
}

# Parse script arguments
parseArguments "$@" || show_error $? "ERROR parsing script arguments"
[ "$error_exit" -eq 0 ] || exit "$error_exit"

# Check if all the binary paths are properly set
checkBinaries "${binary_paths[@]}"

# Check if target and log paths are mounted and writable
# - preserve positional params args (not used currently)
setBackupPaths "$@" || show_error $? "ERROR setting backup and log paths"
[ "$error_exit" -eq 0 ] || exit "$error_exit"

# Start script main function for backup of config files
# - we redirect stdout to $log_file AND terminal
# - we redirect stderr to $log_file_stderr, $log_file AND terminal
# - terminal and $log_file have both stdout and stderr, while $log_file_stderr only holds stderr
main "$@"; exit
