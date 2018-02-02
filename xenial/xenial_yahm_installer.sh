#!/bin/bash

_xenial_install()
{
    local ARCH=`dpkg --print-architecture`

    if [ -d /var/lib/lxc/${ADDON} ]
    then
        die "$(timestamp) [GLOBAL] FATAL: ${ADDON} LXC Instance found, please delete it first /var/lib/lxc/${ADDON}"
    fi

    mkdir -p /var/log/yahm
    rm -rf ${LOG_FILE}

    info "\n$(timestamp) [GLOBAL] Starting the ${ADDON} LXC instance installation.\n"

    progress "$(timestamp) [HOST] [${ADDON}] Creating new LXC container: nodejs. This can take some time..."
    lxc-create -n ${ADDON} -t download --  --dist ubuntu --release xenial --arch=${ARCH} &>> ${LOG_FILE}
    if [ $? -eq 0 ]; then info "OK"; else error "FAILED"; fail_inprogress; fi

    progress "$(timestamp) [HOST] [${ADDON}] Creating LXC network configuration..."
    ${YAHM_DIR}/bin/yahm-network -n ${ADDON} -f attach_bridge &>> ${LOG_FILE}
    if [ $? -eq 0 ]; then info "OK"; else error "FAILED"; fail_inprogress; fi

    # attach network configuration
    echo lxc.include=/var/lib/lxc/${ADDON}/config.network >> /var/lib/lxc/${ADDON}/config
    # setup autostart
    echo 'lxc.start.auto = 1' >> /var/lib/lxc/${ADDON}/config

    progress "$(timestamp) [HOST] [${ADDON}] Starting ${ADDON} LXC container..."
    lxc-start -n ${ADDON} -d
    if [ $? -eq 0 ]; then info "OK"; else error "FAILED"; fail_inprogress; fi

    # wait to get ethernet connection up
    sleep 5

    progress "$(timestamp) [HOST] [${ADDON}] Linking syslog to /var/log/${ADDON}..."
    mkdir -p /var/log/${ADDON}
    mount --bind /var/lib/lxc/${ADDON}/rootfs/var/log /var/log/${ADDON}/
    if [ $? -eq 0 ]; then info "OK"; else die "FAILED"; fail_inprogress; fi

    info "\n$(timestamp) [GLOBAL] [${ADDON}] Host Installation done.\n"

}