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
    # Create service 
    if [ $(insserv -s|grep hm-mod-rpi|wc -l) -eq 0 ]; then 
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

}

_addon_uninstall()
{

}
