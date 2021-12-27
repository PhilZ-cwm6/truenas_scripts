#!/bin/bash

# !!! THIS SCRIPT MUST RUN ON THE TRUENAS OR JAIL TO BACKUP !!!
# !!! Started with root priviledges !!!

# SpellCheck validated at https://www.shellcheck.net/
# - no warnings

# Exit on unset variables (-u), return error if any command fails in a pipe (-o pipefail)
# -f: we need globbing in the "for file in" curl loop
# -e: we do not want to exit on each error, because errors are managed in script and logged
# with -u: to check if an arg is set we must use [ -n "${2:-}" ], that is expand to empty string if $2 is unset
set -u -o pipefail

# Script version
version=3.8.8

: <<'README.MD'
## host_config_backup.sh

### FUNCTIONS
- Backup freebsd host and jails apps or any custom paths (SSH/SSL, apache24, baikal, sql, plex, miniDLNA, unifi...)
- Backup users home directories include root of the main host and jails
- TrueNAS host backup: started as root from the main OS
- Jails backup: started as root user inside the booted jail client
- Can be automated using complementary `backup_cronjob.sh` script
- Backups are encrypted in openssl
- Backup files can also be encrypted using rar, gpg or stored as non encrypted tar
- Decrypt/Extract an openssl, rar, gpg or tar backup file

### SYNOPSIS
- The script must be started from inside the host specified by the mandatory command line option `-host|--host-name`
- Backups are performed and encrypted on the TrueNAS/FreeNAS main host or in the jail
- The backups and logs are stored locally on the TrueNAS server
- The default storage locations for backup and log files are respectively `$target_mount_point/$host_name` and `$target_mount_point/logs` directories
- The target local directory `$target_mount_point` can be overriden either by command line or by editing in script variables:
  + `$main_target_mount_point` : target mount point for the main freeBSD host (TrueNAS/FreeNAS)
  + `$jails_target_mount_point`: target mount point for the jails
  + `$jails_target_mount_point` can be a mount point shared with the main host and pointing to same directory as `$main_target_mount_point`
- If specified by command line, the `target_mount_point` option will override `$main_target_mount_point` and  `$jails_target_mount_point`
- The name of the local subdirectory `$host_name` is the hostname of the TrueNAS/jail server to backup AND must be specified by command line option `-host|--host-name`
- This choice is by design to double check that user specified the proper host to backup and started the script from that host
- This limitation can be bypassed by using the batch script `backup_cronjob.sh` to backup multiple jails and the host in a single cron job
<br /><br />
- By default, an openssl aes256 encryped backup file is generated
- Optionally, encrypted rar5 or gpg files can be generated or even a non compressed tar file
- Multiple output formats can be specified at the same time
- If no file format is specified, script will assume the openssl encryption as default
- This default file format can be changed by editing in script value `$default_encryption`
<br /><br />
- Decrypting backup files is done with the `-d|--decrypt` option, associated with `-in|--input-file` option
- Optional decrypting options are `-out|--out-dir` (output directory) and any input file format option `-ssl|-rar|-gpg|-tar`
- See below examples for how to decrypt
<br /><br />
- A password file containing the encryption/decryption password must be used
- Empty passwords are not allowed
- Default password file is `script_path/script_basename.pass`
- Password file can be set to a different location either in script using `$pass_file` variable or using `-pf|--passfile` option
- Script doesn't support providing password from the command line for security reasons
- Prompt for password is not supported so that script can always be started from a cron job

### SYNTAX
    script_name.sh [-options][Positional params]

#### USAGE
    script_name.sh [-host|--host-name] [-options] [target_mount_point] [filecheck_mount_point]

#### Positional Parameters
    - target_mount_point   : Taget dataset/directory where the config files will be saved
    - filecheck_mount_point: Name of a file or directory in the root of $target_mount_point.
                             Used to verify that the target directory is properly mounted
                             `$target_mount_point/$filecheck_mount_point` must exist as a file or directory

- if omitted, you must edit below `$main_target_mount_point`, `$jails_target_mount_point` and `$filecheck_mount_point` variables
- when provided by command line, they will override the inscript variables
- backups are stored under `$target_mount_point/$host_name` directory
- logs are created under a directory: `$target_mount_point/logs`

#### Options
    [-host|--host-name]
    [-ssl|--ssl-encryption][-rar|--rar-encryption][-gpg|--gpg-encryption]
    [-tar|--unencrypted-tar][-iter|--iterations-count][-pf|--passfile]
    [-?|--help]

#### Decrypt options
    [-d|--decrypt][-in|--input-file][-out|--out-dir]
    [file format option][-iter|--iterations-count][-pf|--passfile]

#### Options details
    -host|--host-name        : specify the short hostname to backup, that is hostname without domain name. Exp: `unifi-jail.local` -> `unifi-jail`
                               script must be started from inside the specified hostname
    -ssl|--ssl-encryption    : generate an openssl encrypted backup
    -rar|--rar-encryption    : generate a RAR5 AES256 encrypted backup. You must install rar binary
    -gpg|--gpg-encryption    : generate a GnuPG AES256 encrypted backup (GPG)
    -tar|--unencrypted-tar   : generate a tar file with no encryption, strongly not recommended.
                               will generate a warning to stderr
    -iter|--iterations-count : set a custom iterations count, overrides `$openssl_iter` variable
                               by default, if not set by options and `$openssl_iter` is kept as empty string in script,
                               it will use default openssl value
    -pf|--passfile           : path to a file containing the password for backup or decryption
                               will override `$pass_file` variable in script
                               if not set either in script neither by command option, it will default to `script_path/script_basename.pass`
    -d|--decrypt             : decrypt mode
    -in|--input-file         : file to decrypt
    -out|--out-dir           : directory where uncrypted files will be extracted.
                               if omitted, extracts to a `config.NNNN` directory created in local directory

- if no encryption option is specified, use default encryption set in variable `$default_encryption`

### INSTALLATION
- plan the dataset where you will copy the script, ideally to a unix dataset (not windows SMB)
- exp: /mnt/my_pool/my_dataset
- SSH / shell into TrueNAS as root
- create a directory to hold your scripts and ensure it can only be read by root to prevent access to your passwords
- in the jails to backup, add the dataset as a mount point in the jail. Exp. `/mnt/my_dataset`
```
mkdir /mnt/my_pool/my_dataset/scripts
chmod 700 scripts
chown root:wheel scripts
```
- copy the `host_config_backup.sh` file to the scripts directory and ensure it can only be executed by root
```
cp host_config_backup.sh /mnt/my_pool/my_dataset/scripts/
chmod 700 /mnt/my_pool/my_dataset/scripts/host_config_backup.sh
chown root:wheel /mnt/my_pool/my_dataset/scripts/host_config_backup.sh
```
- create the file with your passphrase and ensure it is only readable by root
```
cd /mnt/my_pool/my_dataset/scripts
touch host_config_backup.pass
chmod 600 host_config_backup.pass
chown root:wheel host_config_backup.pass
```
- type in your password in the created pass file, either in nano/vi or using echo (less secure)
```
echo 'my_super_pass' >host_config_backup.pass
```
- edit the in script associative arrays and create new ones with your jails names, apps names and apps paths<br />
  Let's suppose that we have a jail named `my_jail` hosting two apps, `minidlna` and `unifi_controller`<br />
  We want to backup:<br />
  `unifi_controller` database twice a week at 7pm<br />
  `unifi_controller` backup folder daily at 7pm<br />
  `minidlna` custom conf on each run<br />
  `minidlna` init.d file on 1st and 15th day of the month at 8am
  <br /><br />
  We should do the below edits of the apps and paths arrays:
  + APP PATHS AND SCHEDULE: define custom arrays with the paths and schedule for each app:
    ```
    unifi_controller_paths=( "/usr/local/share/java/unifi/data" "Sun,Mon,19h"
                             "/usr/local/share/java/unifi/data/backup" "19h"
    )
    minidlna_paths=( "/usr/local/etc/minidlna.conf" "always"
                     "/usr/local/etc/rc.d/minidlna" "1,15,8h"
    )
    ```
    You can add as much path/schedule pairs as you want per app.<br />
    Above example will backup:<br />
        `/usr/local/share/java/unifi/data` directory only on Sundays, Mondays if it is 19:00-19:59 hour<br />
        `/usr/local/share/java/unifi/data/backup` directory everyday if it is 19:00-19:59 hour<br />
        `/usr/local/etc/minidlna.conf` file on each run<br />
        `/usr/local/etc/rc.d/minidlna` file on first and 15th of the month if it is 8:00-8:59 am
  <br /><br />
  + APP NAMES POINTING TO THEIR ABOVE PATHS:<br />
    app `unifi_controller` has above `unifi_controller_paths` paths<br />
    app `minidlna` has above `minidlna_paths` paths
    ```
    allAppPaths[unifi_controller]=unifi_controller_paths[@]
    allAppPaths[minidlna]=minidlna_paths[@]
    ```
  + ALL APPS LOADED BY EACH HOST:
    ```
    allAppsIn_my_jail=( "unifi_controller"
                        "minidlna"
    )
    ```
  + ALL HOSTS WITH THE APPS THEY HOST DEFINED ABOVE
    ```
    allAppsInHost[my_jail]=allAppsIn_my_jail[@]
    ```
  + Start the script from `my_jail` jail with command: `host_config_backup.sh -host 'my_jail' '/mnt/settings/backups' '.settings.online'`
  + This will create backups under `/mnt/settings/backups/my_jail/` directory
  + Backups will include all user directories under `/home` and the `/root` user directory
  + App backups will include `minidlna_paths`and `unifi_controller_paths` specified above

