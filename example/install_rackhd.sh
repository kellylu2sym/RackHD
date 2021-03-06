#!/bin/bash
#
set -e
########################################################################################################
#
# 1.NOTE:  ** MUST READ **
#
#   Before using this script, please read the short "Prerequisites" session about nic setup in:  http://rackhd.readthedocs.io/en/latest/rackhd/ubuntu_package_installation.html
#
# 2.Usage:
#
#  run in Linux shell : wget -qO- https://raw.githubusercontent.com/RackHD/RackHD/one-key-quick-install/example/install_rackhd.sh | sudo bash
#
#  Then following the prompt, input the nic name for as RackHD's control network port.
#  the whole progress will take 20~30 minutes, depends on your network condition and machine performance.
#
#
#
# 3.What Does This Script Do:
#
#  (1) Get control nic port from user input via stdin
#  (2) Check the nic name. force set to 172.31.128.1 to eth1 , with user agreement via typing 'yes' on stdin
#  (3) inspect the NodeJS version, upgrade to NodeJS 4.x if older
#  (4) install some debian-packages as RackHD prerequisite
#  (5) install RackHD debian packages
#  (6) Update DHCP configuration in /etc/dhcp/dhcpd.conf, to enable RackHD as DHCP server on eth1 for 172.31.128.x IP range
#  (7) create some dummy file under /etc/default/, to let upstart works well
#  (8) create RackHD config file
#  (9) Copy images/binaries from bintray to static folder on RackHD application
#  (10) start RackHD services
#
#
#
# 4.Reference:
#
#  this script is based on RackHD document "Ubuntu Package Based Installation"
#  http://rackhd.readthedocs.io/en/latest/rackhd/ubuntu_package_installation.html 
#
#########################################################################################################


#############################################
#  Check if you have 2 NIC as below:
#  eth0 for the public network - providing access to RackHD APIs, and providing routed (layer3) access to out of band network for machines under management
#  eth1 for dhcp/pxe to boot/configure the machines. and IP configurated as static ( 172.31.128.0/22 )
#
#
# Parameter #1 ($1) is the NIC name of the control port for RacKHD
#
#############################################

check_NIC(){
    NIC_Name=$1
    echo $NIC_Name

    if [[ "$NIC_Name" -ne "eth1" ]]; then
        echo "[WARNING] RackHD takes the control NIC port as eth1 by default , with IP 172.31.128.0/22. RackHD may not function well if you left all config as default ! "
        sleep 2
    fi
    NIC_IP=$( ifconfig $NIC_Name | grep "inet addr" | awk -F: '{print $2}' | awk '{print $1}' )

    if [[ ! "$NIC_IP" == '172.31.128.1' ]]; then
	echo -n "Do you want this script to force set your $NIC_Name IP to 172.31.128.1 ? (type \"yes\" to force set, others to abort) > "
	read willing_to_force_ip
	if  [[ "$willing_to_force_ip" == 'yes' ]]; then
		sudo echo "\
		auto $NIC_Name
		iface eth1 inet static
		address 172.31.128.1
		netmask 255.255.252.0" >> /etc/network/interfaces
		echo "[INFO] will restart your $NIC_Name..."
		ifdown $NIC_Name
		ifup $NIC_Name
		New_IP= $( ifconfig $NIC_Name | grep "inet addr" | awk -F: '{print $2}' | awk '{print $1}' )
		echo "Your $NIC_Name new IP address is $New_IP"
	else
	        echo "[Error] default RackHD configure files takes eth1 with IP 172.31.128.1 as control NIC port.RackHD may not function well if you left all config as default !"
	        exit -4
	fi
    fi
}

