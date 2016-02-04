#!/bin/bash

##################################################
# _| || |_| |   / / |   (_)         / /      | |
#|_  __  _| |  / /| |__  _ _ __    / /_ _ ___| |__
# _| || |_| | / / | '_ \| | '_ \  / / _` / __| '_ \
#|_  __  _|_|/ /  | |_) | | | | |/ / (_| \__ \ | | |
#  |_||_| (_)_/   |_.__/|_|_| |_/_/ \__,_|___/_| |_|
##################################################

# Types
Ash__true="true"
Ash__false="false"

# Importing .ashrc
Ash_rc_file="$HOME/.ashrc"
if [[ -e "$Ash_rc_file" ]]; then
    . "$Ash_rc_file"
fi

# Constants
Ash_config_filename="ash_config.yaml"
Ash_modules_filename="ash_modules.yaml"
Ash__modules_foldername="ash_modules"
Ash_module_callable_file="callable.sh"
Ash_module_lib_directory="lib"
Ash_global_modules_directory="global_modules"
Ash_core_modules_directory="core_modules"
Ash_module_classes_folder="classes"
Ash_module_aliases_file="module_aliases.yaml"

# Directories + files
Ash__call_directory="$( pwd )"
Ash_config_file="$Ash__call_directory/$Ash_config_filename"
Ash_modules_file="$Ash__call_directory/$Ash_modules_filename"
Ash_modules_directory="$Ash__call_directory/$Ash__modules_foldername"
Ash_source_file=$(readlink ${BASH_SOURCE[0]})
Ash__source_directory="$(dirname "$Ash_source_file")"
Ash__active_module_directory="" # Determined at runtime

# Platform
Ash__active_platform=''
Ash__PLATFORM_UNKNOWN='unknown'
Ash__PLATFORM_LINUX='linux'
Ash__PLATFORM_FREEBSD='freebsd'
Ash__PLATFORM_DARWIN='darwin'

# ===============================================================
# =========================== Util ==============================
# ===============================================================

#################################################
# Determines the active platform and wraps the
# result into an enumerated easily testable value
#################################################
Ash_determine_platform() {
    local platform="$Ash__PLATFORM_UNKNOWN"
    local uname_string=$(uname)
    if [[ "$uname_string" == 'Linux' ]]; then
        platform="$Ash__PLATFORM_LINUX"
    elif [[ "$uname_string" == 'FreeBSD' ]]; then
        platform="$Ash__PLATFORM_FREEBSD"
    elif [[ "$uname_string" == 'Darwin' ]]; then
        platform="$Ash__PLATFORM_DARWIN"
    fi

    echo "$platform"
}

