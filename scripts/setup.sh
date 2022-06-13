# This script setup the environment needed for VPN usage on lightning network nodes
# Use with care
#
# Usage: sudo bash setup.sh

# check if sudo
if [ "$EUID" -ne 0 ]
  then echo "Please run as root (with sudo)"
  exit 1
fi

echo "
##############################
#         TunnelSats         #
#        Setup Script        #
##############################";echo

# check for downloaded tunnelsats.conf, exit if not available
# get current directory
directory=$(dirname -- $(readlink -fn -- "$0"))
echo "Looking for WireGuard config file..."
if [ ! -f $directory/tunnelsats.conf ]; then
  echo "> ERR: tunnelsats.conf not found. Please place it where this script is located.";echo
  exit 1
else
  echo "> tunnelsats.conf found, proceeding.";echo
fi

# RaspiBlitz: deactivate lnd.check.sh
if [ $(hostname) = "raspberrypi" ] && [ -f /mnt/hdd/lnd/lnd.conf ]; then
    if [ -f /home/admin/config.scripts/lnd.check.sh ]; then
        mv /home/admin/config.scripts/lnd.check.sh /home/admin/config.scripts/lnd.check.bak
        echo "RaspiBlitz detected, safety check for lnd.conf removed";echo
    fi
fi

echo "Checking and installing requirements..."
echo "Updating the package repositories..."
apt-get update > /dev/null;echo

# check cgroup-tools
echo "Checking cgroup-tools..."
checkcgroup=$(cgcreate -h 2> /dev/null | grep -c "Usage")
if [ $checkcgroup -eq 0 ]; then
    echo "Installing cgroup-tools..."
    if apt-get install -y cgroup-tools > /dev/null;then
        echo "> cgroup-tools installed";echo
    else
        echo "> failed to install ncgroup-tools";echo
        exit 1
    fi
else
    echo "> cgroup-tools found";echo
fi

sleep 2

# check nftables
echo "Checking nftables installation..."
checknft=$(nft -v 2> /dev/null | grep -c "nftables")
if [ $checknft -eq 0 ]; then
    echo "Installing nftables..."
    if apt-get install -y nftables > /dev/null;then
        echo "> nftables installed";echo
    else
        echo "> failed to install nftables";echo
        exit 1
    fi
else
    echo "> nftables found";echo
fi

sleep 2

# check wireguard
echo "Checking wireguard installation..."
checkwg=$(wg -v 2> /dev/null | grep -c "wireguard-tools")
if [ ! -f /etc/wireguard ] && [ $checkwg -eq 0 ]; then
    echo "Installing wireguard..."
    if apt-get install -y wireguard > /dev/null;then
        echo "> wireguard installed";echo
    else
        echo "> failed to install wireguard";echo
        exit 1
    fi
else
    echo "> wireguard found";echo
fi

sleep 2


# check for downloaded tunnelsats.conf, exit if not available
# get current directory
echo "Copying WireGuard config file..."
directory=$(dirname -- $(readlink -fn -- "$0"))
if [ -f $directory/tunnelsats.conf ]; then
   cp $directory/tunnelsats.conf /etc/wireguard/
   if [ -f /etc/wireguard/tunnelsats.conf ]; then
      echo "> tunnelsats.conf copied to /etc/wireguard/";echo
   else
      echo "> ERR: tunnelsats.conf not found in /etc/wireguard/. Please check for errors.";echo
   fi
else
   echo "> tunnelsats.conf VPN config file not found. Please put your config file in the same directory as this script!";echo
   exit 1
fi

sleep 2


