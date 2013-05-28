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

check_list="wget buffer"
check_installed "$check_list"

function devices_prepare
{
    replay_count=0
    replay_host_list="$(eval echo "$replay_host_list")"
    replay_device_list="$(eval echo "$replay_device_list")"
    if [ -z "$replay_host_list" ]; then
	echo "variable replay_host_list is undefined"
	exit -1
    fi
    if echo $replay_host_list | grep -q ":"; then
	for i in $replay_host_list; do
	    host=$(echo $i | cut -d: -f1)
	    device=$(echo $i | cut -d: -f2-)
	    replay_host[$replay_count]=$host
	    replay_device[$replay_count]=$device
	    if (( !devices_prepared )); then
		replay_host_orig[$replay_count]=$host
		replay_device_orig[$replay_count]=$device
	    fi
	    (( replay_count++ ))
	done
    else
	if [ -z "$replay_device_list" ]; then
	    echo "variable replay_device_list is undefined"
	    exit -1
	fi
	for host in $replay_host_list; do
	    tmp_list="$(remote "$host" "ls $replay_device_list | xargs -n 1 test -b && ls $replay_device_list")" ||\
		{ echo "non-existing devices on $host: $replay_device_list"; exit -1; }
	    replay_device_list="$tmp_list"
	    for device in $replay_device_list; do
		replay_host[$replay_count]=$host
		replay_device[$replay_count]=$device
		if (( !devices_prepared )); then
		    replay_host_orig[$replay_count]=$host
		    replay_device_orig[$replay_count]=$device
		fi
		(( replay_count++ ))
	    done
	done
    fi

    if (( replay_count <= 0 )); then
	echo "no devices found."
	exit -1
    fi

    if (( !devices_prepared )); then
	replay_count_orig=$replay_count
    fi
    # remember old value before limiting it (some modules may need it)
    replay_count_really=$replay_count
    if (( replay_max_parallelism > 0 && replay_count > replay_max_parallelism )); then
	echo "reducing replay_count from $replay_count to $replay_max_parallelism due to replay_max_parallelism."
	replay_count=$replay_max_parallelism
    fi

    replay_max=$(( replay_count - 1 ))
    replay_hosts_unique="$(for i in $(eval echo {0..$replay_max}); do echo "${replay_host[$i]}"; done | sort -u)"
    if [ -z "$target_hosts_unique" ]; then
	target_hosts_unique="$replay_hosts_unique" # may by later extended by iSCSI&co
    fi
    all_hosts_unique="$replay_hosts_unique" # may by later extended by iSCSI&co
    echo "${new_txt} of hosts / devices / input files / output files:"
    j=0
    for i in $(eval echo {0..$replay_max}); do
	[ -z "${input_file[$j]}" ] && j=0
	input_file[$i]="${input_file[$j]}"
	infix=""
	(( output_add_path   )) && infix="$infix$sub_prefix"
	(( output_add_host   )) && infix="$infix.${replay_host[$i]}"
	(( output_add_device )) && infix="$infix.$(echo ${replay_device[$i]} | sed 's/[\/]\?dev[\/]\?//'| sed 's/\//./g' | sed 's/\.\././g')"
	(( output_add_input  )) && infix="$infix.$(basename ${input_file[$i]} | sed 's/\.\(load\|gz\)//g')"
	output_file[$i]="${output_label:-TEST}$infix.replay.gz"
	echo " $i: ${replay_host[$i]} ${replay_device[$i]} $(basename ${input_file[$i]}) ${output_file[$i]}"
	(( j++ ))
    done
    (( devices_prepared++ ))
    return 0
}

function main_prepare
{
    if echo "$input_file_list" | grep -q '^\(http\|ftp\)s\?:'; then
	echo "Downloading $input_file_list"
	(
	    cd "$download_dir" || exit -1
	    wget --recursive --level=1 --accept "$(basename "$input_file_list")" --continue --no-verbose "$(dirname "$input_file_list")" || exit -1
	) || exit $?
	input_file_list="$download_dir/$(echo "$input_file_list" | cut -d: -f2- )"
    fi
    input_file_list="$(eval echo "$input_file_list")"
    if [ -z "$input_file_list" ]; then
	echo "variable input_file_list is undefined"
	exit -1
    fi
    input_file_max=-1
    j=0
    for i in $input_file_list; do
	input_file[$j]=$i
	input_file_max=$j
	(( j++ ))
    done
    input_file_count=$j

    new_txt="List"
    devices_prepare
    new_txt="New / regenerated list"

    input_pipe_list="gunzip -f < \"\${input_file[\$i]}\" | grep '^ *[0-9.]* *;'"
    output_pipe_list="cat"
    echo ""
}