#################################################
# Autoloads an entire directory, non recursive.
#
# @param $1: The directory to autoload
#################################################
Ash_autoload() {
    for file in "$1"/*; do
        if [[ -f "$file" ]]; then
            . "$file"
        fi
    done
}

#################################################
# Autoloads a modules lib directory.
# Exits if it fails to find the lib directory.
#
# @param $1: The module to load
# @param $2: 1 if we should check aliases, 0 otherwise
#       it is safe to omit this parameter if you don't
#       need to check aliases
#################################################
Ash__import() {
    local module_directory="$(Ash_find_module_directory "$1" "$2")"
    if [[ -d "$module_directory" ]]; then
        Ash_autoload "$module_directory/$Ash_module_lib_directory"
    else
        Logger__error "Attempted to import $1 but could not find module"
        exit
    fi
}

#################################################
# Finds the module directory
#
# Checks local first, then checks global if
# there is nothing in global
#
# @param $1: The module to find
# @param $2: 1 if we should check aliases, 0 otherwise
#################################################
Ash_find_module_directory() {
    local directory=""

    # Checking Core
    local core_module_directory="$Ash__source_directory/$Ash_core_modules_directory"
    directory=$(Ash_find_module_directory_single "$1" "$2" "$core_module_directory")
    if [[ "$directory" != "" ]]; then
        echo "$directory"
        return
    fi

    # Checking Local
    local local_module_directory="$Ash__call_directory/$Ash__modules_foldername"
    directory=$(Ash_find_module_directory_single "$1" "$2" "$local_module_directory")
    if [[ "$directory" != "" ]]; then
        echo "$directory"
        return
    fi

    # Checking Global
    local global_module_directory="$Ash__source_directory/$Ash_global_modules_directory"
    directory=$(Ash_find_module_directory_single "$1" "$2" "$global_module_directory")
    if [[ "$directory" != "" ]]; then
        echo "$directory"
        return
    fi
}

#################################################
# Attempts to find a modules directory from
# a single module location
#
# @param $1: The module to find
# @param $2: 1 if we should check aliases, 0 otherwise
# @param $3: The module directory to check in
#################################################
Ash_find_module_directory_single() {
    local module="$1"
    local check_aliases="$2"
    local module_directory="$3"

    # Checking if we should expand aliases
    if [[ "$check_aliases" -eq 1 ]]; then
        local aliases_file="$module_directory/$Ash_module_aliases_file"
        if [[ -f "$aliases_file" ]]; then
            # Expanding aliases
            eval $(YamlParse__parse "$aliases_file" "Ash_alias_")

            local alias_variable="Ash_alias_$module"
            if [[ ${!alias_variable} != "" ]]; then
                module=${!alias_variable}
            fi
        fi
    fi

    # Checking if module directory exists
    local module="$module_directory/$module"
    if [[ -d $module ]]; then
        echo "$module"
        return
    fi
}

#################################################
# This function will echo 1 if $1 is a function,
# 0 otherise.
#
# @param $1: The string to test if it's a function
#################################################
Ash__is_function() {
    if [ -n "$(type -t "$1")" ] && [ "$(type -t "$1")" = function ]; then
        echo 1
    else
        echo 0
    fi
}

# ===============================================================
# ========================= Dispatch ============================
# ===============================================================

#################################################
# Loads the correct module's callable file
# to be ready to be called
#
# All callable functions will be called with
# {module}:{function_name}.  This function parses
# out both components and handles them appropriately.
#
# @params $@: All parameters passed to Ash
#################################################
Ash_dispatch() {
    local position=1
    IFS=':' read -ra segment <<< "$1"
    for part in "${segment[@]}"; do
        if [[ "$position" -eq 1 ]]; then
            Ash_load_callable_file "$part"
            Ash__import "$part" "1"
        elif [[ "$position" -eq 2 ]]; then
            Ash_execute_callable "$part" "${@:2}"
            return
        fi
        position=$((position+1))
    done

    # Can only reach here if didn't have two parts
    Ash_execute_callable "main" "${@:2}"
}

#################################################
# Loads the correct module callable file
#
# @param $1: The module name
#################################################
Ash_load_callable_file() {
    Ash__active_module_directory="$(Ash_find_module_directory "$1" "1")"
    Obj__classes_directory="$Ash__active_module_directory/$Ash_module_classes_folder"
    local callable_file="$Ash__active_module_directory/$Ash_module_callable_file"
    if [ -e "$callable_file" ]; then
        # Loading up callable file
        . "$callable_file"

        # Loading in config
        local config="$Ash__active_module_directory/$Ash_config_filename"
        eval $(YamlParse__parse "$config" "Ash_module_config_")

        # Updating Logger's prefix
        Logger__set_prefix "$Ash_module_config_name"
    else
        Logger__error "Module '$part' is unknown"
        exit
    fi
}

#################################################
# Dispatches the proper function from the loaded
# module
#
# @param $1: The function name
# @param ${@:2} All parameters to the callable
#################################################
Ash_execute_callable() {
    # Checking if callable
    if [[ -z "$Ash_module_config_callable_prefix" ]]; then
        Logger__error "Cannot execute any callables, as 'callable_prefix' is not set in this module's ash_config.yaml"
        return
    fi

    # Executing the callable function if it exists
    local function="$Ash_module_config_callable_prefix"__callable_"$1"
    if [[ "$(Ash__is_function "$function")" -eq 1 ]]; then
        $function "${@:2}"
    else
        Logger__error "Callable '$1' is unknown"
    fi
}

#################################################
# Displays some basic help/usage for Ash
#################################################
Ash_help() {
    # TODO
    echo "Ash Help -- TODO"
    exit
}

#################################################
# Imports all of the libraries needed by
# the core to run
#################################################
Ash_import_core() {
    Ash__import "github.com/ash-shell/logger"
    Ash__import "github.com/ash-shell/yaml-parse"
    Ash__import "github.com/ash-shell/obj"
}

#################################################
# The entry point function
#################################################
Ash_start() {
    # Checking if user needs help
    if [[ -z "$1" || "$1" = "--help" ]]; then
        Ash_help
    fi

    # Determining platform
    Ash__active_platform="$(Ash_determine_platform)"

    # Importing the core
    Ash_import_core

    # Updating Logger prefix
    Logger__set_prefix "Ash"

    # Dispatching to module
    Ash_dispatch "$@"
}

Ash_start "$@"
