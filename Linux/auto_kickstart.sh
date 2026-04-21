#!/bin/bash
# First thing first is to update and upgrade my linux enviroment
sudo apt-get update -y && sudo apt-get upgrade -y && sudo apt-get dist-upgrade -y

mkdir wordpress
mkdir wordpressSQL

# Here I am downloading my wordpress .yml file to help get the docker container up and running without much user input
wget https://awsclilab-ryanrothenbuhler.s3.amazonaws.com/WordPress-compose.yml

# Here i am installing docker
sudo apt install -y apt-transport-https ca-certificates curl software-properties-common
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
sudo add-apt-repository -y "deb [arch=amd64] https://download.docker.com/linux/ubuntu bionic stable"
apt-cache policy docker-ce
sudo apt install docker-ce -y
sudo systemctl status docker

# Here I am installing a docker container with wordpress in it.
# And I am using the .yml file to set up the container contents.
sudo docker pull wordpress
docker-compose -f WordPress-compose.yml up

#one final update and upgrade of all pakages.
sudo apt-get update -y && sudo apt-get upgrade -y