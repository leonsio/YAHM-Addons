#!/bin/bash

description="NodeJS LXC Container"
addon_required=""
module_required=""

timestamp() { date +"%F_%T_%Z"; }

fail_inprogress()
{
  cat /var/log/yahm/nodejs_install.log
  die "\n$(timestamp) [HOST] [nodejs] Initial setup exiting with an error!\n\n"
}

_addon_install()
{

    if [ `dpkg --print-architecture` = "arm64" ]
    then
        ARCH_ADD="--arch arm64"
        ARCH="arm64"
    else
        ARCH_ADD=""
        ARCH="armhf"
    fi

    if [ -d /var/lib/lxc/nodejs ]
    then
        die "$(timestamp) [node.js] FATAL: node.js LXC Instance found, please delete it first /var/lib/lxc/nodejs"
    fi

    mkdir -p /var/log/yahm
    rm -rf /var/log/yahm/nodejs_install.log

    info "\n$(timestamp) [GLOBAL] [node.js] Starting the nodejs Host LXC installation.\n"

    progress "$(timestamp) [HOST] [node.js] Updating repositories..."
    until apt update &>> /var/log/yahm/nodejs_install.log; do sleep 1; done
    #apt --yes upgrade &>> /var/log/yahm/nodejs_install.log
    if [ $? -eq 0 ]; then info "OK"; else error "FAILED"; fail_inprogress; fi

    progress "$(timestamp) [HOST] [node.js] Installing dependencies..."
    /usr/bin/apt -y install rsync &>> /var/log/yahm/nodejs_install.log
    if [ $? -eq 0 ]; then info "OK"; else error "FAILED"; fail_inprogress; fi

    progress "$(timestamp) [HOST] [node.js] Creating new LXC container: nodejs. This can take some time..."
    lxc-create -n nodejs -t download --  --dist ubuntu --release xenial --arch=arm64 &>> /var/log/yahm/nodejs_install.log
    if [ $? -eq 0 ]; then info "OK"; else error "FAILED"; fail_inprogress; fi

    progress "$(timestamp) [HOST] [node.js] Creating LXC network configuration..."
    ${YAHM_DIR}/bin/yahm-network -n nodejs -f attach_bridge &>> /var/log/yahm/nodejs_install.log
    if [ $? -eq 0 ]; then info "OK"; else error "FAILED"; fail_inprogress; fi

    # attach network configuration
    echo lxc.include=/var/lib/lxc/nodejs/config.network >> /var/lib/lxc/nodejs/config
    # setup autostart
    echo 'lxc.start.auto = 1' >> /var/lib/lxc/nodejs/config

    progress "$(timestamp) [HOST] [node.js] Starting nodejs LXC container..."
    lxc-start -n nodejs -d
    if [ $? -eq 0 ]; then info "OK"; else error "FAILED"; fail_inprogress; fi

    # wait to get ethernet connection up
    sleep 5

    info "\n$(timestamp) [GLOBAL] [nodejs] Host Installation done, beginning with LXC preparation.\n"

    progress "$(timestamp) [LXC] [node.js] Installing dependencies..."
    lxc-attach -n nodejs -- /usr/bin/apt -y install wget git curl &>> /var/log/yahm/nodejs_install.log
    if [ $? -eq 0 ]; then info "OK"; else error "FAILED"; fail_inprogress; fi

    # hack für lxc und avahi, falls bereits eine Instanz läuft
    lxc-attach -n nodejs -- sed -i /etc/adduser.conf -e 's/FIRST_SYSTEM_UID=100/FIRST_SYSTEM_UID=200/g'
    lxc-attach -n nodejs -- sed -i /etc/adduser.conf -e 's/FIRST_SYSTEM_GID=100/FIRST_SYSTEM_GID=200/g'

    progress "$(timestamp) [LXC] [node.js] Installing node.js repository"
    curl -sL https://deb.nodesource.com/setup_9.x | lxc-attach -n nodejs -- bash -  &>> /var/lib/lxc/nodejs/config
    if [ $? -eq 0 ]; then info "OK"; else error "FAILED"; fail_inprogress; fi

    progress "$(timestamp) [LXC] [node.js] Installing node.js"
    lxc-attach -n nodejs -- /usr/bin/apt -y install nodejs &>> /var/log/yahm/nodejs_install.log
    if [ $? -eq 0 ]; then info "OK"; else error "FAILED"; fail_inprogress; fi

    progress "$(timestamp) [HOST] [nodejs] Creating some useful scripts..."

    # join script
    cat > /usr/sbin/yahm-nodejs <<EOF
#!/bin/bash

if [ $# -eq 0 ]
then
    lxc-attach -n nodejs
else

fi
    lxc-attach -n nodejs -- \$@
EOF

    # Set executable
    chmod +x  /usr/sbin/yahm-nodejs*
    info "OK"
    
    info "\n$(timestamp) [GLOBAL] [node.js] Successfully installed\n"
    info "$(timestamp) [GLOBAL] [node.js] Run yahm-nodejs to execute command or login"

}

_addon_update()
{
   if [ $(lxc-info -n nodejs | grep STOPPED|wc -l) -eq 1 ]
    then
        die "$(timestamp) [node.js] ERROR: node.js container is stopped, please start it first (lxc-start -n nodejs -d)"
    fi

    progress "$(timestamp) [LXC] [node.js] Updating repositories and upgrading installed packages..."
    until lxc-attach -n nodejs -- apt update &>> /var/log/yahm/nodejs_install.log; do sleep 1; done
    lxc-attach -n nodejs -- apt --yes upgrade &>> /var/log/yahm/nodejs_install.log
    if [ $? -eq 0 ]; then info "OK"; else info "FAILED"; fail_inprogress; fi

    info "$(timestamp) [LXC] [node.js] node.js was upgraded successfully\n"
}

_addon_uninstall()
{
    info "Deleting installed node.js container. To cancel this operation type CTRL+C you have 5 seconds..."
    countdown
    info "... too late ;)"

    progress "$(timestamp) [HOST] [node.js] Stopping node.js container..."
    lxc-stop -n nodejs -k
    if [ $? -eq 0 ]; then info "OK"; else info "FAILED"; fail_inprogress; fi

    progress "$(timestamp) [HOST] [node.js] Removing node.js container..."
    lxc-destroy -n nodejs
    if [ $? -eq 0 ]; then info "OK"; else info "FAILED"; fail_inprogress; fi

    progress "$(timestamp) [HOST] [node.js] Removing yahm-nodejs script"
    rm -rf /usr/sbin/yahm-nodejs
    info "OK"

    #cleanup
    rm -rf /var/lib/lxc/nodejs
}