# setup split-tunneling
# create file
echo "Creating splitting.sh file in /etc/wireguard/..."
echo "#!/bin/sh
set -e
dir_netcls=\"/sys/fs/cgroup/net_cls\"
torsplitting=\"/sys/fs/cgroup/net_cls/tor_splitting\"
modprobe cls_cgroup
if [ ! -d \"\$dir_netcls\" ]; then
  mkdir \$dir_netcls
  mount -t cgroup -o net_cls none \$dir_netcls
  echo \"> Successfully added cgroup net_cls subsystem\"
fi
if [ ! -d \"\$torsplitting\" ]; then
  mkdir /sys/fs/cgroup/net_cls/tor_splitting
  echo 1118498  > /sys/fs/cgroup/net_cls/tor_splitting/net_cls.classid
  echo \"> Successfully added Mark for net_cls subsystem\"
else
  echo \"> Mark for net_cls subsystem already present\"
fi
# add Tor pid(s) to cgroup
pgrep -x tor | xargs -I % sh -c 'echo % > /sys/fs/cgroup/net_cls/tor_splitting/tasks' > /dev/null
count=\$(cat /sys/fs/cgroup/net_cls/tor_splitting/tasks | wc -l)
if [ \$count -eq 0 ];then
  echo \"> ERR: no pids added to file\"
  exit 1
else
  echo \"> \${count} Tor process(es) successfully excluded\"
fi
" > /etc/wireguard/splitting.sh
if [ -f /etc/wireguard/splitting.sh ]; then
  echo "> /etc/wireguard/splitting.sh created.";echo
else
  echo "> ERR: /etc/wireguard/splitting.sh was not created. Please check for errors.";
  exit 1
fi

# run it once
if [ -f /etc/wireguard/splitting.sh ];then
    echo "> splitting.sh created, executing...";
    # run
    bash /etc/wireguard/splitting.sh
    echo "> Split-tunneling successfully executed";echo
else
    echo "> ERR: splitting.sh execution failed";echo
    exit 1
fi

# enable systemd service
# create systemd file
echo "Creating splitting systemd service..."
if [ ! -f /etc/systemd/system/splitting.service ]; then
  # if we are on Umbrel || Start9 (Docker solutions), create a timer to restart and re-check Tor pids
  if [ $(hostname) = "umbrel" ] || [ -f /embassy-data/package-data/volumes/lnd/data/main/lnd.conf ]; then
     echo "[Unit]
Description=Splitting Tor Traffic by Timer
StartLimitInterval=200
StartLimitBurst=5
[Service]
Type=oneshot
ExecStart=/bin/bash /etc/wireguard/splitting.sh
[Install]
WantedBy=multi-user.target
" > /etc/systemd/system/splitting.service

    echo "[Unit]
Description=5min timer for splitting.service
[Timer]
OnBootSec=60
OnUnitActiveSec=300
Persistent=true
[Install]
WantedBy=timers.target
    " > /etc/systemd/system/splitting.timer
    
    if [ -f /etc/systemd/system/splitting.service ]; then
      echo "> splitting.service created";echo
    else
      echo "> ERR: splitting.service not created. Please check for errors.";echo
    fi
    if [ -f /etc/systemd/system/splitting.timer ]; then
      echo "> splitting.timer created";echo
    else
      echo "> ERR: splitting.timer not created. Please check for errors.";echo
    fi
  else # no Docker
     echo "[Unit]
Description=Splitting Tor Traffic after Restart
# Make sure it starts when tor service is running (thats why restart settings are crucial here)
Requires=tor@default.service
After=tor@default.service
StartLimitInterval=200
StartLimitBurst=5
[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/bin/bash /etc/wireguard/splitting.sh
[Install]
WantedBy=multi-user.target
" > /etc/systemd/system/splitting.service
  fi
fi

# enable and start splitting.service
if [ -f /etc/systemd/system/splitting.service ]; then
  systemctl daemon-reload > /dev/null
  if systemctl enable splitting.service > /dev/null &&
     systemctl start splitting.service > /dev/null; then
    echo "> splitting.service: systemd service enabled and started";echo
  else
    echo "> ERR: splitting.service could not be enabled or started. Please check for errors.";echo
  fi
    # Docker: enable timer
  if [ -f /etc/systemd/system/splitting.timer ]; then
    if systemctl enable splitting.timer > /dev/null &&
       systemctl start splitting.timer > /dev/null; then
      echo "> splitting.timer: systemd timer enabled and started";echo
    else
      echo "> ERR: splitting.timer: systemd timer could not be enabled or started. Please check for errors.";echo
    fi
  fi
else
  echo "> ERR: splitting.service was not created. Please check for errors.";echo
  exit 1
fi

sleep 2

## create and enable wireguard service
echo "Initializing the service..."
systemctl daemon-reload > /dev/null
systemctl enable wg-quick@tunnelsats > /dev/null
echo "> wireguard systemd service enabled"
systemctl start wg-quick@tunnelsats > /dev/null
echo "> wireguard systemd service started";echo

##Add KillSwitch to nftables
echo "Adding KillSwitch to nftables..."
if [ $(hostname) != "raspberrypi" ]; then
  #Create output chain 
  $(nft add chain inet $(wg show | grep interface | awk '{print $2}') output '{type filter hook output priority filter; policy accept;}')
  #Flush Table first to prevent redundant rules
  $(nft flush chain inet $(wg show | grep interface | awk '{print $2}') output)
  # Add Kill Switch Rule
  $(nft insert rule inet $(wg show | grep interface | awk '{print $2}')   output oifname != $(wg show | grep interface | awk '{print $2}')  meta mark != 0xdeadbeef  ip daddr != $(hostname -I | awk '{print $1}' | cut -d"." -f1-3).0/24 ip daddr != 224.0.0.1/24 oifname != "br-*" oifname != "veth*"  fib daddr type != local counter drop comment \"tunnelsats kill switch\" )  
else
  #Create output chain 
  $(nft add chain inet $(wg show | grep interface | awk '{print $2}') output '{type filter hook output priority filter; policy accept;}')
  #Flush Table first to prevent redundant rules
  $(nft flush chain inet $(wg show | grep interface | awk '{print $2}') output)
  #Add Kill Switch Rule
  $(nft insert rule inet  $(wg show | grep interface | awk '{print $2}')  output oifname !=  $(wg show | grep interface | awk '{print $2}') ip daddr != $(hostname -I | awk '{print $1}' | cut -d"." -f1-3).0/24 ip daddr != 224.0.0.1/24  meta mark != 0xdeadbeef fib daddr type != local  counter drop comment \"tunnelsats kill switch\" )
fi

#Checking for Kill Switch

killSwitchExists=$(nft -s list table inet $(wg show | grep interface | awk '{print $2}') | grep -c "tunnelsats kill switch")
if [ $killSwitchExists -eq 0 ]; then
  echo "> ERR: Activating Kill Switch failed, check whether tunnel activated";echo
  exit 1
else
  echo "> Kill Switch Activated";echo
fi

sleep 2

## UFW firewall configuration
vpnExternalPort=$(grep "#VPNPort" /etc/wireguard/tunnelsats.conf | awk '{ print $3 }')
vpnInternalPort="9735"
echo "Checking for firewalls and adjusting settings if applicable...";
checkufw=$(ufw version 2> /dev/null | grep -c "Canonical")
if [ $checkufw -gt 0 ]; then
   ufw disable > /dev/null
   ufw allow $vpnInternalPort comment '# VPN Tunnelsats' > /dev/null
   ufw --force enable > /dev/null
   echo "> ufw detected. VPN port rule added";echo
else
   echo "> ufw not detected";echo
fi

# Instructions
vpnExternalIP=$(grep "Endpoint" /etc/wireguard/tunnelsats.conf | awk '{ print $3 }' | cut -d ":" -f1)

echo " 
These are your personal VPN credentials for your lnd.conf.
Put these in the sections shown in brackets: 
#########################################
[Application Options]
listen=0.0.0.0:9735
externalip=${vpnExternalIP}:${vpnExternalPort}
[Tor]
tor.streamisolation=false
tor.skip-proxy-for-clearnet-targets=true
#########################################
Please save them in a file or write them down for later use.
A more detailed guide is available at: 
https://blckbx.github.io/tunnelsats/ 
Afterwards please restart LND / your system for changes to take effect.
VPN setup completed!";echo

# the end
exit 0
