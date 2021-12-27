#!/bin/bash

# Cronjob to start a cascade of "host_config_backup.sh" calls for main host and selected jails
# Script v3.8.4

# Editable paths: >>XXXX <<XXXX

# >>XXXX
# Host name of the main system (TrueNAS)
main_host_name="truenas"

# Path for the scripts to launch
# Usually, you should make $scripts_path_jails a mount point in jail for $config_backup_script_name
config_backup_script_name="host_config_backup.sh"
scripts_path_host="/mnt/my_pool/common/scripts"
scripts_path_jails="/mnt/common/scripts"

# Jails we want to backup users and apps
allJails=(
    "freebsd-main"
    "streaming"
    "unifi"
)
# <<XXXX


#     ** NO FURTHER EDITS ARE NEEDED BELOW **
#**************************************************

# Start main host config backup (users and apps)
bash "$scripts_path_host/$config_backup_script_name" -rar -host "$main_host_name"

# Start jails config backup (users and apps)
for jail in "${allJails[@]}"; do
    iocage exec "$jail" "bash $scripts_path_jails/$config_backup_script_name -rar -host $jail"
done

# Rotate logs

