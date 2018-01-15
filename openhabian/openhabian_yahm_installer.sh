#!/bin/bash

description="OpenHABian LXC Container"
addon_required=""
module_required=""

addon_install()
{
    wget -nv -O- https://raw.githubusercontent.com/leonsio/openhabian/master/build-yahm-lxc.sh  | sudo -E  bash

}

addon_update()
{

}

addon_uninstall()
{

    info "Deleting installed OpenHABian container. To cancel this operation type CTRL+C you have 5 seconds..."
    countdown
    info "... too late ;)"
}
