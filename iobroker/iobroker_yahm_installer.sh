#!/bin/bash

_iobroker_install()
{

    if [ $(lxc-info -n ${LXCNAME} | grep RUNNING | wc -l) -eq 1 ]
    then
        YAHM_LXC_IP=$(get_lxc_ip ${LXCNAME})
        if [ ${YAHM_LXC_IP} -eq 0 ]
        then
            error "$(timestamp) [GLOBAL] [ioBroker] ERROR: ${LXCNAME} container has no assigned ips, please enter manually"
            YAHM_LXC_IP=$(whiptail --inputbox "Please enter your CCU2 IP" 20 60 "000.000.000.000" 3>&1 1>&2 2>&3)
            # read -p "CCU2 IP: " YAHM_LXC_IP
        fi
    else
        error "$(timestamp) [GLOBAL] [ioBroker] ERROR: ${LXCNAME} container is not running or present, please enter CCU2 IP manually"
        YAHM_LXC_IP=$(whiptail --inputbox "Please enter your CCU2 IP" 20 60 "000.000.000.000" 3>&1 1>&2 2>&3)
        #read -p "CCU2 IP: " YAHM_LXC_IP
    fi

    if [ ${YAHM_LXC_IP} -eq 0 ]
    then
        die "$(timestamp) [ioBroker] FATAL: CCU2 IP can not be empty"
    fi


    info "\n$(timestamp) [GLOBAL] [ioBroker] Host Installation done, beginning with LXC preparation.\n"

    progress "$(timestamp) [LXC] [ioBroker] Installing dependencies..."
    lxc-attach -n iobroker -- /usr/bin/apt -y install wget git curl make gcc g++ &>> ${LOG_FILE}
    if [ $? -eq 0 ]; then info "OK"; else error "FAILED"; fail_inprogress; fi

    # hack für lxc und avahi, falls bereits eine Instanz läuft
    lxc-attach -n iobroker -- sed -i /etc/adduser.conf -e 's/FIRST_SYSTEM_UID=100/FIRST_SYSTEM_UID=400/g'
    lxc-attach -n iobroker -- sed -i /etc/adduser.conf -e 's/FIRST_SYSTEM_GID=100/FIRST_SYSTEM_GID=400/g'

    progress "$(timestamp) [LXC] [ioBroker] Installing node.js repository"
    curl -sL https://deb.nodesource.com/setup_8.x | lxc-attach -n iobroker -- bash -  &>> ${LOG_FILE}
    if [ $? -eq 0 ]; then info "OK"; else error "FAILED"; fail_inprogress; fi

    progress "$(timestamp) [LXC] [ioBroker] Installing node.js"
    lxc-attach -n iobroker -- /usr/bin/apt -y install nodejs &>> ${LOG_FILE}
    if [ $? -eq 0 ]; then info "OK"; else error "FAILED"; fail_inprogress; fi

    progress "$(timestamp) [LXC] [ioBroker] Downgrading npm to 4.x"
    lxc-attach -n iobroker -- npm install -g npm@4 &>> ${LOG_FILE}
    if [ $? -eq 0 ]; then info "OK"; else error "FAILED"; fail_inprogress; fi

    progress "$(timestamp) [LXC] [ioBroker] Installing iobroker. This can take some time..."
    lxc-attach -n iobroker --  npm install -g iobroker  --unsafe-perm &>> ${LOG_FILE}
    if [ $? -eq 0 ]; then info "OK"; else die "FAILED"; fail_inprogress; fi

    progress "$(timestamp) [HOST] [iobroker] Creating some useful scripts..."

    # join script
    cat > /usr/sbin/yahm-iobroker <<EOF
#!/bin/bash

if [ $# -eq 0 ]
then
    lxc-attach -n iobroker
else
    lxc-attach -n iobroker -- \$@
fi

EOF

    # Set executable
    chmod +x  /usr/sbin/yahm-iobroker*
    info "OK"

    # Geting some IP informations
    IB_LXC_IP=$(get_lxc_ip "iobroker")
    LXC_HOST_IP=$(get_ip_to_route ${IB_LXC_IP})

#    progress "$(timestamp) [LXC] [ioBroker] Setup remote syslog..."
#    echo "*.*  @@${LXC_HOST_IP}" | lxc-attach -n iobroker -- tee /etc/rsyslog.d/10-yahm.conf &>> ${LOG_FILE}
#    if [ $? -eq 0 ]; then info "OK"; else die "FAILED"; fail_inprogress; fi

#    progress "$(timestamp) [LXC] [ioBroker] Restarting syslog..."
#    lxc-attach -n iobroker -- service rsyslog restart &>> ${LOG_FILE}
#    if [ $? -eq 0 ]; then info "OK"; else die "FAILED"; fail_inprogress; fi

    progress "$(timestamp) [LXC] [ioBroker] Starting iobroker Service..."
    lxc-attach -n iobroker -- systemctl start iobroker &>> ${LOG_FILE}
    if [ $? -eq 0 ]; then info "OK"; else die "FAILED"; fail_inprogress; fi

    progress "$(timestamp) [LXC] [ioBroker] Installing hm-rpc adapter..."
    lxc-attach -n iobroker -- iobroker add hm-rpc &>> ${LOG_FILE}
    if [ $? -eq 0 ]; then info "OK"; else die "FAILED"; fail_inprogress; fi

    progress "$(timestamp) [LXC] [ioBroker] Setup CCU2 ip in hm-rpc..."
    lxc-attach -n iobroker --  iobroker set hm-rpc.0 --homematicAdress ${YAHM_LXC_IP} &>> ${LOG_FILE}
    if [ $? -eq 0 ]; then info "OK"; else die "FAILED"; fail_inprogress; fi

    progress "$(timestamp) [LXC] [ioBroker] Installing hm-rega adapter..."
    lxc-attach -n iobroker -- iobroker add hm-rega &>> ${LOG_FILE}
    if [ $? -eq 0 ]; then info "OK"; else die "FAILED"; fail_inprogress; fi

    info "\n$(timestamp) [GLOBAL] [ioBroker] Successfully installed\n"
    info "$(timestamp) [GLOBAL] [ioBroker] Go to http://${IB_LXC_IP}:8081 to open the admin UI"
    info "$(timestamp) [GLOBAL] [ioBroker] Run yahm-iobroker to execute command or login"
}

_iobroker_update()
{
    if [ $(lxc-info -n iobroker | grep RUNNING | wc -l) -eq 0 ]
    then
        die "ioBroker container must be running, please start it first: lxc-start -n iobroker -d"
    fi

    progress "$(timestamp) [LXC] [ioBroker] Updating ioBroker..."
    lxc-attach -n iobroker --  npm update -g iobroker &>> ${LOG_FILE}
    if [ $? -eq 0 ]; then info "OK"; else die "FAILED"; fi
}

_iobroker_uninstall()
{
    info "Deleting installed iobroker container. To cancel this operation type CTRL+C you have 5 seconds..."
    countdown
    info "... too late ;)"

    progress "$(timestamp) [HOST] [ioBroker] Stopping ioBroker container..."
    lxc-stop -n iobroker -k
    if [ $? -eq 0 ]; then info "OK"; else info "FAILED"; fail_inprogress; fi

    # cleanup 1
    umount /var/log/iobroker
    rm -rf /var/log/iobroker

    progress "$(timestamp) [HOST] [ioBroker] Removing ioBroker container..."
    lxc-destroy -n iobroker
    if [ $? -eq 0 ]; then info "OK"; else info "FAILED"; fail_inprogress; fi

    progress "$(timestamp) [HOST] [ioBroker] Removing admin scripts"
    rm -rf /usr/sbin/yahm-iobroker
    info "OK"

    # cleanup 2
    rm -rf /var/lib/lxc/iobroker
}
