#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-or-later

set -e

timeout=$1
user=$2
command=( "${@:3}" )

__ssh() {
    ssh \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -l "$user" \
        localhost \
        "$@"
}

if [[ ! -e /crun-vm/ssh-successful ]]; then

    # retry ssh for some time, ignoring some common errors

    ignore_errors=(
        "Connection closed by remote host"
        "Connection refused"
        "Connection reset by peer"
        "Pseudo-terminal will not be allocated because stdin is not a terminal"
        "System is booting up"
    )

    ignore_pattern=$( printf "|%s" "${ignore_errors[@]}" )
    ignore_pattern=${ignore_pattern:1}

    start_time=$( date +%s )
    end_time=$(( start_time + timeout ))

    while true; do

        if (( timeout > 0 && $( date +%s ) >= end_time )); then
            >&2 echo "exec timed out while attempting ssh"
            exit 255
        fi

        set +e
        output=$( __ssh -o BatchMode=yes </dev/null 2>&1 )
        exit_code=$?
        set -e

        sleep 1

        if (( exit_code != 255 )) || ! grep -iqE "$ignore_pattern" <<< "$output"; then
            break
        fi

    done

    if (( exit_code != 0 )) && ! grep -iqE "Permission denied" <<< "$output"; then
        >&2 printf '%s\n' "$output"
        exit "$exit_code"
    fi

    # avoid these steps next time

    touch /crun-vm/ssh-successful

fi

__ssh -o LogLevel=ERROR -- "${command[@]}"
