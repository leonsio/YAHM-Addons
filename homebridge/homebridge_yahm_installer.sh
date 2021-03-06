#!/bin/bash

_homebridge_install()
{

    NODEJS_ROOT_FS="/var/lib/lxc/nodejs/rootfs"


    if [ $(lxc-info -n nodejs | grep RUNNING | wc -l) -eq 0 ]
    then
        die "Node.js container must be running, please start it first: lxc-start -n nodejs -d"
    fi

    if [ $(lxc-info -n ${LXCNAME} | grep RUNNING | wc -l) -eq 1 ]
    then
        YAHM_RUNNING=1
        YAHM_LXC_IP=$(lxc-info -i -n ${LXCNAME} | awk '{print $2}')
        if [ ${YAHM_LXC_IP} -eq 0 ]
        then
            error "ERROR: ${LXCNAME} container has no assigned ips, please enter manually"
            YAHM_LXC_IP=$(whiptail --inputbox "Please enter your CCU2 IP" 20 60 "000.000.000.000" 3>&1 1>&2 2>&3)
        fi
    else
        YAHM_RUNNING=0
        error "ERROR: ${LXCNAME} container is not running or present, please enter CCU2 IP manually"
        YAHM_LXC_IP=$(whiptail --inputbox "Please enter your CCU2 IP" 20 60 "000.000.000.000" 3>&1 1>&2 2>&3)
    fi

    if [ ${YAHM_LXC_IP} -eq 0 ]
    then
        die "FATAL: CCU2 IP can not be empty"
    fi

    progress "$(timestamp) [LXC] [node.js] Installing dependencies..."
    lxc-attach -n nodejs -- /usr/bin/apt -y install avahi-daemon libavahi-compat-libdnssd-dev &>> /var/log/yahm/homebridge_install.log
    if [ $? -eq 0 ]; then info "OK"; else error "FAILED"; fi

    # create own user
    if [ $(lxc-attach -n nodejs -- cat /etc/passwd | grep homebridge |wc -l) -eq 0 ];
    then
        progress "Creating new homebridge user..."
        lxc-attach -n nodejs -- useradd -m homebridge
        if [ $? -eq 0 ]; then info "OK"; else die "FAILED"; fi
    fi

    progress "Installing Homebridge (can take some time)..."
    lxc-attach -n nodejs -- npm install -g homebridge --unsafe-perm &>> /var/log/yahm/homebridge_install.log
    if [ $? -eq 0 ]; then info "OK"; else die "FAILED"; fi
	progress "Installing Homematic Plugin..."
    lxc-attach -n nodejs -- npm install -g homebridge-homematic --unsafe-perm &>> /var/log/yahm/homebridge_install.log
    if [ $? -eq 0 ]; then info "OK"; else die "FAILED"; fi

    progress "Writing CCU2 IP..."
    lxc-attach -n nodejs -- mkdir /home/homebridge/.homebridge/
    cat > $NODEJS_ROOT_FS/home/homebridge/.homebridge/config.json <<EOF
{
	"bridge": {
		"name": "Homebridge",
		"username": "CC:22:3D:E3:CE:30",
		"port": 51826,
		"pin": "031-45-154"
	},
	"description": "This is an autogenerated config. only the homematic platform is enabled. see the sample for more",
	"platforms": [{
		"platform": "HomeMatic",
		"name": "HomeMatic CCU",
		"ccu_ip": "$YAHM_LXC_IP",
		"subsection": "",
		"filter_device": [],
		"filter_channel": [],
		"outlets": []
	}],
	"accessories": []
}
EOF
    lxc-attach -n nodejs -- chown -R homebridge:homebridge /home/homebridge/.homebridge/
    info "OK"

    progress "Setup Startup script.."
    lxc-attach -n nodejs -- touch /etc/default/homebridge
    cat > ${NODEJS_ROOT_FS}/etc/systemd/system/homebridge.service <<EOF
[Unit]
Description=Node.js HomeKit Server
After=syslog.target network-online.target

[Service]
Type=simple
User=homebridge
EnvironmentFile=/etc/default/homebridge
ExecStart=/usr/bin/homebridge \$HOMEBRIDGE_OPTS
Restart=on-failure
RestartSec=10
KillMode=process

[Install]
WantedBy=multi-user.target
EOF
    info "OK"

    lxc-attach -n nodejs -- systemctl daemon-reload
    progress "Enable homebridge Service..."
    lxc-attach -n nodejs -- systemctl enable homebridge.service &>> /var/log/yahm/homebridge_install.log
    if [ $? -eq 0 ]; then info "OK"; else die "FAILED"; fi
    progress "Starting homebridge Service..."
    lxc-attach -n nodejs -- systemctl start homebridge.service &>> /var/log/yahm/homebridge_install.log
    if [ $? -eq 0 ]; then info "OK"; else die "FAILED"; fi

}

_homebridge_update()
{

    if [ $(lxc-info -n nodejs | grep RUNNING | wc -l) -eq 0 ]
    then
        die "Node.js container must be running, please start it first: lxc-start -n nodejs -d"
    fi

    progress "Updating homebridge..."
    lxc-attach -n nodejs --  npm update -g homebridge &>> /var/log/yahm/homebridge_update.log
    if [ $? -eq 0 ]; then info "OK"; else die "FAILED"; fi

    progress "Updating homebridge-homematic..."
    lxc-attach -n nodejs --  npm update -g homebridge-homematic &>> /var/log/yahm/homebridge_update.log
    if [ $? -eq 0 ]; then info "OK"; else die "FAILED"; fi
}

_homebridge_uninstall()
{

    if [ $(lxc-info -n nodejs | grep RUNNING | wc -l) -eq 0 ]
    then
        die "Node.js container must be running, please start it first: lxc-start -n nodejs -d"
    fi

    progress "Stopping homebridge Service..."
    lxc-attach -n nodejs -- systemctl stop homebridge.service &>> /var/log/yahm/homebridge_uninstall.log

    progress "Uninstalling homebridge..."
    lxc-attach -n nodejs --  npm uninstall -g homebridge  &>> /var/log/yahm/homebridge_uninstall.log
    if [ $? -eq 0 ]; then info "OK"; else die "FAILED"; fi

    progress "Uninstalling homebridge-homematic..."
    lxc-attach -n nodejs --  npm uninstall -g homebridge-homematic  &>> /var/log/yahm/homebridge_uninstall.log
    if [ $? -eq 0 ]; then info "OK"; else die "FAILED"; fi

    progress "Removing homebridge user"
    lxc-attach -n nodejs -- userdel -r -f homebridge &>> /var/log/yahm/homebridge_uninstall.log
    info "OK"

}