### EXAMPLES
- Exp 1:
  ```
  host_config_backup.sh -host truenas
  ```
    - will save the backup files in default openssl encrypted format and store them in local directory `$target_mount_point/truenas`
    - the default openssl iterations count is used
    - `$main_target_mount_point` and `$filecheck_mount_point` variables must be set in script

- Exp 2:
  ```
  host_config_backup.sh -host 'plex_jail' -rar -gpg -ssl -tar -p /mnt/scripts/my_passfile.pass
  ```
    - will save the backup files in encrypted openssl format, and also to rar, gpg and tar formats
    - backups will be stored under `$jail_target_mount_point/plex_jail/` directory
    - `$jail_target_mount_point` and `$filecheck_mount_point` variables must be set in script
    - read password from file `/mnt/scripts/my_passfile.pass`

- Exp 3:
  ```
  host_config_backup.sh -host mysql -rar -ssl -iter 9000000 "/mnt/config" ".config.online"
  ```
    - generate an openssl and a rar encrypted backups
    - the encrypted ssl file will have 900000 iterations
    - backup files are created in `/mnt/config/mysql` directory
    - script will check if `/mnt/config/.config.online` file or dir exists to ensure `/mnt/config` is mounted
    - the log files will be saved to `/mnt/config/logs` directory
    - this will override any `$filecheck_mount_point` and `$jail_target_mount_point` variables in script

- Exp 4:
  ```
  host_config_backup.sh -d -in encrypted-file.aes -iter 500000
  ```
    - decrypt the `encrypted-file.aes`, assuming default ssl format but with a custom 500000 iterations count
    - output file is created in local directory under a subdirectory named `config.NNNN`

- Exp 5:
  ```
  host_config_backup.sh -d -rar -in /path/to/encrypted-config.rar -out /home/admin/config -p /pool/data/home/user/my_passfile.pass
  ```
    - decrypt the rar `encrypted-config.rar` file and output to the directory `/home/admin/config`
    - read password from file `/pool/data/home/user/my_passfile.pass`

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
# - jails_target_mount_point: mount point target dataset or directory relative to the jail host
#   Usually, it should be a mountpoint in jail for $target_mount_point
# - filecheck_mount_point: name of a file or directory in the root of $target_mount_point.
#   Used to verify that the target directory is properly mounted
# >>XXXX
main_target_mount_point="/mnt/my_pool/settings"
jails_target_mount_point="/mnt/settings"
filecheck_mount_point=".share.online"
# <<XXXX

# Set the main TrueNAS hostname
# Used to ensure we are backing up a jail or the main host
# - main_hostname: host name of the main OS hosting the jails
# >>XXXX
main_hostname="truenas"
# <<XXXX

### SOURCE FILES/DIRS TO BACKUP ###
# Set the home directory where user directories to backup are located
# - home_dir_main: home dir of users in the main freebsd host
# - home_dir_jails: home dir of users in the jails, usually /home
# - root user located at /root will always be backed up
# >>XXXX
home_dir_main="/mnt/my_pool/home"
home_dir_jails="/home"
# <<XXXX

# Set users directories, apps and config paths to backup (users, ssl, ssh, baikal, apache, plex, minidlna...)
# !! URGENT !!
# - spaces are supported, but special care must be taken to always quote the variables even in the for loops
# - do not end a directory path with '/' if you want to recursively backup its subdirectories
# - add '/' at end of dir name to not recursively backup its subdirectories
# - adding '/*' at end of dir name will also recurse into subdirectories, but it is not recommended !
#
# Init an array for each app to backup. It holds all the app config paths that we want to backup
# format is: appname_paths=("path1" "schedule1" "path 2" "schedule 2" "my path 3" "schedule 3")
# - path: the file/directory path to backup
# - schedule: a string to set schedule days and/or optionally schedule hours on which the specified path will be backed up
#   + multiple days/hours can be set, separated by ',' sign without spaces
#   + at least one schedule hour or one schedule day option must be specified, else the backup will not proceed
#   + if a schedule hour is specified along a schedule day, both must match
#   + if multiple schedule days and hours are specified, the backup will proceed if there is a day AND hour match
#   + if a schedule days are specified without a schedule hour, the backup will bw done on each run on a matching day
#   + can be any of the below values:
#       * always: path backup is created on any day/hour, will override any other schedule day/hour
#       * daily : path backup is created on any day. If a schedule hour is specified, it must also match
#                 will override any other specified day option
#       * day of the week short format: Mon,Tue,Wed,Thu,Fri,Sat,Sun
#       * day of the week long format: Monday,Tuesdaye,Wednesday,Thursday,Friday,Saturday,Sunday
#       * day number of the month: 1-31 or 01-31 format
#       * hour of the day: 1H-24H, or 1h-24h, or 01H-24H, or 01h-24h
#   + if the current date doesn't match the specified string, path backup is skipped
#   + exp: "daily,9h,20h"   : backup every day on 9h and 20h
#          "Mon,Fri,02H"    : backup each monday and friday at 2 am
#          "10,31"          : backup each 10 and 31th day of the month at any hour
#          "daily"          : without a schedule hur, will act like 'always' and backup on each script run
#          "daily,Mon,31,9h : daily at 9h am
# - array name (appname): user defined. Used to identify the app and as a name for the target backup directories of the app
# - spaces are supported if quoted

# >>XXXX
## USER'S DIRECTORIES PATHS AND SCHEDULE
# - main host users home directories
users_home_main=(
    "/root"             "always"
    "$home_dir_main"    "always"
)

# - jails users home directories
users_home_jails=(
    "/root"             "always"
    "$home_dir_jails"   "always"
)

## APP PATHS AND SCHEDULE:
# - common scripts app config files
common_paths=(
    "/mnt/my_pool/common/bash"                   "always"
    "/mnt/my_pool/common/minidlna/config.bak"    "always"
    "/mnt/my_pool/common/nano"                   "always"
    "/mnt/my_pool/common/rar"                    "always"
    "/mnt/my_pool/common/scripts"                "always"
    "/mnt/my_pool/common/tmux"                   "always"
)

