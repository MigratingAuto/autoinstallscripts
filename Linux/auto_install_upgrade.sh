#!/bin/bash

# First I will update and upgrade my linux enviroment using apt
sudo apt update && apt upgrade -y

# install xRDP, fastfetch, net-tools, qemu guest agent
sudo apt install -y xrdp net-tools qemu-guest-agent

# enable and start the xrdp service and start the qemu-guest-agent
# sudo systemctl enable xrdp
# sudo systemctl start xrdp
# sudo systemctl enable qemu-guest-agent
# sudo systemctl start qemu-guest-agent
sudo systemctl enable --now xrdp qemu-guest-agent

# Will ask for user input to put in the username
echo "What is your username"
read -s userName

# Add your user to the “ssl-cert” group
sudo adduser $userName ssl-cert #change $username to user on linux
sudo systemctl restart xrdp

# Install fastfetch
# sudo apt install fastfetch -y

# Install Balloon Module for Proxmox and install qemu guest agent
sudo modprobe virtio_balloon
echo virtio_balloon | sudo tee -a /etc/modules