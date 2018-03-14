#!/bin/bash
long=$1
minutes=$1
echo -e "This script assumes that: \n \
  1) It will be run from the undercloud as root\n \
  2) root can ssh to each overcloud controller\n \
  3) The Undercloud is not using UTC time and overcloud is. \n \
     If this is not the case see the comments in filterLog function\n \
  4) It will be run from the directory where tempest tests can be executed if tempest testing is desired\n \
  5) Overcloud node are in /etc/hosts/; if not: \n \
     openstack server list -c Name -c Networks -f value | awk '{ gsub(\"ctlplane=\",\"\"); print \$2\"  \"\$1; }'  >>/etc/hosts"
     #openstack server list -c Name -c Networks -f value | awk '{ gsub("ctlplane=",""); print $2"  "$1; }'  >>/etc/hosts
#read -p "Press enter to continue..."
echo " "

#check to see if we run all tests
if [ -z "$long" ]; then long=false; fi
#go back $minutes for ERROR|WARN messages
if [ -z "$minutes" ]; then minutes=60; fi

#get the path to the script
scriptpath="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

#beginning of code to detect controllers
. ~/stackrc
read controller0 controller1 controller2 <<< $(openstack server list -c Name -c Networks -f value | grep controller | sort | awk -F= '{ print $2 }')
masterctrl=$controller0
echo controller0=$controller0
echo controller1=$controller1
echo controller2=$controller2
echo " " 

function filterLog {
  line=$1
  if echo "$line" | grep -q 'log check'; then echo "$line"
  else
    read rawLogTime <<< $(echo $line | grep -o ^"[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9] [0-9][0-9]:[0-9][0-9]:[0-9][0-9]") 
    read convertedLogTime <<< $(date +%s --date "$rawLogTime") 
    #read adjustedCurrentTime <<< $(date -u +%s --date "- $minutes min")  #use this line if UTC is NOT used on the undercloud
    read adjustedCurrentTime <<< $(date +%s --date "- $minutes min")    #use this line if UTC is used on the undercloud
    if [ $convertedLogTime -ge $adjustedCurrentTime ]; then echo $line; fi 
  fi
}

if $long; then
  echo "### disk space check ###"
  echo "disk space on $(hostname)"
  sudo df -h | head -5

  . ~/stackrc
  for host in $(openstack server list -c Name -f value); do 
    echo disk space on $host
    ssh heat-admin@$host sudo df -h | head -5
    echo ' '
  done
fi

#echo "### mysql status ###"
#Keeping these in the code but too much detail so commented out
#ssh heat-admin@$masterctrl sudo "mysql -e \"show variables like 'wsrep_cluster%'\""
#ssh heat-admin@$masterctrl sudo "mysql  -e \"show status;\" | grep -E \"(wsrep_local_state_comment|wsrep_cluster_size|wsrep_ready|state_uuid|conf_id|cluster_status|wsrep_ready|wsrep_connected|local_state_comment|incoming_address|last_committed)\""
ssh heat-admin@$masterctrl sudo "mysql  -e \"show status;\" | grep -E \"(wsrep_local_state_comment|wsrep_cluster_size|wsrep_ready|cluster_status|wsrep_ready|wsrep_connected|incoming_address)\""
echo " "
echo "### mysql cluster check"
if ssh heat-admin@$masterctrl sudo docker ps | grep -q -o galera-bundle-docker.*; then 
  for controller in $controller0 $controller1 $controller2; do 
    read galera <<< $(ssh heat-admin@$controller sudo docker ps | grep -o galera-bundle-docker.*)
    ssh heat-admin@$controller sudo docker exec $galera clustercheck
  done
else
  for controller in $controller0 $controller1 $controller2; do 
    ssh heat-admin@$controller sudo clustercheck
  done
fi

echo " "

