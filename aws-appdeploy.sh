#!/bin/bash

ansiblecheck() {

        test=`nc -w1 -z $ansibleip $ansiblesshport ; echo $?`
        if [ "$test" -ne "0" ];
        then
		echo "Ansible isn't reachable using ssh. Exiting."
		exit 1
	fi
}

gitrepocheck() {

        httpcode=`curl -I https://github.com/jpazdyga/jblog 2>1| grep 404 | grep HTTP | cut -d' ' -f2`
        if [ "$httpcode" -eq "404" ];
        then
                echo -e " \nGithub repository url you have specified is probably private.\n\n"
                read -p "Do you want to proceed using your [c]redentials, [t]oken or [q]uit? [c/t/q] " resp1
                case $resp1 in
                        c)
                                read -p "Enter your github usename: " username
                                read -sp "Enter your github password: " password
                                echo -e "\n"
                                giturl=`echo $giturl | sed "s/:\/\//:\/\/$username:$password@/g"`
                        ;;
                        t)
                                read -p "Enter your application token: " token
                                giturl=`echo $giturl | sed "s/:\/\//:\/\/$token@/g"`
                        ;;
                        q)
                                echo "Fine, exiting now."
                                exit 0
                        ;;
                        *)
                                echo -e "Wrong answer given. Try again."
                                gitrepocheck
                        ;;
                esac
        fi
}

createcloudconfig() {

        id_rsa=`ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -p$ansiblesshport ansible@$ansibleip "cat /etc/ansible/.ssh/id_rsa.pub | cut -d' ' -f1,2"`

echo "#cloud-config

hostname: $shortname

ssh_authorized_keys:
 - ssh-rsa $authorizedkey

coreos:
 etcd2:
   discovery: https://discovery.etcd.io/$discovery" > ./cloud-config
   echo '   advertise-client-urls: http://$private_ipv4:2379,http://$private_ipv4:4001
   initial-advertise-peer-urls: http://$private_ipv4:2380
   listen-client-urls: http://0.0.0.0:2379,http://0.0.0.0:4001
   listen-peer-urls: http://$private_ipv4:2380
 fleet:
   public-ip: $private_ipv4

users:
 - name: ansible
   groups:
     - sudo
     - docker
   ssh_authorized_keys:' >> ./cloud-config
echo "     - $id_rsa" >> ./cloud-config
}

defineandstart() {
	#[Instance:i-4bfe9cea]
	instanceid=`./ebs-start-instance.py | cut -d':' -f2 | sed 's/]//g'`
	sleep 5
	privip=`./get_instance_ip.py private $instanceid`
	echo "Priv IP: " $privip

}

ansiblecreate() {

        ssh -t -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -p$ansiblesshport ansible@$ansibleip "sudo /usr/local/bin/add_new_coreos_host.sh $privip ; ansible-playbook coreos-bootstrap.yml ; ansible-playbook coreos-fsdeploy.yml --extra-vars 'giturl=$giturl domain=$domainname'"

}

vmremove() {

        ./terminate-instance.py $instanceid
	echo "machine removed"
        exit 0

}

if [ -z "$1" ];
then
        echo "Usage: $0 [server_shortname] [domainname] [giturl]" 
        exit 1
elif [ "$1" == "remove" ];
then
        instanceid="$2"
        vmremove
fi

###     Things to be adjusted:  ###

# Authorized keys for user 'core'
authorizedkey="AAAAB3N.............QGiOc7qeblJEUqrMXPij50LcE0ya10cmdAw=="

# generate a new token for each unique cluster from https://discovery.etcd.io/new?size=3
discovery="e730e5....................91291"

# CoreOS release to be installed:
rel="stable"

# Virtual machine shortname
shortname="$1"

# Virtual machine domain:
domainname="$2"

# Machine short name (FQDN)
fqdn=`echo -e "$shortname.$domainname"`

ansibleip="[ipaddr.of.ansible.host]"
ansiblesshport="[ssh.daemon.listenport]"

if [ `echo $3 | grep git` ];
then
        giturl="$3"
else
	echo "You probably want to deploy an app from git repo. You'll need to specify doamin name for this."
	exit 1
fi

ansiblecheck
gitrepocheck
createcloudconfig
defineandstart
ansiblecreate