# - ssl app certificates for all system + apache24
ssl_paths=("/etc/ssl"   "always")

# - sshd daemon config files (port, rules...)
sshd_paths=("/etc/ssh"  "always")

# - apache24 app .conf files
apache24_paths=("/usr/local/etc/apache24"   "always")

# - baikal app config and database
baikal_paths=("/usr/local/www/apache24/data/baikal" "always")

# - minidlna app config files (database/thumbs is not backed up to spare disk space)
minidlna_paths=(
    "/usr/local/etc/minidlna.conf"  "always"
    "/usr/local/etc/rc.d/minidlna"  "always"
)

# - unifi controller app data directory
unifi_controller_paths=(
    "/usr/local/share/java/unifi/data"          "Sun,20h"
    "/usr/local/share/java/unifi/data/backup"   "always"
)

# - plexmedia app config files
plexmedia_paths=(
    "undefined_path"    "always"
)

## APP NAMES POINTING TO THEIR ABOVE PATHS:
# Declare an associative array with each app name:
# - allAppPaths[appname]=appname_paths[@]
# - appname: user defined. Used to identify the app and as a name for the target backup directory of the app
# - appname_paths[@]: we init it our array to the above defined app paths array
declare -A allAppPaths
allAppPaths[host_users]="users_home_main[@]"
allAppPaths[jail_users]="users_home_jails[@]"
allAppPaths[common]="common_paths[@]"
allAppPaths[ssl]="ssl_paths[@]"
allAppPaths[sshd]="sshd_paths[@]"
allAppPaths[apache24]="apache24_paths[@]"
allAppPaths[baikal]="baikal_paths[@]"
allAppPaths[minidlna]="minidlna_paths[@]"
allAppPaths[unifi_controller]="unifi_controller_paths[@]"
allAppPaths[plexmedia]="plexmedia_paths[@]"

## ALL APPS LOADED BY EACH HOST
# Init an array for each jail/OS, and set the items to the app names holded by the os/jail
# - format is: allAppsIn_hostname=("appname 1" "appname 2"...)
# - hostname: must match the hostname to backup, hostname is passed to the script as an argument
# - appname: must match an allAppPaths[appname] array index appname
# - if no apps are to backup in hostname, init it with: allAppsIn_hostname=()

# truenas main host /mnt/common settings and scripts
allAppsIn_truenas=(
    "host_users"
    "common"
)

# freebsd-main host has the ssl, sshd, apache24 and baikal apps to backup
allAppsIn_freebsdmain=(
    "jail_users"
    "ssl"
    "sshd"
    "apache24"
    "baikal"
)

# streaming host has minidlna app to backup
allAppsIn_streaming=(
    "jail_users"
    "minidlna"
)

# unifi host has unifi controller app to backup
allAppsIn_unifi=(
    "jail_users"
    "unifi_controller"
)

# plexmedia host has plexmedia app to backup
allAppsIn_plexmedia=(
    "jail_users"
    "plexmedia"
)

## ALL HOSTS WITH THE APPS THEY HOST DEFINED ABOVE
# Declare an associative array for each OS/jail to backup and init it. Format is:
# - allAppsInHost[hostname]=allAppsIn_hostname[@]
# - [hostname]:
#   + must match the jail/OS hostname to backup
#   + it is passed as an argument to the script
#   + will be used as the target directory name for OS/jail backup
declare -A allAppsInHost
allAppsInHost[truenas]="allAppsIn_truenas[@]"
allAppsInHost[freebsd-main]="allAppsIn_freebsdmain[@]"
allAppsInHost[streaming]="allAppsIn_streaming[@]"
allAppsInHost[unifi]="allAppsIn_unifi[@]"
allAppsInHost[plexmedia]="allAppsIn_plexmedia[@]"
# <<XXXX


#  ** BELOW  >>XXXX <<XXXX editable paths are optional ! **
#************************************************************

# Option to prune archive files older than x days
# If you manually move an archive file to the target subdirectory 'archive_dir_name', it will be excluded from pruning
# - keep_days: max days before deleting backup
# - archive_dir_name: dir name where backups will not be pruned if older than $keep_days
# >>XXXX
keep_days=180
archive_dir_name="keep"
# <<XXXX

# Paths where rar and gpg optional commands are installed
# - do not add these to ${binary_paths[@]} because they are optional, and checked on use
# >>XXXX
#rar="/usr/local/bin/rar"
rar="/root/bin/rar"
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
service="/usr/sbin/service"
#cp="/bin/cp"
find="/usr/bin/find"
rm="/bin/rm"
#mv="/bin/mv"
tee="/usr/bin/tee"
#cut="/usr/bin/cut"
dirname="/usr/bin/dirname"
basename="/usr/bin/basename"
cat="/bin/cat"
hostname="/bin/hostname"
ls="/bin/ls"

# Array with all binary paths to test
# - rar and gpg are optional and tested before operations
binary_paths=( "$openssl" "$grep" "$mkdir" "$sed" "$chown" "$chmod" "$touch" "$tar" "$service" "$find" "$rm" "$tee" "$dirname" "$basename" "$cat" "$hostname" "$ls" )
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

# Backup Password file path: the path for a file containing the password when using encryption
# - can be overriden by [-pf|--passfile] option
# - if not set here or by command option, it will default to : 
#   + a password file in the same directory as this script file
#   + with same file name as the script file name
#   + but with last extension replaced by .pass
# >>XXXX
pass_file=""
# <<XXXX


#  ** NO FURTHER EDITS ARE NEEDED BELOW **
#*******************************************

# Global variables for the functions
# - target_mount_point: either main_target_mount_point or jail_target_mount_point depending if it is a jail or main host
# - host_name: the actual hostname running the script, can be a jail or main TrueNAS host
# - is_jail: if true, functions assume backup from a jail
# - target_dir: directory path where the backup files will be stored ($target_mount_point/$host_name)
# - log_path: directory path where log files will be stored ($target_mount_point/logs)
# - log_file: path to stdout+stderr log file ($log_path/$log_file_name)
# - log_file_stderr: path to stderr log file ($log_path/$log_file_name_stderr)
# - POSITIONAL_PARAMS: array with all positional arguments (args without "-" prefix)
declare target_mount_point
declare host_name
declare is_jail
declare target_dir
declare log_path
declare log_file
declare log_file_stderr
declare -a POSITIONAL_PARAMS

# Encryption option settings.
# - If none is specified, use default output format specified in $default_encryption variable
# - If set here to true, they cannot be toggled off by command line option
# - openssl_crypt [-ssl|--ssl-encryption]:
#   + generate an encrypted openssl backup file
#   + if $openssl_iter is left empty, use default openssl iter count
# - openssl_iter [-iter|--iterations-count]: an integer
#   + pbkdf2 iterations: start with 300000 and increase depending on your CPU speed
#   + significant only if openssl_crypt is true
#   + set to empty string for default openssl pbkdf2 iteration count,
#     currently of 10000 as per source code (too low, security wise)
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
declare curr_date