echo "### rabbitmq status ###"
#keep this command around for deeper troubleshooting
#rabbitmqctl list_queues | awk '{ print $1,$2 }'| while read queue value; do if [ "$value" != "0" ]; then echo $queue $value;fi; don
if ssh heat-admin@$masterctrl sudo docker ps | grep -q -o rabbitmq-bundle-docker.*; then 
  ssh heat-admin@$masterctrl sudo docker exec rabbitmq-bundle-docker-0 rabbitmqctl cluster_status
else
  ssh heat-admin@$masterctrl sudo rabbitmqctl cluster_status
fi

echo " "
echo "Stopped Pacemaker resources"
ssh heat-admin@$masterctrl sudo "pcs status | grep -e Stopped -e unmanaged -B 2"
echo " "
echo "Pacemaker failed actions"
ssh heat-admin@$masterctrl sudo "crm_mon  -1 | grep 'Failed Actions' -A 99"
echo " "
echo "Pacemaker maintenance mode"
ssh heat-admin@$masterctrl sudo "pcs property show maintenance-mode"
echo " "
echo "### ceph status ###"
ssh heat-admin@$masterctrl sudo "ceph -s"
echo " "
ssh heat-admin@$masterctrl sudo "ceph osd tree"
echo " "
. ~/stackrc
openstack baremetal node list
echo " "

echo "### systemd units status ###"
for host in $(openstack server list -c Name -f value); do 
  echo "systemd units not 'loaded active' on $host"
  ssh heat-admin@$host  sudo systemctl list-units "openstack*" "neutron*" "openvswitch*" --no-pager --no-legend | grep -v 'loaded active'
  echo ' '
done

echo "### haproxy status up/down ###"
read haproxy_creds <<< $(ssh heat-admin@overcloud-controller-0 sudo grep -o "admin:[0-9A-Za-z]*" /etc/haproxy/haproxy.cfg)
read haproxy_loc   <<< $(ssh heat-admin@overcloud-controller-0 "sudo  grep  'haproxy\.stats' /etc/haproxy/haproxy.cfg -A 1" | tail -1 | awk '{ print $2 }')
echo haproxy_loc=$haproxy_loc
curl -s -u "$haproxy_creds" "http://$haproxy_loc/\;csv" | egrep -vi "(frontend|backend)" | awk -F',' '{ print $1" "$2" "$18 }'
echo ' '

if $long; then 
  echo "### kernel errors since boot ###"
  for host in $(openstack server list -c Name -f value); do 
    echo "kernel errors on $host"
    ssh heat-admin@$host  sudo journalctl -p err -k -b
    echo ' '
  done 
fi

. /home/stack/overcloudrc
echo "###  network agent list ###"
openstack network agent list
echo " "
echo "### compute service list ###"
openstack compute service list
echo " "
echo "### volume service list ###"
openstack volume service list
echo " "

#removing api response because we're checking systemd for api services and haproxy stats for results - that's enough
#echo "### api response ###"
#. ~/overcloudrc
#for url in $(openstack catalog list -c Endpoints -f value | grep publicURL | awk -F'URL:' '{ print $2 }' | grep -o "http://.*:...."); do echo -e "\n\n$url"; curl -s --max-time 3 $url;done
#echo " " 

echo "### undercloud metadata response ###"
read metaport <<< $(sudo grep "^metadata_listen_port" /etc/nova/nova.conf  | awk -F= '{ print $2 }')
read metaip   <<< $(sudo grep "^metadata_listen=" /etc/nova/nova.conf  | awk -F= '{ print $2 }')
curl -s $metaip:$metaport
echo -e "\n" 

echo "### overcloud metadata response ###"
read metaport   <<< $(ssh heat-admin@$masterctrl sudo grep "^metadata_listen_port" /etc/nova/nova.conf  | awk -F= '{ print $2 }')
read metaip <<< $(ssh heat-admin@$masterctrl sudo grep "^metadata_listen=" /etc/nova/nova.conf  | awk -F= '{ print $2 }')
ssh heat-admin@$masterctrl sudo curl -s $metaip:$metaport
echo " " 