function main_setup
{
    echo $FUNCNAME
    echo "Determine target architecture(s) and copy executable(s)..."
    for host in $replay_hosts_unique; do
	if remote "$host" [ -x blkreplay.exe ]; then
	    echo "Host $host already has blkreplay.exe"
	    continue
	fi
	arch="$(remote "$host" "uname -m || arch")" ||\
	    { echo "cannot determine architecture of $host"; return 1; }
	exe="$bin_dir/arch.$arch"
	if ! [ -x "$exe/blkreplay.exe" ]; then # try generic architectures
	    case "$arch" in
		*_64)
                arch="m64"
		;;
		i?86)
                arch="m32"
		;;
	    esac
	    exe="$bin_dir/arch.$arch"
	fi
	if ! [ -x "$exe/blkreplay.exe" ]; then
	    echo "Sorry, no blkreplay executable for architecture $arch available."
	    echo "Please re-make blkreplay with appropriate architecture (e.g. install cross compiler / cross libraries)."
	    exe="$bin_dir"
	    if [ -x "$exe/blkreplay.exe" ]; then
		echo "Trying to resort to generic $exe, but this is likely to fail."
	    else
		return 1
	    fi
	fi
	echo "Host $host has architecture $arch"
	scp -p "$exe"/*.exe root@$host: || return 1
    done
}

function main_run
{
    echo $FUNCNAME
    buffer_cmd="(buffer -m 16m || cat)"
    for i in $(eval echo {0..$replay_max}); do
	options=""
	# list of parameterless options
	optlist="dry_run fake_io o_direct no_o_direct o_sync no_o_sync no_dispatcher"
	for opt in $optlist; do
	    if eval "(( $opt ))"; then
		options="$options --$(echo $opt | sed 's/_/-/g')"
	    fi
	done
	# list of options with parameters
	optlist="replay_start replay_duration replay_out start_grace strong threads speedup fan_out bottleneck simulate_io ahead_limit verbose fill_random"
	for opt in $optlist; do
	    if eval "[ -n \"\$$opt\" ]"; then
		options="$options --$(echo $opt | sed 's/_/-/g')=$(eval echo \$${opt})"
	    fi
	done
	case "$cmode" in
	    with-conflicts | with-drop | with-partial | with-ordering)
	    options="$options --$cmode"
	    ;;
	    *)
	    echo "Warning: no cmode is set. Falling back to default."
	    ;;
	esac
	case "$vmode" in
	    no-overhead | with-verify | with-final-verify | with-paranoia)
	    options="$options --$vmode"
	    ;;
	    *)
	    ;;
	esac
	blkreplay="./blkreplay.exe $options ${replay_device[$i]} "
	#echo "$blkreplay"
	cmd="$buffer_cmd | $blkreplay | $buffer_cmd"
	uncompress=""
	if (( enable_compress_ssh )); then
	    cmd="$cmd | gzip -$enable_compress_ssh | $buffer_cmd"
	    uncompress="gunzip | "
	fi
	echo "Starting blkreplay on ${replay_host[$i]} options '$options' device ${replay_device[$i]}"
	#echo "$cmd"
	eval "$input_pipe_list" |\
	    remote "${replay_host[$i]}" "$cmd" |\
	    eval "$uncompress$output_pipe_list" |\
	    gzip -8 >\
	    "${output_file[$i]}" &
	if [ -n "$replay_start" ] && [ -n "$replay_delta" ]; then
	    (( replay_start += replay_delta ))
	fi
    done
    echo "$(date) Waiting for termination........"
    wait
    echo "$(date) Done."
}

function main_cleanup
{
    echo $FUNCNAME
}

function main_finish
{
    echo $FUNCNAME
    if (( !omit_tmp_cleanup )); then
	echo "Cleaning all remote /tmp/ directories..."
	cmd="rm -rf /tmp/blkreplay.* || rm -rf \$TMPDIR/blkreplay.* || exit 0"
	remote_all_noreturn "$all_hosts_unique" "$cmd"
    fi
}

# Notice: this is the _only_ place where these lists are to be assigned.
# In modules, the lists must be _extended_ only (prepend / append)

prepare_list="main_prepare"
setup_list="main_setup"
run_list="main_run"
cleanup_list="main_cleanup"
finish_list="main_finish"
input_pipe_list="echo 'you did not implement any filters'"
output_pipe_list="echo 'you did not implement any filters'"

function main
{
    ok=1
    for script in $prepare_list; do
	if (( ok )); then
	    (( verbose_script )) && echo "calling $script"
	    $script || ok=0
	fi
    done
    for script in $setup_list; do
	if (( ok )); then
	    (( verbose_script )) && echo "calling $script"
	    $script || ok=0
	fi
    done
    for script in $run_list; do
	if (( ok )); then
	    (( verbose_script )) && echo "calling $script"
	    $script || ok=0
	fi
    done
    for script in $cleanup_list; do
	(( verbose_script )) && echo "calling $script"
	$script
    done
    for script in $finish_list; do
	(( verbose_script )) && echo "calling $script"
	$script
    done
    return $(( !ok ))
}