# On script error exit, check if post app backup tasks need to be performed
# - exp: start/stop a service
post_process_app=""

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
    # Double check we have a valid host name specified by command line option
    [ -z "$host_name" ] && show_error 1 "ERROR: Internal Error" "setBackupPaths() empty host name !"
    [ "$error_exit" -eq 0 ] || exit "$error_exit"

    # Get the actual hostname running the script, can be a jail or main TrueNAS host
    # Used to double check the host name for security before backups
    # -s, --short: Display the host name cut at the first dot (truenas.intranet -> truenas)
    current_host=$($hostname -s)
    [ -z "$current_host" ] && show_error 1 "ERROR: Failed to get current hostname"
    [ "$error_exit" -eq 0 ] || exit "$error_exit"

    # Ensure the host name specified by command line option is the actual running host/jail
    # we double check the host name for security
    [ "$current_host" != "$host_name" ] && show_error 1 "ERROR: HOST NAME MISMATCH" "Specified host '$host_name' dosesn't match the current host '$current_host'" \
                                                            "You must run the script from the same host specified by option -host"
    [ "$error_exit" -eq 0 ] || exit "$error_exit"

    # Check if it is the main TrueNAS host, else assume it is a jail
    is_jail="true"
    [ "$host_name" = "$main_hostname" ] && is_jail="false"

    # Set the target mount point if it was not set by command line option
    # - ${target_mount_point+x}: if $target_mount_point is unset or empty, expand to empty string, else to 'x'
    #   needed because $target_mount_point can be unset at this point and we use 'set -u' so script will error and stop on -z test
    # - properly set it depending on the host to backup if it is a jail or the main TrueNAS host
    if [ -z "${target_mount_point+x}" ]; then
        target_mount_point="$main_target_mount_point"
        [ "$is_jail" = "true" ] && target_mount_point="$jails_target_mount_point"
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
            "Ensure the target directory is mounted and the below file/dir exists at its root:" \
            "$target_mount_point/$filecheck_mount_point"
        exit 1
    fi

    # - ensure the target directory is writable
    if [ ! -w "$target_mount_point" ]; then
        show_error 1 "ERROR: TARGET DIRECTORY NOT WRITABLE" \
            "Ensure the target directory is properly mounted and writable by current user:" \
            "$target_mount_point"
        exit 1
    fi

    # - set the target and log paths
    target_dir="$target_mount_point/$host_name"
    log_path="$target_mount_point/logs"
    log_file_name="$host_name-config.log"
    log_file="$log_path/$log_file_name"

    log_file_name_stderr="__ERROR__$host_name-config.log"
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

    # Reset internal bash timer:
    # used to display script execution duration at the end
    SECONDS=0

    # Create the backup target
    $mkdir -p "$target_dir" || show_error $? "ERROR creating target directory: $target_dir"
    [ "$error_exit" -eq 0 ] || exit "$error_exit"

    # chmod/chown the target_dir so that only root can access it
    # - left to the user to respect any SMB/ACLs existing permissions
    #$chown root:wheel "$target_dir" || show_error $? "ERROR setting owner of target directory: $target_dir"
    #[ "$error_exit" -eq 0 ] || exit "$error_exit"

    #$chmod 700 "$target_dir" || show_error $? "ERROR setting permissions of target directory: $target_dir"
    #[ "$error_exit" -eq 0 ] || exit "$error_exit"

    # Start the backup
    echo ""
    echo "Starting backup of <$host_name> config"

    curr_date=$(date +"%Y.%m.%d_%H.%M.%S")
    save_config
    rm_old_backups

    # Display elapsed time in hh:mm:ss
    elapsed_time=$(printf "%02d:%02d:%02d" "$((SECONDS/3600))" "$(((SECONDS/60)%60))" "$((SECONDS%60))")

    echo ""
    echo "All settings saved to $target_dir"
    echo "Log file: $log_file"
    echo "Backup of <$host_name> completed in $elapsed_time"

    date
    echo ""
} > >(tee -a "$log_file") 2> >(tee -a "$log_file_stderr" "$log_file" >&2)
    # redirect both stderr and stdout to $log_file AND to terminal + redirect stderr to $log_file_stderr

