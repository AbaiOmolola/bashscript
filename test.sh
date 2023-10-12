#!/bin/bash

# create shared folder
mkdir -p shared_folder

# create vagrant file
cat > Vagrantfile <<EOF
# -*- mode: ruby -*-
# vi: set ft=ruby :

Vagrant.configure("2") do |config|
 config.vm.box = "bento/ubuntu-20.04"

 # create a shared folder for all node
 config.vm.synced_folder "./shared_folder", "/vagrant"

 # create the master node
 config.vm.define "master" do |master|
  master.vm.hostname = "master-node"
  master.vm.network "private_network", ip: "192.168.56.11"
  master.vm.provider "virtualbox" do |vb|
   vb.memory = "2048"
   vb.cpus = 2
 end
 
  # provisioning script the master node
  master.vm.provision  "shell", inline: <<-SHELL
    sudo apt-get update
    
    # create the altschool user
    sudo useradd -m  -p "$(openssl passwd -1 1234)" -s /bin/bash altschool

    # grant altschool user sudo privileges
    sudo usermod -aG sudo altschool
    sudo echo "altschool ALL=(ALL:ALL) ALL" >> /etc/sudoers

    # generate ssh key for altschool users (without a passphrase)
    sudo -u altschool ssh-keygen -t rsa -N "" -f /home/altschool/.ssh/id_rsa -q

    # copy the public key to shared folder
    sudo cp /home/altschool/.ssh/id_rsa.pub /vagrant/master_id_rsa.pub

    # create /mnt/altschool directory
    sudo mkdir -p /mnt/altschool
    sudo chown altschool:altschool /mnt/altschool

    # create  test file in /mnt/altschool
    sudo -u altschool touch /mnt/altschool/test.txt

    # put the content in a test file
    sudo -u altschool echo "Hello World" > /mnt/altschool/test.txt

    # copy the content of /mnt/school into shared folder
    sudo cp -r /mnt/altschool /vagrant || true

    # install apache2, MySQL, PHP and other required packages 
    DEBIAN_FRONTEND=noninteractive sudo apt-get install -y apache2 mysql-server php libapache2-mod-php php-mysql

    # start  and enable apache2 service
    sudo systemctl start apache2
    sudo systemctl enable apache2

    sudo apt-get install debconf-utils

    #start and enable mysql service and secure installation 
   
    sudo debconf-set-selections <<< "mysql-server mysql-server/root_password password 1234"
    sudo debconf-set-selections <<< "mysql-server mysql-server/root_password_again password 1234"
    sudo systemctl start mysql
    sudo systemctl enable mysql

    # create a sample php file for validation of amp deck
    echo "<?php phpinfo(); ?>" > /var/www/html/info.php

    #install nginx
    DEBIAN_FRONTEND=noninteractive sudo apt-get install -y nginx

    # start and enable nginx service
    sudo systemctl start nginx
    sudo systemctl enable nginx

    #configure nginx as a load balancer for the master  and slave nodes
    sudo rm /etc/nginx/sites-enabled/default

    # create nginx new  configuration file
    sudo touch /etc/nginx/sites-available/loadbalancer.conf

    # put content of configuration in file
    sudo echo -e "upstream backend {
        server 192.168.56.11;
        server 192.168.58.12;
    }

    server {
        listen 90;
        location / {
            proxy_pass http://backend;
        }
    }" > /etc/nginx/sites-available/loadbalancer.conf

    # create symlink of the configuration file
    sudo ln -s /etc/nginx/sites-available/loadbalancer.conf /etc/nginx/sites-enabled/loadbalancer.conf

    # creat nginx default page
    sudo touch /var/www/html/loadbalancer.html

    # put content of  default page 
    sudo echo -e "<!Doctype html>
    <html>
    <head>
    <title>Load Balancer</title>
    </head>
    <body>
    <h1>Load Balancer</h1>
    <p>welcome to my default page  for my balancer</p>
    </body>
    </html>" > /var/www/html/loadbalancer.html

    #restart nginx service
    sudo systemctl restart nginx || true
    SHELL
  end
  
  # create slave  node
  config.vm.define "slave" do |slave|
  slave.vm.hostname = "slave-node"
  slave.vm.network "private_network", ip: "192.168.58.12"
  slave.vm.provider "virtualbox" do |vb|
   vb.memory = "2048"
   vb.cpus = 2
  end

  # provisioning script the  node
  slave.vm.provision  "shell", inline: <<-SHELL
    sudo apt-get update
   
    # copy the public key to shared folder to the slave node to append it to the 
    sudo cat /vagrant/master_id_rsa.pub >> /home/vagrant/.ssh/authorized_keys

    # remove public key from shared folder
    sudo rm /vagrant/master_id_rsa.pub || true

    # create /mnt/altschool/slave directory
    sudo mkdir -p /mnt/altschool/slave
    sudo chown vagrant:vagrant /mnt/altschool/slave


    # copy the content of shared folder to mnt/altschool/slave
    sudo cp -r /vagrant/* /mnt/altschool/slave/ || true

    # install apache2, MySQL, PHP and other required packages 
    DEBIAN_FRONTEND=noninteractive sudo apt-get install -y apache2 mysql-server php libapache2-mod-php php-mysql

    # start  and enable apache2 service
    sudo systemctl start apache2
    sudo systemctl enable apache2

    # start and enable mysql service and secure installation 
    sudo debconf-set-selections <<< "mysql-server mysql-server/root_password password 1234"
    sudo debconf-set-selections <<< "mysql-server mysql-server/root_password_again password 1234"
    sudo systemctl start mysql
    sudo systemctl enable mysql

    # create a sample php file for validation of amp deck
    echo "<?php phpinfo(); ?>" > /var/www/html/info.php
    SHELL
  end 
end
EOF

# start up vagrant
vagrant up
