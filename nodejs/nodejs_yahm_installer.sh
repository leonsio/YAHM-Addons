#!/bin/bash


_nodejs_install()
{
    info "\n$(timestamp) [LXC] [node.js] Starting LXC installation.\n"

    progress "$(timestamp) [LXC] [node.js] Installing dependencies..."
    lxc-attach -n nodejs -- /usr/bin/apt-get update &>> ${LOG_FILE}
    lxc-attach -n nodejs -- /usr/bin/apt-get -y install wget git curl &>> ${LOG_FILE}
    if [ $? -eq 0 ]; then info "OK"; else error "FAILED"; fail_inprogress; fi

    # hack für lxc und avahi, falls bereits eine Instanz läuft
    lxc-attach -n nodejs -- sed -i /etc/adduser.conf -e 's/FIRST_SYSTEM_UID=100/FIRST_SYSTEM_UID=200/g'
    lxc-attach -n nodejs -- sed -i /etc/adduser.conf -e 's/FIRST_SYSTEM_GID=100/FIRST_SYSTEM_GID=200/g'

    progress "$(timestamp) [LXC] [node.js] Setup node.js repository"
    curl -sL https://deb.nodesource.com/setup_9.x | lxc-attach -n nodejs -- bash -  &>> ${LOG_FILE}
    if [ $? -eq 0 ]; then info "OK"; else error "FAILED"; fail_inprogress; fi

    progress "$(timestamp) [LXC] [node.js] Installing node.js"
    lxc-attach -n nodejs -- /usr/bin/apt -y install nodejs &>> ${LOG_FILE}
    if [ $? -eq 0 ]; then info "OK"; else error "FAILED"; fail_inprogress; fi

    progress "$(timestamp) [HOST] [node.js] Creating some useful scripts..."

    # join script
    cat > /usr/sbin/yahm-nodejs <<EOF
#!/bin/bash

if [ $# -eq 0 ]
then
    lxc-attach -n nodejs
else
    lxc-attach -n nodejs -- \$@
fi

EOF

    # Set executable
    chmod +x  /usr/sbin/yahm-nodejs*
    info "OK"

    # Geting some IP informations
    NJ_LXC_IP=$(get_lxc_ip "nodejs")
    LXC_HOST_IP=$(get_ip_to_route ${NJ_LXC_IP})

#    progress "$(timestamp) [LXC] [node.js] Setup remote syslog..."
#    echo "*.*  @@${LXC_HOST_IP}" | lxc-attach -n nodejs -- tee /etc/rsyslog.d/10-yahm.conf &>> ${LOG_FILE}
#    if [ $? -eq 0 ]; then info "OK"; else die "FAILED"; fail_inprogress; fi
#
#    progress "$(timestamp) [LXC] [node.js] Restarting syslog..."
#    lxc-attach -n nodejs -- service rsyslog restart &>> ${LOG_FILE}
#    if [ $? -eq 0 ]; then info "OK"; else die "FAILED"; fail_inprogress; fi

    info "\n$(timestamp) [GLOBAL] [node.js] Successfully installed\n"
    info "$(timestamp) [GLOBAL] [node.js] Run yahm-nodejs to execute command or login"

}

_nodejs_update()
{
   if [ $(lxc-info -n nodejs | grep STOPPED|wc -l) -eq 1 ]
    then
        die "$(timestamp) [node.js] ERROR: node.js container is stopped, please start it first (lxc-start -n nodejs -d)"
    fi

    progress "$(timestamp) [LXC] [node.js] Updating repositories and upgrading installed packages..."
    until lxc-attach -n nodejs -- apt update &>> ${LOG_FILE}; do sleep 1; done
    lxc-attach -n nodejs -- apt --yes upgrade &>> ${LOG_FILE}
    if [ $? -eq 0 ]; then info "OK"; else info "FAILED"; fail_inprogress; fi

    info "$(timestamp) [LXC] [node.js] node.js was upgraded successfully\n"
}

_nodejs_uninstall()
{
    info "Deleting installed node.js container. To cancel this operation type CTRL+C you have 5 seconds..."
    countdown
    info "... too late ;)"

    progress "$(timestamp) [HOST] [node.js] Stopping node.js container..."
    lxc-stop -n nodejs -k
    if [ $? -eq 0 ]; then info "OK"; else info "FAILED"; fail_inprogress; fi

    # cleanup 1
    umount /var/log/nodejs
    rm -rf /var/log/nodejs

    progress "$(timestamp) [HOST] [node.js] Removing node.js container..."
    lxc-destroy -n nodejs
    if [ $? -eq 0 ]; then info "OK"; else info "FAILED"; fail_inprogress; fi

    progress "$(timestamp) [HOST] [node.js] Removing yahm-nodejs script"
    rm -rf /usr/sbin/yahm-nodejs
    info "OK"

    # cleanup 2
    rm -rf /var/lib/lxc/nodejs
}