# Backup users and apps defined paths
function save_config() {
    echo ""
    echo "---Saving <$host_name> apps and settings---"

    # Set an array with all app names in $host_name
    apps_in_host=("${!allAppsInHost[$host_name]}")

    echo ">>> Found ${#apps_in_host[@]} apps(s) to backup"

    # Ensure at least one output format was set
    [ "$openssl_crypt" != "true" ] && [ "$rar_crypt" != "true" ] \
        && [ "$gpg_crypt" != "true" ] && [ "$tar_no_crypt" != "true" ] \
        && show_error 1 "ERROR: Internal Error" "save_config(): No output format provided !"

    [ "$error_exit" -eq 0 ] || exit "$error_exit"

    # For each app in <$host_name>, generate a list with paths scheduled for a backup
    i=1
    for appname in "${apps_in_host[@]}"; do
        #echo "allAppPaths[$appname] = ${!allAppPaths[$appname]}" # prints all paths for $appname
        app_paths=("${!allAppPaths[$appname]}") # array with all path/schedule pairs for the app $appname
        #app_paths_items=$((${#app_paths[@]}/2))  # number of paths to backup
        sched_app_paths=() # array with the app paths that will be backed up if they are scheduled
        dest_dir="$target_dir/$appname"
        dest_file="$appname" # we add extension (aes, rar, gpg, tar) later
        app_target="$dest_dir/$dest_file"

        echo ""
        echo ">>> $i". "$appname"
        ((i++))

        # Check source app paths to backup if each path is scheduled for a backup or not
        # - if not scheduled, skip backup for the given path
        # Check scheduled paths to backup if they exist or are empty directories
        # - if file/directory item to backup is not found: fatal error (output to stderr and exit script)
        # - if all app paths are empty directories: warn (stderr output but continue)
        #echo "   all paths: ${app_paths[@]}"
        echo ">> Checking app source paths to backup:"
        for ((j=0; j<${#app_paths[@]}; j=$((j+2)))); do
            app_path_url="${app_paths[j]}"

            # Check schedule state for the current app path
            # read the ',' separated schedule times into app_path_schedules() array
            sched_index=$((j+1))
            app_path_schedules=()

            # Without IFS:
            #readarray -t -d ',' app_path_schedules < <(printf "${app_paths[$sched_index]}")

            # Set an array with all schedule entries for the app path
            IFS=',' read -r -a app_path_schedules <<< "${app_paths[$sched_index]}"

            # Check if schedule allows backup to be done for the current path
            # - by default, if no schedule hour is specified, backup on any hour if it is a schedule day
            # - if a schedule hour is specified, to backup, we must also match the schedule day
            has_a_schedule_day="false"
            has_a_schedule_hour="false"
            is_schedule_day="false"
            is_schedule_hour="false"
            is_scheduled="false"
            for schedule_time in "${app_path_schedules[@]}"; do
                if [ "$schedule_time" = "always" ]; then
                    # 'always' option overrides any other schedule entry
                    is_schedule_day="true"
                    is_schedule_hour="true"
                    break;
                elif [ "$schedule_time" = "daily" ]; then
                    has_a_schedule_day="true"
                    is_schedule_day="true"
                    continue
                elif [[ "${schedule_time:~0}" =~ ^(h|H)$ ]]; then
                    # Last char is a 'H' or 'h': hour of the day schedule specified
                    has_a_schedule_hour="true"

                    # remove last char (h or H)
                    schedule_time="${schedule_time::-1}"

                    # get current hour of the day in decimal format (00-24)
                    current_time=$(date +'%H')
                    [ "$schedule_time" = "$current_time" ] && is_schedule_hour="true" && continue

                    # get current hour of the day in decimal format (1-24), single digits are preceded by a blank !
                    # remove leading whitespace character
                    current_time=$(date +'%k')
                    current_time="${current_time#' '}"
                    [ "$schedule_time" = "$current_time" ] && is_schedule_hour="true" && continue
                else
                    # assume it is a schedule day
                    has_a_schedule_day="true"
                    # - day of the week short format: Mon,Tue,Wed,Thu,Fri,Sat,Sun
                    current_time=$(date +'%a')
                    [ "$schedule_time" = "$current_time" ] && is_schedule_day="true" && continue

                    # - day of the week long format: Monday,Tuesdaye,Wednesday,Thursday,Friday,Saturday,Sunday
                    current_time=$(date +'%A')
                    [ "$schedule_time" = "$current_time" ] && is_schedule_day="true" && continue

                    # - day number of the month (1-31), single digits are preceded by a blank !
                    #   remove leading whitespace character
                    current_time=$(date +'%e')
                    current_time="${current_time#' '}"
                    [ "$schedule_time" = "$current_time" ] && is_schedule_day="true" && continue

                    # - day number of the month, as a decimal number (01-31)
                    #   remove leading whitespace character
                    current_time=$(date +'%d')
                    current_time="${current_time#' '}"
                    [ "$schedule_time" = "$current_time" ] && is_schedule_day="true" && continue
                fi
            done

            # The backup of app path can be scheduled if:
            # - both a schedule day and schedule hour matched, or if 'always' schedule option was specified
            [ "$is_schedule_day" = "true" ] && [ "$is_schedule_hour" = "true" ] && is_scheduled="true"

            # - we have a matching schedule day and no schedule hour was specified
            [ "$is_schedule_day" = "true" ] && [ "$has_a_schedule_hour" = "false" ] && is_scheduled="true"

            # - we have a matching schedule hour and no schedule day was specified
            [ "$has_a_schedule_day" = "false" ] && [ "$has_a_schedule_hour" = "true" ] && is_scheduled="true"

            # In all other cases, the app path is not scheduled for a backup (include if no valid option was set or empty string)
            if [ "$is_scheduled" != "true" ]; then
                echo "> $app_path_url"
                echo "  (-) skipped: schedule=${app_paths[$sched_index]}"
                continue
            fi

            # Check if file/directory app path exists
            if [ ! -f "$app_path_url" ] && [ ! -d "$app_path_url" ]; then
                show_error 1 "> $app_path_url (NOT FOUND)" "" "ERROR: APP PATH NOT FOUND"
                [ "$error_exit" -eq 0 ] || exit "$error_exit"
            fi

            # Check if it is a directory and not empty before saving
            if [ -d "$app_path_url" ] && [ -z "$(ls -A "$app_path_url")" ]; then
                show_error 0 "> $app_path_url" \
                             "  (!) empty directory - skipped"
                continue
            fi

            # Add the path to the list of paths to backup
            sched_app_paths+=("$app_path_url")
            echo "> $app_path_url"
            echo "  (+) queued for backup"
        done

        # If all app path items are empty directories or app has no scheduled paths to backup
        # then, skip creating an app archive with only empty directories
        # Note: if a directory or file to backup is not found, script breaks in previous step !
        if [ ${#sched_app_paths[@]} -eq 0 ]; then
            echo ""
            echo ">> Skipping backup of '$appname'"
            continue
        fi

        # Create app target directory and the $archive_dir_name where user can move files that script will not prune after $keep_days
        # - if create the target directories fails: fatal error (output to stderr and exit script)
        echo ""
        echo ">> Creating target directory:"
        echo "   $appname --> $dest_dir"
        mkdir -p "$dest_dir/$archive_dir_name" || show_error $? "ERROR creating directory: $dest_dir/$archive_dir_name"
        [ "$error_exit" -eq 0 ] || exit "$error_exit"

        # Check if specific app tasks are needed before backup
        appCustomTasks "$appname" "pre_process"

        # Backup apps
        echo ""
        echo ">> Compressing $appname"

        target_filename="$app_target-$curr_date"
        [ "$openssl_crypt" = "true" ] && save_openssl "$target_filename.aes" "${sched_app_paths[@]}"
        [ "$rar_crypt" = "true" ] && save_rar "$target_filename.rar" "${sched_app_paths[@]}"
        [ "$gpg_crypt" = "true" ] && save_gpg "$target_filename.gpg" "${sched_app_paths[@]}"
        [ "$tar_no_crypt" = "true" ] && save_decrypted "$target_filename.tar" "${sched_app_paths[@]}"

        # Check if specific app tasks are needed after backup
        appCustomTasks "$appname" "post_process"

        echo ""
        echo ">> Saved <$appname> to $dest_dir"
    done

    echo ""
    echo ">>> All <$host_name> Apps saved to $dest_dir"
}

# Do some specific app tasks before/after backup
function appCustomTasks() {
    [ $# -ne 2 ] && show_error 1 "ERROR: Internal Error" "appCustomTasks() needs 2 arguments, received $# args"
    [ "$error_exit" -eq 0 ] || exit "$error_exit"

    app="$1"
    process_type="$2"
    if [ "$app" = "unifi_controller" ]; then
        if [ "$process_type" = "pre_process" ]; then
            # Set variable to inform that we will need post backup tasks for the current app
            # only used on an unexpected exit, like error, not Ctrl^C and other interrupts
            post_process_app="$app"

            # Stop the unifi service to backup controller data folder
            # This will also stop the mongod service
            echo ""
            echo ">> Stopping unifi service"
            $service unifi status # if it is not started, message is printed to stdout, but command returns 1
            command_status=$?

            if [ "$command_status" -eq 0 ]; then
                # 'service stop' command outputs some errors to stderr if child processes are not found, even if command succeeds
                # This is the case with unifi service and we always get message to stderr: 'kill: ?????: No such process'
                # We redirect stderr to a variable, print it to stdout, but choose to print it or not to stderr
                # - redirect stderr to a variable, stdout to $out_fd fd, then to stdout, then delete $out_fd fd
                # - also, preserve command return code in $command_status
                { stderr_msg=$($service unifi stop 2>&1 1>&$out_fd); command_status=$? ;} {out_fd}>&1 ; exec {out_fd}>&-

                # - print the stderr to our stdout like in all script
                echo "$stderr_msg"

                # - print stderr to stderr if it contains other lines not containing 'No such process' message 
                echo "$stderr_msg" | grep -v "No such process" 1>&2

                # - check success status of 'service unifi stop' command
                [ "$command_status" -eq 0 ] || show_error 0 "ERROR: Could not stop unifi service. Continuing anyway !"
            else 
                show_error 0 "WARNING: unifi service already stopped !"
            fi
        elif [ "$process_type" = "post_process" ]; then
            # After backup, restart unifi service
            echo ""
            echo ">> Starting unifi service"
            $service unifi status
            command_status=$?

            if [ "$command_status" -ne 0 ]; then
                $service unifi start
                command_status=$?
                [ "$command_status" -eq 0 ] || show_error 0 "ERROR starting unifi Service. Continuing anyway !"
            else 
                show_error 0 "WARNING: unifi service already started !"
            fi

            # on error exit, no need to do another post backup process
            post_process_app=""
        else
            show_error 1 "ERROR: Internal Error" "appCustomTasks() invalid arg 2 value: $process_type"
            [ "$error_exit" -eq 0 ] || exit "$error_exit"
        fi
    fi
}

# OpenSSL encrypted backup file
function save_openssl() {
    [ $# -lt 2 ] && show_error 1 "ERROR: Internal Error" "save_openssl() needs at least 2 arguments, received $# args"
    [ "$error_exit" -eq 0 ] || exit "$error_exit"

    target="$1"
    shift
    source=("$@")
    if [ -z "$target" ] || [ -z "${source[*]}" ]; then
        show_error 1 "ERROR: Internal Error" "save_openssl() received empty args: target=$target , source=${source[*]}"
        [ "$error_exit" -eq 0 ] || exit "$error_exit"
    fi

    echo ""
    echo ">> Openssl backup to $target_dir"

    # Get the encryption password and assign it to $password
    # - for openssl, we only need to check if pass file exists
    #password=""
    get_password

    # Check iterations count if set in script or by command line option
    # - case iter_count is empty string: use default openssl command iterations count
    if [ -n "$openssl_iter" ]; then
        # ensure the specified iter count is an integer
        is_unsigned_integer "$openssl_iter" || show_error 1 "ERROR: iteration count invalid option: $openssl_iter"
        [ "$error_exit" -eq 0 ] || exit "$error_exit"
    fi

    # Format tar source files to silent errors:
    # - only accept full paths to properly silent 'tar: Removing leading '/' from member names' printed to stderr
    # - new_source(): array with source paths trimmed from their leading '/' char
    # - exclude_options(): array with exclude option tar syntax for all socket files found, without the leading '/' char
    # - tar_source_excludes: populate the new_source() and exclude_options() arrays
    new_source=()
    exclude_options=()
    tar_source_excludes "${source[@]}"

    # Encrypted openssl tarball
    # ${openssl_iter:+-iter}: If $openssl_iter is null or unset, nothing is substituted, otherwise the expansion of '-iter' word is substituted.
    # - using "$openssl_iter" causes openssl error 'empty string option'
    # - instead of using $openssl_iter unquoted, we use 'unquoted expansion with an alternate value'
    #   it allows the unquoted empty default value without error, while the non empty $openssl_iter is quoted
    #   https://github.com/koalaman/shellcheck/wiki/SC2086
    $tar -cf - "${exclude_options[@]}" -C / "${new_source[@]}" | \
        $openssl enc -e -aes-256-cbc -md sha512 -pbkdf2 ${openssl_iter:+-iter} ${openssl_iter:+"$openssl_iter"} -salt -pass file:"$pass_file" -out "$target"

    command_status=$?
    [ "$command_status" -eq 0 ] || show_error "$command_status" "ERROR creating openssl encrypted backup: $target"
    [ "$error_exit" -eq 0 ] || exit "$error_exit"

    echo ""
    echo "> OpenSSL file saved: $target"
}

# RAR encrypted backup file
function save_rar() {
    [ $# -lt 2 ] && show_error 1 "ERROR: Internal Error" "save_rar() needs at least 2 arguments, received $# args"
    [ "$error_exit" -eq 0 ] || exit "$error_exit"

    target="$1"
    shift
    source=("$@")
    if [ -z "$target" ] || [ -z "${source[*]}" ]; then
        show_error 1 "ERROR: Internal Error" "save_rar() received empty args: target=$target , source=${source[*]}"
        [ "$error_exit" -eq 0 ] || exit "$error_exit"
    fi

    echo ""
    echo ">> RAR backup to $target_dir"

    # Check if rar binary is available
    [ -f "$rar" ] || show_error 1 "ERROR: cannot find rar commad: $rar"
    [ "$error_exit" -eq 0 ] || exit "$error_exit"

    # Get the encryption password and assign it to $password
    password=""
    get_password

    # Backup using rar encryption
    # - rar: only append created archive file name to log file (-logpa) and errors (-ilog) + suppress STDOUT except if it contains "*ERROR:*"
    # - grep: return true even if 'ERROR:' pattern is not found, else our pipe fails with set -o pipefail
    $rar a -ow -@ -rr10 -s- -ep2 -m3 -ma -x"*.rar" -logpa="$log_file" -ilog"$log_file_stderr" -p"$password" "$target" "${source[@]}" | \
         { $grep ".*ERROR:.*" || : ;}

    # print everything but remove text after 5 spaces "     " for each line (do not show the backspace chars), cf. "rar progress output" comment for explanation
    #$rar a -ow -@ -rr10 -s- -ep2 -m3 -ma -x"*.rar" -ilog"$log_file_stderr" -p"$password" -ag-YYYY.MM.DD_HH.MM.SS-NN "$target" "${source[@]}" | \
    #    $sed -e 's/     .*OK/ OK/' -e 's/     .*100%/ 100%/'

    command_status=$?
    [ "$command_status" -eq 0 ] || show_error "$command_status" "ERROR creating rar encrypted backup: $target"
    [ "$error_exit" -eq 0 ] || exit "$error_exit"

    echo ""
    echo "> RAR file saved: $target"
}

# GnuPG encrypted backup file
function save_gpg() {
    [ $# -lt 2 ] && show_error 1 "ERROR: Internal Error" "save_gpg() needs at least 2 arguments, received $# args"
    [ "$error_exit" -eq 0 ] || exit "$error_exit"

    target="$1"
    shift
    source=("$@")
    if [ -z "$target" ] || [ -z "${source[*]}" ]; then
        show_error 1 "ERROR: Internal Error" "save_gpg() received empty args: target=$target , source=${source[*]}"
        [ "$error_exit" -eq 0 ] || exit "$error_exit"
    fi

    echo ""
    echo ">> GPG backup to $target_dir"

    # Check if gpg binary is available
    [ -f "$gpg" ] || show_error 1 "ERROR: cannot find gpg commad: $gpg"
    [ "$error_exit" -eq 0 ] || exit "$error_exit"

    # Get the encryption password and assign it to $password
    # - for gpg, we only need to check if pass file exists
    #password=""
    get_password

    # Format tar source files to silent errors:
    # - only accept full paths to properly silent 'tar: Removing leading '/' from member names' printed to stderr
    # - new_source(): array with source paths trimmed from their leading '/' char
    # - exclude_options(): array with exclude option tar syntax for all socket files found, without the leading '/' char
    # - tar_source_excludes: populate the new_source() and exclude_options() arrays
    new_source=()
    exclude_options=()
    tar_source_excludes "${source[@]}"

    # Encrypted GnuPG tarball
    $tar -cf - "${exclude_options[@]}" -C / "${new_source[@]}" | \
        $gpg --cipher-algo aes256 --pinentry-mode loopback --passphrase-file "$pass_file" -o "$target" --symmetric
        # [--pinentry-mode loopback] : needed in new gpg for supplying unencryped passwords on command line. Else, we get the error "problem with the agent: Invalid IPC response"

    command_status=$?
    [ "$command_status" -eq 0 ] || show_error "$command_status" "ERROR creating gpg encrypted backup: $target"
    [ "$error_exit" -eq 0 ] || exit "$error_exit"

    echo ""
    echo "> GPG file saved: $target"
}

# TAR non-encrypted backup file
function save_decrypted() {
    [ $# -lt 2 ] && show_error 1 "ERROR: Internal Error" "save_decrypted() needs at least 2 arguments, received $# args"
    [ "$error_exit" -eq 0 ] || exit "$error_exit"

    target="$1"
    shift
    source=("$@")
    if [ -z "$target" ] || [ -z "${source[*]}" ]; then
        show_error 1 "ERROR: Internal Error" "save_decrypted() received empty args: target=$target , source=${source[*]}"
        [ "$error_exit" -eq 0 ] || exit "$error_exit"
    fi

    echo ""
    echo ">> TAR backup to $target_dir"

    # Print warning to stderr
    show_error 0 "WARNING: backup using no encryption..."

    # Format tar source files to silent errors:
    # - only accept full paths to properly silent 'tar: Removing leading '/' from member names' printed to stderr
    # - new_source(): array with source paths trimmed from their leading '/' char
    # - exclude_options(): array with exclude option tar syntax for all socket files found, without the leading '/' char
    # - tar_source_excludes: populate the new_source() and exclude_options() arrays
    new_source=()
    exclude_options=()
    tar_source_excludes "${source[@]}"

    # no encryption is selected, only create a tarball
    # freeBSD tar defaults verbose messages to stderr and always uses stdout as archive destination (pipe)
    # unlike some installers where tar only outputs archive to stdout if we specify '-' as filename or no "-f filename"
    # do not use verbose (tar -cvf), else stderr gets populated with filenames and cron job sends an error
    $tar -cf "$target" "${exclude_options[@]}" -C / "${new_source[@]}"
    #$tar -cvf "$target" "${new_source[@]}"

    command_status=$?
    [ "$command_status" -eq 0 ] || show_error "$command_status" "ERROR creating non-encrypted backup: $target"
    [ "$error_exit" -eq 0 ] || exit "$error_exit"

    echo ""
    echo "> TAR file saved: $target"
}

# Format tar source files to silent errors:
# - accept a list of full paths as arguments
# - only accepts fulls paths: ensure there is a leading '/' in each source file or fail
# - trim the leading '/' from each source path argument and add the new trimmed path
#   to new_source() array. It is needed because we use 'tar -C /' option to stop
#   error message 'tar: Removing leading '/' from member names' from being printed to stderr
# - search for socket files in each source path and add them to socket_files() array
#   because tar has no option to skip them and will print a warning to stderr
# - format exclude_options() array with tar excluded socket files list without the leading '/'
#
# Code variables:
# - new_source(): array with source paths trimmed from their leading '/' char
#   !! must be defined by caller !!
# - exclude_options(): array with exclude option tar syntax for all socket files found, without the leading '/' char
#   !! must be defined by caller !!
# - 'find -type s -print0': print socket file names separated by null char instead of new lines
#   this will preserve file names with '\n'
# - readarray -d -O [last_index] $'\0': read from output to array, assuming null char as delimiter
#   + -O [last_index]: do not overwrite the array with next paths results but append to the existing array
#   + it is the same as using readarray -d '' array
function tar_source_excludes() {
    echo "> Check source paths and exclude socket files"

    # Ensure it is called with at least one path argument
    [ $# -eq 0 ] && show_error 1 "ERROR: Internal Error" "tar_source_excludes() received no args"
    [ "$error_exit" -eq 0 ] || exit "$error_exit"

    # Array with list of socket files FULL paths found in the backup paths
    socket_files=()
    for path in "$@"; do
        # accept only full path sources
        [ "${path::1}" = "/" ] || show_error 1 "ERROR: ${FUNCNAME[1]} compression format only accepts full paths to backup" "Received relative path: $path"
        [ "$error_exit" -eq 0 ] || exit "$error_exit"

        # trim leading '/' from source files/dirs to allow using 'tar -C /' option
        # and init new_source() array with the trimmed paths
        new_source+=("${path#/}")

        # init socket_files() array with all socket files in paths list
        readarray -d $'\0' -O "${#socket_files[@]}" socket_files < <($find "$path" -type s -print0)
    done

    # Add each socket file to the tar exclusion list
    # ${x#/}: remove leading '/' from excluded file names because we use 'tar -C /' option
    for x in "${socket_files[@]}"; do
        echo "  - exclude socket file: $x"
        exclude_options+=("--exclude=${x#/}")
    done

: <<'DEBUG_CODE'
    echo "DEBUG new_source=${new_source[*]}"
    echo "DEBUG socket_files=${socket_files[*]}"
    echo "DEBUG exclude_options=${exclude_options[*]}"
DEBUG_CODE
}

# Decrypt config file
function decrypt_config() {
    echo ""
    echo "---Decrypting config files---"
    echo "> Input file: $input_file"

    # Check decryption options
    [ "$decrypt_mode" != "true" ] && show_error 1 "ERROR: Internal Error" "decrypt_config(): decrypt_mode=$decrypt_mode"
    [ "$error_exit" -eq 0 ] || exit "$error_exit"

    [ -z "$input_file" ] && show_error 1 "ERROR: Internal Error" "decrypt_config(): empty input_file"
    [ "$error_exit" -eq 0 ] || exit "$error_exit"

    # Check that there are no multiple decryption formats set to true (in script edits)
    count=0
    [ "$openssl_crypt" = "true" ] && count=$((count + 1))
    [ "$rar_crypt" = "true" ] && count=$((count + 1))
    [ "$gpg_crypt" = "true" ] && count=$((count + 1))
    [ "$tar_no_crypt" = "true" ] && count=$((count + 1))
    [ $count -ne 1 ] && show_error 1 "ERROR: Internal Error" "decrypt_config(): $count encryption formats specified"
    [ "$error_exit" -eq 0 ] || exit "$error_exit"

    if [ ! -f "$input_file" ] || [ ! -r "$input_file" ]; then 
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
    else show_error 1 "ERROR: Internal Error" "decrypt_config(): input file format not specified"
    fi

    [ "$error_exit" -eq 0 ] || exit "$error_exit"
    
    echo "> Config file extracted to $out_path"
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
        is_unsigned_integer "$openssl_iter" || show_error 1 "ERROR: iteration count invalid option: $openssl_iter"
        [ "$error_exit" -eq 0 ] || exit "$error_exit"
    fi

    # Decrypt config file
    $openssl enc -d -aes-256-cbc -salt -md sha512 -pbkdf2 ${openssl_iter:+-iter} ${openssl_iter:+"$openssl_iter"} -in "$input_file" -pass file:"$pass_file" | \
        $tar -xvf - -C "$out_path"
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
    out_path="${out_path%/}" # remove trailing /
    $rar x -p"$password" "$input_file" "$out_path/"

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
    # If password file is not set in script or by -pf|--passfile option,
    # then default to /script_path/script_basename.pass
    if [ -z "$pass_file" ]; then
        script_path=$($dirname "$0")
        script_name=$($basename "$0")
        pass_file_name="${script_name%.*}.pass" # scriptname.sh becomes scriptname
        pass_file="$script_path/$pass_file_name"
    fi

    #password=$(<"$pass_file") # bash only
    password=$($cat "$pass_file")
    [ -z "$password" ] && show_error 1 "ERROR: no password was set" "you must specify a password in $pass_file" "Or you can set the passfile path using -pf|--passfile option"
    [ "$error_exit" -eq 0 ] || exit "$error_exit"
}

# Check if a received arg is an integer (exclude -/+ signs)
function is_unsigned_integer() {
    command_status=1
    [ $# -ne 1 ] && show_error 1 "ERROR: Internal Error" "is_unsigned_integer() needs one argument"
    [ "$error_exit" -eq 0 ] || exit "$error_exit"

    # Bash only
    [[ "$1" =~ ^[0-9]+$ ]] && command_status=0 # is an integer

    return "$command_status"

: <<'POSIX_CODE'
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
POSIX_CODE
}

: <<'COMMENTED_CODE'
# Check if a received arg is a signed integer (include -/+ leading signs)
function is_signed_integer() {
    command_status=1
    [ $# -ne 1 ] && show_error 1 "ERROR: Internal Error" "is_signed_integer() needs one argument"
    [ "$error_exit" -eq 0 ] || exit "$error_exit"

    # Bash only
    [[ "$1" =~ ^[+-]?[0-9]+$ ]] && command_status=0 # is a signed integer
    return "$command_status"

: <<'POSIX_CODE'
    # Posix compatible
    case ${1#[-+]} in
        *[!0-9]*|'')
            # Not a signed integer
            return "$command_status"
            ;;
        *)
            # is a valid signed integer
            command_status=0
            return "$command_status"
            ;;
    esac
POSIX_CODE
}
COMMENTED_CODE

# Log passed args to stderr and preserve error code from caller
# - call syntax: show_error $? "error msg 1" "error message 2"...
# - after function call, use this line of code: [ "$error_exit" -eq 0 ] || exit "$error_exit"
#   this will exit with "$error_exit" code if previous command failed
# - we do not exit here else stderr gets flushed after the command prompt display
function show_error() {
    # $1 must be an integer value because it is used as a return/exit code
    error_time=$(date)

    if ! is_unsigned_integer "$1"; then
        {
            echo "INTERNAL ERROR IN FUNCTION show_error()"
            echo "function arg1=$1"
            echo "expected: integer value for arg1"

            printf "!!!! %s !!!!\n" "$error_time"
            echo ""
        } >&2
        exit 1 # fatal error, exit
    fi

    # Ensure the function is called with at least two args and that there is an error message to display
    if [ "$#" -lt  2 ] || [ -z "$2" ]; then
        {
            echo "INTERNAL ERROR IN FUNCTION show_error()"
            echo "function arg2 not found or empty string"
            echo "expected arg2 to be a string with error message"

            printf "!!!! %s !!!!\n" "$error_time"
            echo ""
        } >&2
        exit 1 # fatal error, exit
    fi

    # Set error exit
    error_exit="$1"

    # Print to stderr each arg (error message) in a separate line
    shift # $1 is now the first error message
    {
        for error_msg in "$@"; do
            echo "$error_msg"
        done

        printf "!!!! %s !!!!\n" "$error_time"
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
    pos_args=0      # positional args count
    enc_options=0   # encryption args count
    dec_options=0   # decryption args count
    iter_arg=0      # -iter|--iterations-count options used
    passfile_arg=0  # -pf|--passfile option used
    host_options=0  # -host|--host-name option used

    script_name=$($basename "$0")

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
                    is_unsigned_integer "$2" || show_error 1 "ERROR: syntax error" "Iterations count must be a number" "Usage: $script_name [-options] [target_mount_point] [filecheck_mount_point]"
                    [ "$error_exit" -eq 0 ] || exit "$error_exit"

                    openssl_iter="$2"
                    iter_arg=1
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
            -pf|--passfile)
                # First char of $str: $(printf %.1s "$str")
                if [ -n "${2:-}" ] && [ "$(printf %.1s "$2")" != "-" ]; then
                    pass_file="$2"
                    passfile_arg=1
                    shift 2
                else
                    show_error 1 "ERROR: Argument for $1 is missing" "Usage: $script_name [-options] [target_mount_point] [filecheck_mount_point]"
                    exit 1
                fi
                ;;
            -host|--host-name)
                # First char of $str: $(printf %.1s "$str")
                if [ -n "${2:-}" ] && [ "$(printf %.1s "$2")" != "-" ]; then
                    host_name="$2"
                    host_options=$((host_options + 1))
                    shift 2
                else
                    show_error 1 "ERROR: Argument for $1 is missing" "Usage: $script_name [-options] [target_mount_point] [filecheck_mount_point]"
                    exit 1
                fi
                ;;
            -?|--help)
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

    # Some useless, non harmful associations in backup/decrypt modes that would be ignored if not checked here
    # -iter without -ssl in backup mode
    [ "$iter_arg" -ne 0 ] && [ "$openssl_crypt" != "true" ] && \
        show_error 1 "ERROR: syntax error" "-iter|--iterations-count option only useful in openssl format" "Usage: $script_name [-options] [target_mount_point] [filecheck_mount_point]"
    [ "$error_exit" -eq 0 ] || exit "$error_exit"

    # -pf|--passfile without any encrypted format
    [ "$passfile_arg" -ne 0 ] && [ "$openssl_crypt" != "true" ] && [ "$rar_crypt" != "true" ] && [ "$gpg_crypt" != "true" ] && \
        show_error 1 "ERROR: syntax error" "-pf|--passfile option only useful with encrypted formats" "Usage: $script_name [-options] [target_mount_point] [filecheck_mount_point]"
    [ "$error_exit" -eq 0 ] || exit "$error_exit"
    

    # Specific encryption/decryption options rules
    if [ $dec_options -ne 0 ]; then
        # decryption option must be used (-d|--decrypt)
        [ "$decrypt_mode" != "true" ] && show_error 1 "ERROR: syntax error" "in/out options need --decrypt option" "Usage: $script_name [-options] [target_mount_point] [filecheck_mount_point]"
        [ "$error_exit" -eq 0 ] || exit "$error_exit"

        # input file is mandatory
        [ -z "$input_file" ] && show_error 1 "ERROR: syntax error: Missing input file to decrypt" "Usage: $script_name [-options] [target_mount_point] [filecheck_mount_point]"
        [ "$error_exit" -eq 0 ] || exit "$error_exit"

        # positional args are not used
        [ $pos_args -ne 0 ] && show_error 1 "ERROR: syntax error: Positional arguments cannot be used in decryption mode" "Usage: $script_name [-options] [target_mount_point] [filecheck_mount_point]"
        [ "$error_exit" -eq 0 ] || exit "$error_exit"

        # only one input format can be specified
        # note: if more than a default format option was altered in script, check it in decrypt_config()
        [ $enc_options -gt 1 ] && show_error 1 "ERROR: syntax error: Only one input format can be specified for decryption" "Usage: $script_name [-options] [target_mount_point] [filecheck_mount_point]"
        [ "$error_exit" -eq 0 ] || exit "$error_exit"

        # host option has no meaning in decrypt mode
        [ $host_options -ne 0 ] && show_error 1 "ERROR: syntax error: Host options cannot be specified for decryption" "Usage: $script_name [-options] [target_mount_point] [filecheck_mount_point]"
        [ "$error_exit" -eq 0 ] || exit "$error_exit"
    else
        # backup mode
        # Case no -host|--host-name option provided
        [ $host_options -ne 1 ] && show_error 1 "ERROR: syntax error" "You must specify one host name with -host option" "Usage: $script_name [-options] [target_mount_point] [filecheck_mount_point]"
        [ "$error_exit" -eq 0 ] || exit "$error_exit"
    fi

    # Show effective parameters
    # - target_mount_point: if not set by command line option, it will be unset at this stage
    # - host_name: will be unset at this stage in decryption mode
    echo "> Using below options:"
    echo "  - target mount point: ${target_mount_point:-}" # expand to empty string if $target_mount_point is null or unset
    echo "  - mount point check : $filecheck_mount_point"
    echo "  - openssl encryption: $openssl_crypt"
    echo "  - rar encryption    : $rar_crypt"
    echo "  - gpg encryption    : $gpg_crypt"
    echo "  - tar compression   : $tar_no_crypt"
    echo "  - custom iterations : $openssl_iter"
    echo "  - decrypt mode      : $decrypt_mode"
    echo "    + input file      : $input_file"
    echo "    + output directory: $out_path"
    echo "  - host name         : ${host_name:-}" # expand to empty string if $target_mount_point is null or unset
}

# Print version and syntax
function printVersion() {
    script_name=$($basename "$0")

    echo ""
    echo "$script_name version $version"
    echo "https://github.com/PhilZ-cwm6/truenas_scripts"
    echo "usage: $script_name.sh [-options] [target_mount_point] [filecheck_mount_point]"
    echo "- target_mount_point   : target dataset/directory for the backup"
    echo "- filecheck_mount_point: file/dir in 'target_mount_point' to ensure that the target is properly mounted"
    echo "- Options : [-ssl|--ssl-encryption][-rar|--rar-encryption][-gpg|--gpg-encryption]"
    echo "            [-tar|--unencrypted-tar][-iter|--iterations-count][-pf|--passfile]"
    echo "            [-host|--host-name]"
    echo "            [-?|--help]"
    echo "- Decrypt : [-d|--decrypt][-in|--input-file][-out|--out-dir][file format option]"
    echo "            [-iter|--iterations-count][-pf|--passfile]"
    echo "- Defaults: backup using 'default_encryption' to in-script path 'target_mount_point'"
}

# Check if all the binary paths are properly set
checkBinaries "${binary_paths[@]}"

# Parse script arguments
parseArguments "$@" || show_error $? "ERROR parsing script arguments"
[ "$error_exit" -eq 0 ] || exit "$error_exit"

# If we are decrypting a config file, no logging or other tasks are processed
if [ "$decrypt_mode" = "true" ]; then
    decrypt_config
    exit $?
fi

# Check if target and log paths are mounted and writable
# - preserve positional params args (not used currently)
setBackupPaths "$@" || show_error $? "ERROR setting backup and log paths"
[ "$error_exit" -eq 0 ] || exit "$error_exit"

# Trap to cleanup temp files before main function
# - Called on signal EXIT
function sig_clean_exit() {
    # save the return code of the script
    err=$?

    # reset trap for all signals to not interrupt post_process on any next signal
    trap '' EXIT INT QUIT TERM

    appCustomTasks "$post_process_app" "post_process"
    exit $err # exit the script with saved $?
}

# - Set the signal traps
trap sig_clean_exit EXIT

# Start script main function
main "$@"; exit