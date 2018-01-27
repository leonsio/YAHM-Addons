#!/bin/bash

description="Homematic Fake LAN Adapter"
addon_required=""
module_required=""

# Default Parameter
file_hm_fake_lan_gw='/etc/init.d/hm-fake-lan-gw'
file_cmdline_txt='/boot/cmdline.txt'
reboot=0 # Neustart ausfuehren

kernel_version=$(uname -r | sed -e 's/-.*//i')
if [ $(ver ${kernel_version}) -ge $(ver 4.4.9) ]
then
    overlay_file="pi3-miniuart-bt"
else
    overlay_file="pi3-miniuart-bt-overlay"
fi

_addon_install()
{

    die "Not tested"
    if [ -e ${LXC_ROOT_MODULES}/hm-mod-rpi-pcb ] && [ $IS_FORCE -ne 1 ]
    then
        die "ERROR: hm-mod-rpi-pcb module is installed, please remove it first"
    fi

    if [ -e ${LXC_ROOT_MODULES}/hm-mod-rpi-pcb ]
    then
        error "ERROR: homematic-ip module is installed, t.b.d"
    fi

    if [ -e ${LXC_ROOT_MODULES}/pivccu-driver ] && [ $IS_FORCE -ne 1 ]
    then
        die "ERROR: pivccu-driver module is installed, t.b.d"
    fi

    if [ "$BOARD_TYPE" != "Raspberry Pi" ] && [ $IS_FORCE -ne 1 ]
    then
        info "See Wiki for manual installation"
        die "ERROR: This module is for Raspberry Pi only, use -f flag to overwrite this check"
    fi

    info "Found hardware: $BOARD_TYPE $BOARD_VERSION"

    # Raspberry 2 oder 3 ?
    if [ "$BOARD_TYPE" = "Raspberry Pi" ] && [ "$BOARD_VERSION" = "3" ]
    then
        progress "Trying to disable bluetooth on Raspberry Pi 3 to use HM-MOD-RPI-PCB"

        if [ ! -f /boot/config.txt ] && [ $IS_FORCE -ne 1 ]
        then
            die "ERROR: File /boot/config.txt does not exist!"
        fi

        if [ $(cat /boot/config.txt | grep ${overlay_file} | wc -l ) -eq 0 ]
        then
            echo -e "\n# Allow the normal UART pins to work\ndtoverlay=${overlay_file}\nenable_uart=1\nforce_turbo=1" >> /boot/config.txt
            info "Modification /boot/config.txt done."
            reboot=$((reboot+1))
        fi
    elif [ "$BOARD_TYPE" = "Raspberry Pi" ] && [ "$BOARD_VERSION" = "2" ]
    then
        if [ $(ver ${kernel_version}) -ge $(ver 4.4.9) ]
        then
            if [ $(cat /boot/config.txt | grep "^enable_uart=0" | wc -l) -eq 1 ]
            then
                sed -i /boot/config.txt -e "s/enable_uart=0/enable_uart=1/"
                info "Modification /boot/config.txt done."
                reboot=$((reboot+1))
            else
                echo -e "\n# Allow the normal UART pins to work\nenable_uart=1" >> /boot/config.txt
                info "Modification /boot/config.txt done."
                reboot=$((reboot+1))
            fi
        fi
    fi

    # Disable serial
    progress "Trying to disable serial console"
    if [ ! -f $file_cmdline_txt ] && [ $IS_FORCE -ne 1 ]
    then
        die "ERROR: File $file_cmdline_txt does not exist!"
    fi

    if [ $(cat /boot/cmdline.txt|grep "console=serial0,115200"|wc -l) -gt 0 ];then
        sed -i /boot/cmdline.txt -e "s/console=ttyAMA0,[0-9]\+ //"
        sed -i /boot/cmdline.txt -e "s/console=serial0,[0-9]\+ //"
        reboot=$((reboot+1))
        info "Serial disabled successfully."
    else
        info "Serial already disabled"
    fi


    # Create service 
    if [ $(insserv -s|grep hm-mod-rpi|wc -l) -eq 0 ]
    then
        progress "Create service for fake hm lan gateway"
        cat > $file_hm_fake_lan_gw <<EOF
#!/bin/sh
### BEGIN INIT INFO
# Provides:       hm-fake-lan-gw yahm-gw
# Required-Start: udev mountkernfs \$remote_fs
# Required-Stop:  
# Default-Start: 2 3 4 5
# Default-Stop: 0 1 6
# Short-Description: Start Fake HM-LAN-GW Service
# Description: http://homematic-forum.de/forum/viewtopic.php?f=18&t=27705
### END INIT INFO

. /lib/lsb/init-functions

case "\$1" in
  start)
    log_daemon_msg "Starting HM-LAN-GW Service"
    printf "Starting HM-LAN-GW Service"
    cd /opt/YAHM/share/tools/hmgw
    /opt/YAHM/share/tools/hmgw/hmlangw -n auto  -s /dev/${dev_int} > /var/log/hmlangw.log 2>&1 &
    log_end_msg 0
    ;;
  stop)
    log_daemon_msg "Stopping HM-LAN-GW Service"
    printf "Stopping HM-LAN-GW Service"
    killall -w hmlangw 
    ;;
  *)
    echo "Usage: \$0 start|stop" >&2
    exit 3
    ;;
esac
EOF
        chmod +x $file_hm_fake_lan_gw
        if [ "$CODENAME" = "stretch" ] ;
        then
            update-rc.d hm-fake-lan-gw remove
            update-rc.d hm-fake-lan-gw defaults
            update-rc.d hm-fake-lan-gw enable
            systemctl daemon-reload
        else
            insserv $file_hm_fake_lan_gw
            info "Installing fake gw service is done."
        fi
    fi 

    info "\nPlease setup your System as a HM-LAN-GW inside CCU2 GUI"

    # Reboot
    if [ $reboot -gt 0 ]
    then
        info "For serial number see /opt/YAHM/share/tools/hmgw/serialnumber.txt file, after the service is started\n"
        echo "======================================"
        echo "Rebooting in 60 seconds to apply settings (to chancel reboot type 'shutdown -c')..."
        echo "======================================"
        shutdown -r +1 "Rebooting to disable serial console"
    else
        info "Fake HM-LAN-GW was installed successfully"
        info "Trying to start service"
        systemctl enable hm-fake-lan-gw
        systemctl start hm-fake-lan-gw
        SERIAL=$(cat /opt/YAHM/share/tools/hmgw/serialnumber.txt)
        info "Serial number for HM-LAN-GW is: ${SERIAL}\n"
    fi
}

_addon_update()
{
    info "t.b.d"
}

_addon_uninstall()
{
    die "not tested"

    info "Uninstall gpio reset service..."
    if [ -e $file_hm_fake_lan_gw ];then

        if [ "$CODENAME" = "stretch" ] ;
        then
            update-rc.d hm-fake-lan-gw remove
        else
            insserv -r $file_hm_fake_lan_gw
        fi

        rm $file_hm_fake_lan_gw
        progress "Remove $file_hm_fake_lan_gw."
    fi
}