echo " "
echo "Show ERROR|WARN messages in service log for last $minutes minutes"
echo " "
scp $(echo $scriptpath)/read_logs.sh heat-admin@$controller0:/tmp/read_logs.sh >> /dev/null
ssh heat-admin@$controller0 sudo su -c /tmp/read_logs.sh | while read line; do filterLog "$line"; done
#ssh heat-admin@$controller0 'for service in nova neutron glance cinder ceph; do echo -e "\n######## controller0 $service #################"; tail -n 500 /var/log/$service/*.log | egrep "(ERROR|WARN)" | tail -3 ; done' | while read line; do filterLog "$line"; done
echo " "
scp $(echo $scriptpath)/read_logs.sh heat-admin@$controller1:/tmp/read_logs.sh >> /dev/null
ssh heat-admin@$controller1 sudo su -c /tmp/read_logs.sh | while read line; do filterLog "$line"; done
#ssh heat-admin@$controller1 'for service in nova neutron glance cinder ceph; do echo -e "\n######## controller1 $service #################"; tail -n 500 /var/log/$service/*.log | egrep "(ERROR|WARN)" | tail -3 ; done' | while read line; do filterLog "$line"; done
echo " "
scp $(echo $scriptpath)/read_logs.sh heat-admin@$controller2:/tmp/read_logs.sh >> /dev/null
ssh heat-admin@$controller2 sudo su -c /tmp/read_logs.sh | while read line; do filterLog "$line"; done
#ssh heat-admin@$controller2 'for service in nova neutron glance cinder ceph; do echo -e "\n######## controller2 $service #################"; tail -n 500 /var/log/$service/*.log | egrep "(ERROR|WARN)" | tail -3 ; done' | while read line; do filterLog "$line"; done
echo " "

if $long; then 
  echo "Show scenario issues in service logs that are type INFO"
#  read -p "Press enter to continue..."
  echo -e "\n#########controller 0 Port not present##########"
  ssh heat-admin@$controller0 sudo 'grep "Port [0-9a-z].* not present in bridge" /var/log/neutron/openvswitch-agent.log' | while read line; do filterLog "$line"; done
  echo -e "\n#########controller 1 Port not present##########"
  ssh heat-admin@$controller1 sudo 'grep "Port [0-9a-z].* not present in bridge" /var/log/neutron/openvswitch-agent.log' | while read line; do filterLog "$line"; done
  echo -e "\n#########controller 2 Port not present##########"
  ssh heat-admin@$controller2 sudo 'grep "Port [0-9a-z].* not present in bridge" /var/log/neutron/openvswitch-agent.log' | while read line; do filterLog "$line"; done
fi

if $long; then
  echo "### mongodb status ###"
  read mongoip <<< $(ssh heat-admin@$controller0 sudo grep 'mongodb://' /etc/ceilometer/ceilometer.conf| grep -Eo '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' | head -n1)
  ssh heat-admin@$controller0 "sudo mongo $mongoip:27017/ceilometer --eval \"printjson(rs.status())\"" | grep -e name -e state -e optime\" -e lastHeartbeatRecv
  echo ' '
fi

if $long; then
  . ~/stackrc
  echo "### update status ###"
  read osprepo <<< $(sudo subscription-manager repos --list-enabled | grep -o  'rhel-7-server-openstack-..-rpms')
  for host in $(openstack server list -c Name -f value); do 
    echo rpms to update in OSP repo for $host
    ssh heat-admin@$host sudo yum check-updates --disablerepo='*' --enablerepo="$osprepo" | wc -l
    echo ' '
  done
fi

if $long; then
  echo "### restart needed status ###"
  for host in $(openstack server list -c Name -f value); do 
    echo restart status for $host
    ssh heat-admin@$host sudo  needs-restarting  -r ; echo $?
    echo ' '
  done
fi

if [ ! -e etc/tempest.conf ]; then 
  echo "etc/tempest.conf not found; won't try to run tests" 
else
  if $long; then 
    sudo su -c "ostestr --pdb tempest.scenario.test_minimum_basic" 
  fi
fi
