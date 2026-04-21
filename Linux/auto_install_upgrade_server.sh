#!/bin/bash

# First I will update and upgrade my linux enviroment using apt
sudo apt update && apt upgrade -y

# install net-tools, qemu guest agent
sudo apt install -y net-tools qemu-guest-agent

# enable and start the qemu-guest-agent
sudo systemctl enable --now qemu-guest-agent

# Install Balloon Module for Proxmox and install qemu guest agent
sudo modprobe virtio_balloon
echo virtio_balloon | sudo tee -a /etc/modules