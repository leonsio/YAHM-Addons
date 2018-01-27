#!/bin/bash

description="OpenHABian LXC Container"
addon_required=""
module_required=""

fail_inprogress()
{
  cat /var/log/yahm/openhabian_install.log
  die "\n$(timestamp) [HOST] [openHABian] Initial setup exiting with an error!\n\n"
}

_addon_install()
{

    local ARCH=`dpkg --print-architecture`

    if [ $(lxc-info -n ${LXCNAME} | grep RUNNING | wc -l) -eq 1 ]
    then
        YAHM_LXC_IP=$(get_lxc_ip ${LXCNAME})
        if [ ${#YAHM_LXC_IP} -eq 0 ]
        then
            error "$(timestamp) [GLOBAL] [openHABian] ERROR: ${LXCNAME} container has no assigned ips, please enter manually"
            YAHM_LXC_IP=$(whiptail --inputbox "Please enter your CCU2 IP" 20 60 "000.000.000.000" 3>&1 1>&2 2>&3)
            # read -p "CCU2 IP: " YAHM_LXC_IP
        fi
    else
        error "$(timestamp) [GLOBAL] [openHABian] ERROR: ${LXCNAME} container is not running or present, please enter CCU2 IP manually"
        YAHM_LXC_IP=$(whiptail --inputbox "Please enter your CCU2 IP" 20 60 "000.000.000.000" 3>&1 1>&2 2>&3)
        #read -p "CCU2 IP: " YAHM_LXC_IP
    fi

    if [ ${#YAHM_LXC_IP} -eq 0 ]
    then
        die "$(timestamp) [openHABian] FATAL: CCU2 IP can not be empty"
    fi

    if [ -d /var/lib/lxc/openhabian ]
    then
        die "$(timestamp) [openHABian] FATAL: Openhab LXC Instance found, please delete it first /var/lib/lxc/openhabian"
    fi

    mkdir -p /var/log/yahm
    rm -rf /var/log/yahm/openhabian_install.log

    info "\n$(timestamp) [GLOBAL] [openHABian] Starting the openHABian Host LXC installation."
    info "\n$(timestamp) [GLOBAL] [openHABian] For live installation log see: tail -f /var/log/yahm/openhabian_install.log\n"

    progress "$(timestamp) [HOST] [openHABian] Updating repositories..."
    until apt update &>> /var/log/yahm/openhabian_install.log; do sleep 1; done
    #apt --yes upgrade &>> /var/log/yahm/openhabian_install.log
    if [ $? -eq 0 ]; then info "OK"; else error "FAILED"; fail_inprogress; fi

    progress "$(timestamp) [HOST] [openHABian] Creating new LXC container: openhabian. This can take some time..."
    lxc-create -n openhabian -t download --  --dist debian --release stretch --arch=${ARCH} &>> /var/log/yahm/nodejs_install.log
    if [ $? -eq 0 ]; then info "OK"; else error "FAILED"; fail_inprogress; fi

    progress "$(timestamp) [HOST] [openHABian] Creating LXC network configuration..."
    ${YAHM_DIR}/bin/yahm-network -n openhabian -f attach_bridge &>> /var/log/yahm/openhabian_install.log
    if [ $? -eq 0 ]; then info "OK"; else error "FAILED"; fail_inprogress; fi

    # attach network configuration
    echo lxc.include=/var/lib/lxc/openhabian/config.network >> /var/lib/lxc/openhabian/config
    # setup autostart
    echo 'lxc.start.auto = 1' >> /var/lib/lxc/openhabian/config

    progress "$(timestamp) [HOST] [openHABian] Starting openhabian LXC container..."
    lxc-start -n openhabian -d
    if [ $? -eq 0 ]; then info "OK"; else error "FAILED"; fail_inprogress; fi

    progress "$(timestamp) [HOST] [openHABian] Linking syslog to /var/log/openhabian..."
    mkdir -p /var/log/openhabian
    mount --bind /var/lib/lxc/openhabian/rootfs/var/log /var/log/openhabian/
    if [ $? -eq 0 ]; then info "OK"; else die "FAILED"; fail_inprogress; fi

    info "\n$(timestamp) [GLOBAL] [openHABian] Host Installation done, beginning with LXC preparation.\n"

    # hack für lxc und avahi, falls bereits eine Instanz läuft
    lxc-attach -n openhabian -- sed -i /etc/adduser.conf -e 's/FIRST_SYSTEM_UID=100/FIRST_SYSTEM_UID=300/g'
    lxc-attach -n openhabian -- sed -i /etc/adduser.conf -e 's/FIRST_SYSTEM_GID=100/FIRST_SYSTEM_GID=300/g'

    if [ "$BOARD_TYPE" = "Raspberry Pi" ]
    then
        echo "$(timestamp) [INFO] [openHABian] Raspberry Pi Hardware found, setup addition repositories."

        progress "$(timestamp) [LXC] [openHABian] Installing repository key..."
        wget -qO - http://archive.raspberrypi.org/debian/raspberrypi.gpg.key  | lxc-attach -n openhabian -- apt-key add - &>> /var/log/yahm/openhabian_install.log
        if [ $? -eq 0 ]; then info "OK"; else error "FAILED"; fail_inprogress; fi

        progress "$(timestamp) [LXC] [openHABian] Installing repository files..."
        echo 'deb http://archive.raspberrypi.org/debian/ stretch main ui' | lxc-attach -n openhabian  -- tee /etc/apt/sources.list.d/rpi.list &>> /var/log/yahm/openhabian_install.log
        if [ $? -eq 0 ]; then info "OK"; else error "FAILED"; fail_inprogress; fi
    fi

    progress "$(timestamp) [LXC] [openHABian] Creating gpio user..."
    lxc-attach -n openhabian -- useradd gpio &>> /var/log/yahm/openhabian_install.log
    if [ $? -eq 0 ]; then info "OK"; else error "FAILED"; fail_inprogress; fi

    progress "$(timestamp) [LXC] [openHABian] Creating openhabian user..."
    lxc-attach -n openhabian -- useradd -m openhabian &>> /var/log/yahm/openhabian_install.log
    if [ $? -eq 0 ]; then info "OK"; else error "FAILED"; fail_inprogress; fi

    progress "$(timestamp) [LXC] [openHABian] Setting default password for openhabian user..."
    echo openhabian:openhabian | lxc-attach -n openhabian -- chpasswd &>> /var/log/yahm/openhabian_install.log
    if [ $? -eq 0 ]; then info "OK"; else error "FAILED"; fail_inprogress; fi

    # wait to get ethernet connection up
    sleep 5

    progress "$(timestamp) [LXC] [openHABian] Installing dependencies..."
    lxc-attach -n openhabian --  apt -y install wget gnupg git lsb-release ca-certificates iputils-ping rsyslog &>> /var/log/yahm/openhabian_install.log
    if [ $? -eq 0 ]; then info "OK"; else error "FAILED"; fail_inprogress; fi


    progress "$(timestamp) [LXC] [openHABian] Cloning openhabian repository..."
    lxc-attach -n openhabian -- git clone -b master https://github.com/openhab/openhabian.git /opt/openhabian &>> /var/log/yahm/openhabian_install.log
    if [ $? -eq 0 ]; then info "OK"; else error "FAILED"; fail_inprogress; fi

    progress "$(timestamp) [LXC] [openHABian] Linking openhabian configuration utility to /usr/bin..."
    lxc-attach -n openhabian -- ln -sfn /opt/openhabian/openhabian-setup.sh /usr/bin/openhabian-config &>> /var/log/yahm/openhabian_install.log
    if [ $? -eq 0 ]; then info "OK"; else error "FAILED"; fail_inprogress; fi

    progress "$(timestamp) [LXC] [openHABian] Creating openhabian default configuration..."
    echo -e "hostname=openHABian\nusername=openhabian\nuserpw=openhabian\ntimeserver=0.pool.ntp.org\nlocales='en_US.UTF-8 de_DE.UTF-8'\nsystem_default_locale=en_US.UTF-8\ntimezone=Europe/Berlin" > /var/lib/lxc/openhabian/rootfs/etc/openhabian.conf &>> /var/log/yahm/openhabian_install.log
    if [ $? -eq 0 ]; then info "OK"; else error "FAILED"; fail_inprogress; fi

    if [ $ARCH = "arm64" ]
    then
        lxc-attach -n openhabian -- dpkg --add-architecture armhf
    fi

    # Geting some IP informations
    OH_LXC_IP=$(get_lxc_ip "openhabian")
    LXC_HOST_IP=$(get_ip_to_route ${OH_LXC_IP})

#    progress "$(timestamp) [LXC] [ioBroker] Setup remote syslog..."
#    echo "*.*  @@${LXC_HOST_IP}" | lxc-attach -n openhabian -- tee /etc/rsyslog.d/10-yahm.conf &>> /var/log/yahm/iobroker_install.log
#    if [ $? -eq 0 ]; then info "OK"; else die "FAILED"; fail_inprogress; fi
#
#    progress "$(timestamp) [LXC] [ioBroker] Restarting syslog..."
#    lxc-attach -n openhabian -- service rsyslog restart &>> /var/log/yahm/iobroker_install.log
#    if [ $? -eq 0 ]; then info "OK"; else die "FAILED"; fail_inprogress; fi

    progress  "$(timestamp) [LXC] [openHABian] Starting openhabian installation, this can take some time....."
    lxc-attach -n openhabian -- /opt/openhabian/openhabian-setup.sh unattended
    if [ $? -eq 0 ]; then info "OK"; else error "FAILED"; fail_inprogress; fi

    progress  "$(timestamp) [LXC] [openHABian] Setup CCU2 Binding inside openHABian..."
    OH_CONF_DIR=/var/lib/lxc/openhabian/rootfs/etc/openhab2
    sed -i $OH_CONF_DIR/services/addons.cfg -e 's/^#binding.*$/binding=homematic/'
    echo "Bridge homematic:bridge:yahm [ gatewayAddress=\"${YAHM_LXC_IP}\" ]" > $OH_CONF_DIR/things/yahm-homematic.things
    lxc-attach -n openhabian  -- chown openhab:openhab /etc/openhab2/things/yahm-homematic.things
    if [ $? -eq 0 ]; then info "OK"; else error "FAILED"; fail_inprogress; fi

    progress  "$(timestamp) [LXC] [openHABian] Starting openHAB2 Service..."
    lxc-attach -n openhabian -- systemctl start openhab2.service
    if [ $? -eq 0 ]; then info "OK"; else error "FAILED"; fail_inprogress; fi

    progress "$(timestamp) [HOST] [openHABian] Creating some useful scripts..."

    # openhabian configuration script
    cat > /usr/sbin/openhabian-config <<EOF
#!/bin/bash

lxc-attach -n openhabian -- /opt/openhabian/openhabian-setup.sh

EOF
    # join script
    cat > /usr/sbin/yahm-openhabian <<EOF
#!/bin/bash

if [ $# -eq 0 ]
then
    lxc-attach -n openhabian
else
    lxc-attach -n openhabian -- \$@
fi

EOF

    # Set executable
    chmod +x  /usr/sbin/openhabian*
    chmod +x  /usr/sbin/yahm-openhabian
    info "OK"

    info "\n$(timestamp) [GLOBAL] [openHABian] Successfully installed\n"
    info "$(timestamp) [GLOBAL] [openHABian] Run openhabian-config to access openhabian configuration"
    info "$(timestamp) [GLOBAL] [openHABian] Run yahm-openhabian to execute command or login"
    info "$(timestamp) [GLOBAL] OpenHABian Login URL: http://${OH_LXC_IP}:8080"

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
    if [ $? -eq 0 ]; then info "OK"; else info "FAILED"; fail_inprogress; fi

    info "$(timestamp) [LXC] [openHABian] openHABian was upgraded successfully\n"
    info "$(timestamp) [GLOBAL] [openHABian] Run openhabian-config to access openhabian configuration"
}

_addon_uninstall()
{

    info "Deleting installed OpenHABian container. To cancel this operation type CTRL+C you have 5 seconds..."
    countdown
    info "... too late ;)"

    progress "$(timestamp) [HOST] [openHABian] Stopping openHABian container..."
    lxc-stop -n openhabian -k
    if [ $? -eq 0 ]; then info "OK"; else info "FAILED"; fail_inprogress; fi

    # cleanup 1
    umount /var/log/openhabian
    rm -rf /var/log/openhabian

    progress "$(timestamp) [HOST] [openHABian] Removing openHABian container..."
    lxc-destroy -n openhabian
    if [ $? -eq 0 ]; then info "OK"; else info "FAILED"; fail_inprogress; fi

    progress "$(timestamp) [HOST] [openHABian] Removing admin scripts"
    rm -rf /usr/sbin/openhabian-config
    rm -rf /usr/sbin/yahm-openhabian
    info "OK"

    # cleanup 2
    rm -rf /var/lib/lxc/openhabian
}
