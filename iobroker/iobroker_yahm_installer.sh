#!/bin/bash

description="ioBroker LXC Container"
addon_required=""
module_required=""

addon_install()
{

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
