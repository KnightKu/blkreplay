#!/usr/bin/env bash
# Copyright 2010-2012 Thomas Schoebel-Theuer /  1&1 Internet AG
#
# Email: tst@1und1.de
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.

#####################################################################

# New modularized version May 2012

# Make many measurements in subtrees of current working directory.
# Use directory names as basis for configuration variants

script_dir="$(cd "$(dirname "$(which "$0")")"; pwd)"
source "$script_dir/modules/lib.sh" || exit $?

to_produce="${to_produce:-replay.gz}"
to_check="${to_check:-}"
to_start="${to_start:-main}"

dry_run_script=0
verbose_script=0

# check some preconditions

check_list="grep sed gawk head tail cut nice date gzip gunzip zcat buffer"
check_installed "$check_list"

# include modules
prepare_list=""
setup_list=""
run_list=""
cleanup_list=""
finish_list=""

function source_module
{
    module="$1"
    modname="$(basename $module | sed 's/^[0-9]*_\([^.]*\)\..*/\1/')"
    if source_config default-$modname; then
	echo "Sourcing module $modname"
	source $module || exit $?
    elif [ "$modname" = "main" ]; then
	echo "Cannot use main module. Please provide some config file 'default-$modname.conf' in $(pwd) or in some parent directory."
	exit -1
    fi
}

shopt -s nullglob
for module in $module_dir/[0-9]*.sh; do
    source_module "$module"
done

work_dir="."

# parse options.
while [ $# -ge 1 ]; do
    key="$(echo "$1" | cut -d= -f1)"
    val="$(echo "$1" | cut -d= -f2-)"
    case "$key" in
	--work_dir)
        work_dir="$val"
	shift
        ;;
	--test | --dry-run)
        dry_run_script="$val"
	shift
        ;;
	--override)
	shift
	echo "=> Overriding $1"
	eval $1
	shift
        ;;
	*)
	break
        ;;
    esac
done

ignore_cmd="grep -v '[/.]old' | grep -v 'ignore'"
sort_cmd="while read i; do if [ -e \"\$i\"/prio-[0-9]* ]; then echo \"\$(cd \$i; ls prio-[0-9]*):\$i\"; else echo \"z:\$i\"; fi; done | sort | sed 's/^[^:]*://'"

# find directories
resume=1
while (( resume )); do
    echo "Scanning directory structure starting from $(pwd)"
    resume=0
    for test_dir in $(find $work_dir -type d | eval "$ignore_cmd" | eval "$sort_cmd"); do
	(( dry_run_script )) || rm -f $test_dir/dry-run.$to_produce
	if [ -e "$test_dir/skip" ]; then
	    echo "Skipping directory $test_dir"
	    continue
	fi
	if [ $(find $test_dir -type d | eval "$ignore_cmd" | wc -l) -gt 1 ]; then
	    echo "Ignoring inner directory $test_dir"
	    continue
	fi
	shopt -u nullglob
	if ls $test_dir/*.$to_produce > /dev/null 2>&1; then
	    echo "Already finished $test_dir"
	    continue
	fi
	if [ -n "$to_check" ] && ! ls $test_dir/*.$to_check > /dev/null 2>&1; then
	    echo "No *.$to_check files exist in $test_dir"
	    continue
	fi
	echo ""
	echo "==============================================================="
	echo "======== $test_dir"
	if [ -e "$test_dir/stop" ] || [ -e "./stop" ]; then
	    echo "would start $test_dir"
	    echo "echo stopping due to stop file."
	    resume=0
	    break
	fi
	(
	    cd $test_dir
	    # source additional user modules (if available)
	    source_config "user_modules" || echo "(ignored)"
	    shopt -s nullglob
	    for module in $user_module_dir/[0-9]*.sh; do
		source_module "$module"
	    done

	    # source all individual config files (for overrides)
	    shopt -s nullglob
	    for i in $(echo $test_dir | sed 's/\// /g'); do
		[ "$i" = "." ] && continue
		if ! source_config "$i"; then
		    echo "Cannot source config file '$i.conf' -- please provide one."
		    exit -1
		fi
	    done
	    shopt -u nullglob

	    export sub_prefix=$(echo $test_dir | sed 's/\//./g' | sed 's/\.\././g')
	    if (( dry_run_script )); then
		echo "==> Dry Run ..."
		touch dry-run.$to_produce
	    else
		echo "==> $(date) Starting $sub_prefix"
		eval "$to_start" || { echo "Replay failure $?"; exit -1; }
	    fi
	    echo "==> $(date) Finished."
	) || { echo "Failure $?"; exit -1; }
	echo "==============================================================="
	echo ""
	(( resume++ ))
	break
    done
done

if (( dry_run_script )); then
    echo "removing dry-run.$to_produce everywhere..."
    rm -f $(find $work_dir -name "dry-run.$to_produce")
fi

echo "======== Finished pwd=$(pwd)"
exit 0