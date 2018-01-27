#!/bin/bash

description="Homematic-Virtual-Interface"
addon_required="nodejs"
module_required=""

_addon_install()
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
        if [ ${#YAHM_LXC_IP} -eq 0 ]
        then
            error "ERROR: ${LXCNAME} container has no assigned ips, please enter manually"
            YAHM_LXC_IP=$(whiptail --inputbox "Please enter your CCU2 IP" 20 60 "000.000.000.000" 3>&1 1>&2 2>&3)
        fi
    else
        YAHM_RUNNING=0
        error "ERROR: ${LXCNAME} container is not running or present, please enter CCU2 IP manually"
        YAHM_LXC_IP=$(whiptail --inputbox "Please enter your CCU2 IP" 20 60 "000.000.000.000" 3>&1 1>&2 2>&3)
    fi

    if [ ${#YAHM_LXC_IP} -eq 0 ]
    then
        die "FATAL: CCU2 IP can not be empty"
    fi

    # create own user
    if [ $(lxc-attach -n nodejs -- cat /etc/passwd | grep hmvi |wc -l) -eq 0 ];
    then
        progress "Creating new hmvi user..."
        lxc-attach -n nodejs -- useradd -m hmvi
        if [ $? -eq 0 ]; then info "OK"; else die "FAILED"; fi
    fi

    progress "Installing homematic-virtual-interface (can take some time)..."
    lxc-attach -n nodejs --  npm install -g homematic-virtual-interface &>> /var/log/yahm/hvi_install.log
    if [ $? -eq 0 ]; then info "OK"; else die "FAILED"; fi

    progress "Writing CCU2 IP..."
    lxc-attach -n nodejs -- mkdir /home/hmvi/.hm_virtual_interface
    echo "{\"ccu_ip\":\"$YAHM_LXC_IP\",\"plugins\":[]}" > ${NODEJS_ROOT_FS}/home/hmvi/.hm_virtual_interface/config.json
    lxc-attach -n nodejs -- chown -R hmvi:hmvi /home/hmvi/.hm_virtual_interface
    info "OK"

    progress "Setup Startup script.."
    # Copy startup file
    lxc-attach -n nodejs -- cp /usr/lib/node_modules/homematic-virtual-interface/bin/hmvi.service /etc/systemd/system
    # Change username
    lxc-attach -n nodejs -- sed -i /etc/systemd/system/hmvi.service -e 's/^User=.*$/User=hmvi/'
    # Change executable
    lxc-attach -n nodejs -- sed -i /etc/systemd/system/hmvi.service -e 's/^ExecStart=.*$/ExecStart=\/usr\/bin\/hmvi 1> \/var\/s_hvl.log 2>\&1 \&/'
    info "OK"

    lxc-attach -n nodejs -- systemctl daemon-reload
    progress "Enable hmvi Service..."
    lxc-attach -n nodejs -- systemctl enable hmvi.service &>> /var/log/yahm/hvi_install.log
    if [ $? -eq 0 ]; then info "OK"; else die "FAILED"; fi
    progress "Starting hmvi Service..."
    lxc-attach -n nodejs -- systemctl start hmvi.service &>> /var/log/yahm/hvi_install.log
    if [ $? -eq 0 ]; then info "OK"; else die "FAILED"; fi

    if [ $YAHM_RUNNING -eq 1 ]
    then
        if [ $(cat ${LXC_ROOT_FS}/usr/local/etc/config/InterfacesList.xml | grep '<name>HVL</name>' | wc -l ) -eq 0 ]
        then
            progress "Updating InterfaceList.xml"
            my_url=$(lxc-info -i -n nodejs | awk '{print $2}')
            sed -i ${LXC_ROOT_FS}/usr/local/etc/config/InterfacesList.xml -e "s/<\/interfaces>/<ipc><name>HVL<\/name><url>xmlrpc:\/\/${my_url}<\/url><info>HVL<\/info><\/ipc><\/interfaces>/"
            info "OK"
        fi
    else
        cp ${NODEJS_ROOT_FS}/usr/lib/node_modules/homematic-virtual-interface/hvl_addon.tar.gz ${HOME}
        info "Please install hvl_addon.tar.gz addon in CCU2-GUI"
        info "You can find hvl_addon.tar.gz inside your home directory, or download it from: https://github.com/thkl/Homematic-Virtual-Interface"
    fi

}

_addon_update()
{

    if [ $(lxc-info -n nodejs | grep RUNNING | wc -l) -eq 0 ]
    then
        die "Node.js container must be running, please start it first: lxc-start -n nodejs -d"
    fi

    progress "Updating homematic-virtual-interface..."
    lxc-attach -n nodejs --  npm update -g homematic-virtual-interface
    if [ $? -eq 0 ]; then info "OK"; else die "FAILED"; fi
}

_addon_uninstall()
{

    if [ $(lxc-info -n nodejs | grep RUNNING | wc -l) -eq 0 ]
    then
        die "Node.js container must be running, please start it first: lxc-start -n nodejs -d"
    fi

    progress "Stopping hmvi Service..."
    lxc-attach -n nodejs -- systemctl stop hmvi.service

    progress "Uninstalling homematic-virtual-interface..."
    lxc-attach -n nodejs --  npm uninstall -g homematic-virtual-interface &>> /var/log/yahm/nvi_uninstall.log
    if [ $? -eq 0 ]; then info "OK"; else die "FAILED"; fi

    progress "Removing hmvi user"
    lxc-attach -n nodejs -- userdel -r -f hmvi

    if [ $(lxc-info -n ${LXCNAME} | grep RUNNING | wc -l) -eq 1 ]
    then
        check_install_deb "xmlstarlet"

        if [ ! -f "${LXC_ROOT_FS}/usr/local/etc/config/InterfacesList.xml" ]
        then
            die "InterfacesList.xml can not be found, please start ${LXCNAME} first"
        fi

        info "Removing HVL from InterfacesLixt.xml"
        cd ${LXC_ROOT_FS}/usr/local/etc/config/
        if [ $( cat InterfacesList.xml | grep HVL | wc -l ) -gt 0 ]
        then
            xmlstarlet ed -d "/interfaces/ipc[name='HVL']" InterfacesList.xml > InterfacesList.xml.new
            mv InterfacesList.xml InterfacesList.xml.bak
            mv InterfacesList.xml.new InterfacesList.xml
        fi
    else
        info "Please remove hvl addon in CCU2-GUI"
    fi

}