#############################################
#  Check NodeJS is greater than 4.x
#
#############################################
check_install_nodejs(){

    do_install=true;

    if type -p nodejs; then
        # Node JS being installed
        NODEJS_VER=$(nodejs --version | sed s/v//)
        if [[ "$NODEJS_VER" < "4.0" ]] ; then
            # Remove Old NodeJS
            echo "[INFO] removing old version [$NODEJS_VER] of NodeJS..."
            sudo apt-get -y remove nodeijs nodejs-legacy
            do_install=true;
        else
            do_install=false;
        fi
    else
        do_install=true;
    fi


    if [[ $do_install = true  ]]; then
            echo "[INFO] Your NodeJS has not been installed or too old, install NodeJS 4.x first...."
            # Install NodeJS 4.x =========== Starts ============
            curl --silent https://deb.nodesource.com/gpgkey/nodesource.gpg.key | sudo apt-key add -
            VERSION=node_4.x
            DISTRO="$(lsb_release -s -c)"
            echo "deb https://deb.nodesource.com/$VERSION $DISTRO main" | sudo tee /etc/apt/sources.list.d/nodesource.list
            echo "deb-src https://deb.nodesource.com/$VERSION $DISTRO main" | sudo tee -a /etc/apt/sources.list.d/nodesource.list

            sudo apt-get update
            sudo apt-get -y install nodejs
            # Install NodeJS 4.x =========== Ends ============
    fi
    # Double Check ========
    if  ! type -p nodejs; then
        return -1;
    fi
    NODEJS_VER=$(nodejs --version | sed s/v//);
    if [[  "$NODEJS_VER" < "4.0" ]] ; then
        return -2;
    fi
        
    return 0

}
#############################################
#  Install Prerequisite
#
#############################################

install_prerequisite(){

    sudo apt-get -y install rabbitmq-server
    sudo apt-get -y install mongodb
    sudo apt-get -y install snmp
    sudo apt-get -y install ipmitool

    sudo apt-get -y install ansible
    sudo apt-get -y install apt-mirror
    sudo apt-get -y install amtterm

    sudo apt-get -y install isc-dhcp-server

}

#############################################
#  Install RackHD deb package from bintray
#
#############################################
install_RackHD(){
    echo "deb https://dl.bintray.com/rackhd/debian trusty main" | sudo tee -a /etc/apt/sources.list
    sudo apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys 379CE192D401AB61
    sudo apt-get update

   echo "[INFO] Install RackHD ........"

    sudo apt-get -y install on-dhcp-proxy on-http on-taskgraph
    sudo apt-get -y install on-tftp on-syslog
}

#############################################
#  Update DHCP config
#
#############################################
update_dhcp_config(){

    # After isc-dhcp-server installed, there should be /etc/dhcp/dhcpd.conf file
    sudo echo "
    ##### RackHD added lines########################
    deny duplicates;
    ignore-client-uids true;
    subnet 172.31.128.0 netmask 255.255.252.0 {
       range 172.31.128.2 172.31.131.254;
       # Use this option to signal to the PXE client that we are doing proxy DHCP
       option vendor-class-identifier \"PXEClient\";
    }
    " >> /etc/dhcp/dhcpd.conf
}
#############################################
#  Do tricky job to entertain upstart(Only for Ubuntu 14.04)
#
#############################################
make_upstart_happy(){
    #
    #  The services files in /etc/init/ all need a conf file to exist in /etc/default/{service} Touch those files to allow the upstart scripts to start automatically.
    #
    for service in $(echo "on-dhcp-proxy on-http on-tftp on-syslog on-taskgraph");
    do touch /etc/default/$service;
    done
}

#############################################
# Copy example config.json , and put it into /opt/monorail/config.json
#
# NOTE: this is only for quick tutorial, modify the config for your own situation
#############################################
create_RackHD_config(){
    wget https://raw.githubusercontent.com/RackHD/RackHD/master/packer/ansible/roles/monorail/files/config.json  -O /opt/monorail/config.json
}
#############################################
# Copy the PXE image and micro kernel from bintray 
#
#############################################
copy_RackHD_static_bins(){

    echo "[INFO] Will Copy static files, it will take a while"

    mkdir -p /var/renasar/on-tftp/static/tftp
    cd /var/renasar/on-tftp/static/tftp

    for file in $(echo "\
        monorail.ipxe \
        monorail-undionly.kpxe \
        monorail-efi64-snponly.efi \
        monorail-efi32-snponly.efi");do
    wget "https://dl.bintray.com/rackhd/binary/ipxe/$file"
    done

    mkdir -p /var/renasar/on-http/static/http/common
    cd /var/renasar/on-http/static/http/common

    for file in $(echo "\
        base.trusty.3.16.0-25-generic.squashfs.img \
        discovery.overlay.cpio.gz \
        initrd.img-3.16.0-25-generic \
        vmlinuz-3.16.0-25-generic");do
    wget "https://dl.bintray.com/rackhd/binary/builds/$file"
    done
}
#############################################
#
# start RackHD services 
#############################################
start_RackHD(){
    service on-http start
    service on-tftp start
    service on-dhcp-proxy start
    service on-syslog start
    service on-taskgraph start
}
#############################################
#
# Print Usage 
#############################################
print_usage(){
   curl http://localhost:9090/api/common/nodes/
   echo "curl http://localhost:9090/api/common/nodes/"
}

#############################################
#
#  Main Sequence
#############################################

if [ "$(whoami)" != "root" ]; then
	echo "Sorry, please run with sudo or root."
	exit 1
fi

echo -n "Please specific the name of control NIC port of RackHD(example : eth1)  > "
read input_NIC_Name
check_NIC $input_NIC_Name
check_install_nodejs
install_prerequisite
install_RackHD
update_dhcp_config
make_upstart_happy
create_RackHD_config
copy_RackHD_static_bins
start_RackHD
print_usage

