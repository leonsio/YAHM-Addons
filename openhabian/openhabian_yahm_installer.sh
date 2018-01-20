#!/bin/bash

description="OpenHABian LXC Container"
addon_required=""
module_required=""

timestamp() { date +"%F_%T_%Z"; }

fail_inprogress()
{
  cat /var/log/yahm/openhabian_install.log
  die "$(timestamp) [HOST] [openHABian] Initial setup exiting with an error!\n\n"
}


_addon_install()
{
    wget -nv -O- https://raw.githubusercontent.com/leonsio/openhabian/master/build-yahm-lxc.sh  | sudo -E  bash
}

_addon_update()
{

    if [ $(lxc-info -n openhabian | grep STOPPED|wc -l) -eq 1 ]
    then
        die "$(timestamp) [openHABian] ERROR: openHABian container is stopped, please start it first (lxc-start -n openhabian -d)"
    fi

    progress "$(timestamp) [LXC] [openHABian] Updating repositories and upgrading installed packages..."
    until lxc-attach -n openhabian -- apt update &>> /var/log/yahm/openhabian_install.log; do sleep 1; done
    lxc-attach -n openhabian -- apt --yes upgrade &>> /var/log/yahm/openhabian_install.log
    if [ $? -eq 0 ]; then echo "OK"; else echo "FAILED"; fail_inprogress; fi

    info  "$(timestamp) [LXC] [openHABian] openHABian was upgraded successfully"
}

_addon_uninstall()
{

    info "Deleting installed OpenHABian container. To cancel this operation type CTRL+C you have 5 seconds..."
    countdown
    info "... too late ;)"

    progress "Stopping openHABian container"
    lxc-stop -n openhabian -k

    progress "Removing openHABian container"
    rm -rf /var/lib/lxc/openhabian
}
