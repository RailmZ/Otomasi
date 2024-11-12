#!/bin/bash

echo "Configuring local repository to Kartolo..."

cat <<EOT > /etc/apt/sources.list
deb http://kartolo.sby.datautama.net.id/ubuntu/ focal main restricted universe multiverse
deb http://kartolo.sby.datautama.net.id/ubuntu/ focal-updates main restricted universe multiverse
deb http://kartolo.sby.datautama.net.id/ubuntu/ focal-security main restricted universe multiverse
deb http://kartolo.sby.datautama.net.id/ubuntu/ focal-backports main restricted universe multiverse
deb http://kartolo.sby.datautama.net.id/ubuntu/ focal-proposed main restricted universe multiverse
EOT

apt update

echo "Configuring VLAN 10 on eth1 using Netplan..."

cat <<EOT > /etc/netplan/01-netcfg.yaml
network:
  version: 2
  ethernets:
    eth1:
      dhcp4: no
  vlans:
    eth1.10:
      id: 10
      link: eth1
      addresses:
        - 192.168.29.1/24
EOT

netplan apply

echo "Installing and configuring DHCP server..."
apt install -y isc-dhcp-server

cat <<EOT > /etc/dhcp/dhcpd.conf
subnet 192.168.29.0 netmask 255.255.255.0 {
    range 192.168.29.10 192.168.29.100;
    option routers 192.168.29.1;
    option domain-name-servers 8.8.8.8, 8.8.4.4;
}
EOT

echo 'INTERFACESv4="eth1.10"' > /etc/default/isc-dhcp-server
systemctl restart isc-dhcp-server

echo "Enabling IP forwarding permanently..."
echo "net.ipv4.ip_forward = 1" >> /etc/sysctl.conf
sysctl -p

iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE

echo "Adding route to MikroTik network..."
ip route add 192.168.200.0/24 via 192.168.29.10  # Adjust as needed

echo "Configuring Cisco device..."
CISCO_USER=""
CISCO_PASS=""
CISCO_IP="192.168.29.10"

sshpass -p "$CISCO_PASS" ssh -o StrictHostKeyChecking=no $CISCO_USER@$CISCO_IP << EOF
enable
configure terminal
interface fastEthernet 0/0
switchport mode trunk
exit
interface fastEthernet 0/1
switchport mode access
switchport access vlan 10
exit
end
EOF

echo "Configuring MikroTik device..."
MIKROTIK_USER="admin"
MIKROTIK_PASS="123"
MIKROTIK_IP="192.168.29.11"

sshpass -p "$MIKROTIK_PASS" ssh -o StrictHostKeyChecking=no $MIKROTIK_USER@$MIKROTIK_IP << EOF
/ip dhcp-client add interface=ether1 disabled=no
/ip address add address=192.168.200.1/24 interface=ether2
/ip dhcp-server add name=dhcp1 interface=ether2 address-pool=dhcp_pool disabled=no
/ip pool add name=dhcp_pool ranges=192.168.200.10-192.168.200.100
/ip dhcp-server network add address=192.168.200.0/24 gateway=192.168.200.1
/ip route add dst-address=0.0.0.0/0 gateway=192.168.29.1
EOF

echo "Automation complete."
