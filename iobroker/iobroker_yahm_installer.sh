#!/bin/bash

description="ioBroker LXC Container"
addon_required=""
module_required=""

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

    if [ -d /var/lib/lxc/iobroker ]
    then
        die "$(timestamp) [ioBroker] FATAL: ioBroker LXC Instance found, please delete it first /var/lib/lxc/iobroker"
    fi

    mkdir -p /var/log/yahm
    rm -rf /var/log/yahm/iobroker_install.log

    info "\n$(timestamp) [GLOBAL] [ioBroker] Starting the iobroker Host LXC installation.\n"

    progress "$(timestamp) [HOST] [ioBroker] Updating repositories..."
    until apt update &>> /var/log/yahm/iobroker_install.log; do sleep 1; done
    #apt --yes upgrade &>> /var/log/yahm/iobroker_install.log
    if [ $? -eq 0 ]; then info "OK"; else error "FAILED"; fail_inprogress; fi

    progress "$(timestamp) [HOST] [ioBroker] Installing dependencies..."
    /usr/bin/apt -y install rsync &>> /var/log/yahm/iobroker_install.log
    if [ $? -eq 0 ]; then info "OK"; else error "FAILED"; fail_inprogress; fi

    progress "$(timestamp) [HOST] [ioBroker] Creating new LXC container: iobroker. This can take some time..."
    lxc-create -n iobroker -t download --  --dist ubuntu --release xenial --arch=arm64 &>> /var/log/yahm/iobroker_install.log
    if [ $? -eq 0 ]; then info "OK"; else error "FAILED"; fail_inprogress; fi

    progress "$(timestamp) [HOST] [ioBroker] Creating LXC network configuration..."
    ${YAHM_DIR}/bin/yahm-network -n iobroker -f attach_bridge &>> /var/log/yahm/iobroker_install.log
    if [ $? -eq 0 ]; then info "OK"; else error "FAILED"; fail_inprogress; fi

    # attach network configuration
    echo lxc.include=/var/lib/lxc/iobroker/config.network >> /var/lib/lxc/iobroker/config
    # setup autostart
    echo 'lxc.start.auto = 1' >> /var/lib/lxc/iobroker/config

    progress "$(timestamp) [HOST] [ioBroker] Starting iobroker LXC container..."
    lxc-start -n iobroker -d
    if [ $? -eq 0 ]; then info "OK"; else error "FAILED"; fail_inprogress; fi

    # wait to get ethernet connection up
    sleep 5

    info "\n$(timestamp) [GLOBAL] [iobroker] Host Installation done, beginning with LXC preparation.\n"

    progress "$(timestamp) [LXC] [ioBroker] Installing dependencies..."
    lxc-attach -n iobroker -- /usr/bin/apt -y install wget git curl maje gcc g++ &>> /var/log/yahm/iobroker_install.log
    if [ $? -eq 0 ]; then info "OK"; else error "FAILED"; fail_inprogress; fi

    # hack für lxc und avahi, falls bereits eine Instanz läuft
    lxc-attach -n iobroker -- sed -i /etc/adduser.conf -e 's/FIRST_SYSTEM_UID=100/FIRST_SYSTEM_UID=400/g'
    lxc-attach -n iobroker -- sed -i /etc/adduser.conf -e 's/FIRST_SYSTEM_GID=100/FIRST_SYSTEM_GID=400/g'

    progress "$(timestamp) [LXC] [ioBroker] Installing node.js repository"
    curl -sL https://deb.nodesource.com/setup_8.x | lxc-attach -n iobroker -- bash -  &>> /var/lib/lxc/iobroker/config
    if [ $? -eq 0 ]; then info "OK"; else error "FAILED"; fail_inprogress; fi

    progress "$(timestamp) [LXC] [ioBroker] Installing node.js"
    lxc-attach -n iobroker -- /usr/bin/apt -y install nodejs &>> /var/log/yahm/iobroker_install.log
    if [ $? -eq 0 ]; then info "OK"; else error "FAILED"; fail_inprogress; fi

    progress "$(timestamp) [LXC] [ioBroker] Downgrading npm to 4.x"
    lxc-attach -n iobroker -- npm install -g npm@4
    if [ $? -eq 0 ]; then info "OK"; else error "FAILED"; fail_inprogress; fi

    progress "Installing iobroker. This can take some time..."
    lxc-attach -n iobroker --  npm install -g iobroker  --unsafe-perm &>> /var/log/yahm/iobroker_install.log
    if [ $? -eq 0 ]; then info "OK"; else die "FAILED"; fi

    progress "$(timestamp) [HOST] [iobroker] Creating some useful scripts..."

    # join script
    cat > /usr/sbin/yahm-iobroker <<EOF
#!/bin/bash

if [ $# -eq 0 ]
then
    lxc-attach -n iobroker
else

fi
    lxc-attach -n iobroker -- \$@
EOF

    # Set executable
    chmod +x  /usr/sbin/yahm-iobroker*
    info "OK"

    progress "Starting iobroker Service..."
    lxc-attach -n iobroker -- systemctl start iobroker &>> /var/log/yahm/iobroker_install.log
    if [ $? -eq 0 ]; then info "OK"; else die "FAILED"; fi

    # Geting some IP informations
    IB_LXC_IP=$(lxc-info -i -n iobroker | awk '{print $2}')

    info "\n$(timestamp) [GLOBAL] [ioBroker] Successfully installed\n"
    info "$(timestamp) [GLOBAL] [ioBroker] Go to http://${IB_LXC_IP}:8081 to open the admin UI"
    info "$(timestamp) [GLOBAL] [ioBroker] Run yahm-iobroker to execute command or login"
}

_addon_update()
{
    if [ $(lxc-info -n iobroker | grep RUNNING | wc -l) -eq 0 ]
    then
        die "ioBroker container must be running, please start it first: lxc-start -n iobroker -d"
    fi

    progress "Updating ioBroker..."
    lxc-attach -n iobroker --  npm update -g iobroker &>> /var/log/yahm/iobroker_update.log
    if [ $? -eq 0 ]; then info "OK"; else die "FAILED"; fi
}

_addon_uninstall()
{
    info "Deleting installed iobroker container. To cancel this operation type CTRL+C you have 5 seconds..."
    countdown
    info "... too late ;)"

    progress "$(timestamp) [HOST] [ioBroker] Stopping ioBroker container..."
    lxc-stop -n iobroker -k
    if [ $? -eq 0 ]; then info "OK"; else info "FAILED"; fail_inprogress; fi

    progress "$(timestamp) [HOST] [ioBroker] Removing ioBroker container..."
    lxc-destroy -n iobroker
    if [ $? -eq 0 ]; then info "OK"; else info "FAILED"; fail_inprogress; fi

    progress "$(timestamp) [HOST] [ioBroker] Removing admin scripts"
    rm -rf /usr/sbin/yahm-iobroker
    info "OK"

    # cleanup
    rm -rf /var/lib/lxc/iobroker
}
