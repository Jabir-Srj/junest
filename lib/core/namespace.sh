#!/usr/bin/env bash
#
# This module contains all namespace functionalities for JuNest.
#
# http://man7.org/linux/man-pages/man7/namespaces.7.html
# http://man7.org/linux/man-pages/man2/unshare.2.html
#
# Dependencies:
# - lib/utils/utils.sh
# - lib/core/common.sh
#
# vim: ft=sh

CONFIG_PROC_FILE="/proc/config.gz"
CONFIG_BOOT_FILE="/boot/config-$($UNAME -r)"
PROC_USERNS_CLONE_FILE="/proc/sys/kernel/unprivileged_userns_clone"

function _is_user_namespace_enabled() {
    local config_file=""
    if [[ -e $CONFIG_PROC_FILE ]]
    then
        config_file=$CONFIG_PROC_FILE
    elif [[ -e $CONFIG_BOOT_FILE ]]
    then
        config_file=$CONFIG_BOOT_FILE
    else
        return $NOT_EXISTING_FILE
    fi

    if ! zgrep_cmd -q "CONFIG_USER_NS=y" $config_file
    then
        return $NO_CONFIG_FOUND
    fi

    if [[ ! -e $PROC_USERNS_CLONE_FILE ]]
    then
        return 0
    fi

    if ! zgrep_cmd -q "1" $PROC_USERNS_CLONE_FILE
    then
        return $UNPRIVILEGED_USERNS_DISABLED
    fi

    return 0
}

function _check_user_namespace() {
    set +e
    _is_user_namespace_enabled
    case $? in
        $NOT_EXISTING_FILE) warn "Could not understand if user namespace is enabled. No config.gz file found. Proceeding anyway..." ;;
        $NO_CONFIG_FOUND) warn "Unprivileged user namespace is disabled at kernel compile time or kernel too old (<3.8). Proceeding anyway..." ;;
        $UNPRIVILEGED_USERNS_DISABLED) warn "Unprivileged user namespace disabled. Root permissions are required to enable it: sudo sysctl kernel.unprivileged_userns_clone=1" ;;
    esac
    set -e
}

function _run_env_with_namespace(){
    local backend_args="$1"
    shift

    provide_common_bindings
    local bindings=${RESULT}
    unset RESULT

    # Use option -n in groot because umount do not work sometimes.
    # As soon as the process terminates, the namespace
    # will terminate too with its own mounted directories.
    if [[ "$1" != "" ]]
    then
        JUNEST_ENV=1 unshare_cmd --mount --user --map-root-user $GROOT --no-umount --recursive $bindings $backend_args "$JUNEST_HOME" "${SH[@]}" "-c" "$(insert_quotes_on_spaces "${@}")"
    else
        JUNEST_ENV=1 unshare_cmd --mount --user --map-root-user $GROOT --no-umount --recursive $bindings $backend_args "$JUNEST_HOME" "${SH[@]}"
    fi
}


#######################################
# Run JuNest as fakeroot user via user namespace.
#
# Globals:
#   JUNEST_HOME (RO)         : The JuNest home directory.
#   GROOT (RO)               : The groot program.
#   SH (RO)                  : Contains the default command to run in JuNest.
# Arguments:
#   backend_args ($1)        : The arguments to pass to groot
#   no_copy_files ($2?)      : If false it will copy some files in /etc
#                              from host to JuNest environment.
#   cmd ($3-?)               : The command to run inside JuNest environment.
#                              Default command is defined by SH variable.
# Returns:
#   $ARCHITECTURE_MISMATCH   : If host and JuNest architecture are different.
#   Depends on the unshare command outcome.
# Output:
#   -                        : The command output.
#######################################
function run_env_with_namespace() {
    check_nested_env

    local backend_args="$1"
    local no_copy_files="$2"
    shift 2

    _check_user_namespace

    check_same_arch

    if ! $no_copy_files
    then
        copy_common_files
        copy_file /etc/hosts.equiv
        copy_file /etc/netgroup
        copy_file /etc/networks
        # No need for localtime as it is setup during the image build
        #copy_file /etc/localtime
        copy_passwd_and_group
    fi

    _run_env_with_namespace "$backend_args" "$@"
}
