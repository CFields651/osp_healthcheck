#!/bin/bash
minutes=$1
tests=$2
echo -e "This script assumes that: \n \
  1) It will be run from the undercloud as root\n \
  2) root can ssh to each overcloud controller\n \
  3) The Undercloud is not using UTC time and overcloud is. \n \
     If this is not the case see the comments in filterLog function\n \
  4) It will be run from the directory where tempest tests can be executed\n \
  5) Controler IP address variables have been set in the script"
read -p "Press Enter to continue..."
echo " "

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
. ~/overcloudrc


function filterLog {
  line=$1
  if echo "$line" | grep -q 'controller'; then echo "$line"
  else
    read rawLogTime <<< $(echo $line | grep -o ^"[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9] [0-9][0-9]:[0-9][0-9]:[0-9][0-9]") 
    read convertedLogTime <<< $(date +%s --date "$rawLogTime") 
    read adjustedCurrentTime <<< $(date -u +%s --date "- $minutes min")  #use this line if UTC is NOT used on the undercloud
    #read adjustedCurrentTime <<< $(date +%s --date "- $minutes min")    #use this line if UTC is used on the undercloud
    if [ $convertedLogTime -ge $adjustedCurrentTime ]; then echo $line; fi 
  fi
}


echo "### mysql status ###"
ssh heat-admin@$masterctrl sudo "mysql -e \"show variables like 'wsrep_cluster%'\""
ssh heat-admin@$masterctrl sudo "mysql  -e \"show status;\" | grep -E \"(wsrep_local_state_comment|wsrep_cluster_size|wsrep_ready|state_uuid|conf_id|cluster_status|wsrep_ready|wsrep_connected|local_state_comment|incoming_address|last_committed)\""
echo " "
echo "### rabbitmq status ###"
#keep this command around for deeper troubleshooting
#rabbitmqctl list_queues | awk '{ print $1,$2 }'| while read queue value; do if [ "$value" != "0" ]; then echo $queue $value;fi; don
ssh heat-admin@$masterctrl sudo rabbitmqctl cluster_status
echo " "
echo "Stopped Pacemaker resources"
ssh heat-admin@$masterctrl sudo "pcs status | grep Stopped -B 2"
echo " "
echo "Pacemaker failed actions"
ssh heat-admin@$masterctrl sudo "crm_mon  -1 | grep 'Failed Actions' -A 99"
echo " "
echo "### ceph status ###"
ssh heat-admin@$masterctrl sudo "ceph -s"
echo " "
ssh heat-admin@$masterctrl sudo "ceph osd tree"
echo " "
. /home/stack/overcloudrc
echo "### openstack catalog list ###"
openstack catalog list
echo " "
echo "### neutron agent-list ###"
neutron agent-list
echo " "
echo "### nova service-list ###"
nova service-list
echo " "
echo "### cinder service-list ###"
cinder service-list
echo " "
read -p "Press Enter to continue..."
echo "### api response ###"
for url in $(openstack catalog list -c Endpoints -f value | grep publicURL | awk -F'URL:' '{ print $2 }' | grep -o "http://.*:...."); do echo -e "\n\n$url"; curl --max-time 3 $url;done
echo " " 
echo "Show ERROR|WARN messages in service log for last $minutes minutes"
read -p "Press enter to continue..."
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
if [ "$tests" = "all" ]; then 
  echo "Show scenario issues in service logs that are type INFO"
  read -p "Press enter to continue..."
  echo -e "\n#########controller 0 Port not present##########"
  ssh heat-admin@$controller0 sudo 'grep "Port [0-9a-z].* not present in bridge" /var/log/neutron/openvswitch-agent.log' | while read line; do filterLog "$line"; done
  echo -e "\n#########controller 1 Port not present##########"
  ssh heat-admin@$controller1 sudo 'grep "Port [0-9a-z].* not present in bridge" /var/log/neutron/openvswitch-agent.log' | while read line; do filterLog "$line"; done
  echo -e "\n#########controller 2 Port not present##########"
  ssh heat-admin@$controller2 sudo 'grep "Port [0-9a-z].* not present in bridge" /var/log/neutron/openvswitch-agent.log' | while read line; do filterLog "$line"; done
  # additional scenarios
  # grep 'Failed to connect to libvirt' /var/log/nova/nova-compute.log; #this caused the 'Port not present error in openvswitch'
fi

if [ ! -e etc/tempest.conf ]; then 
  echo "etc/tempest.conf not found; won't try to run tests" 
else
  echo -e "a) Run tempest.test_network_basic_ops "
  echo -e "b) Run tempest.test_minimum_basic.py "
  echo -e "q) quit"
  read -p "What do you want to do: " answer

  if [ "$answer" == "a" ]; then
    su -c "ostestr --pdb tempest.scenario.test_network_basic_ops" stack
  elif [ "$answer" == "b" ]; then
    su -c "ostestr --pdb tempest.scenario.test_minimum_basic" stack
  fi
fi
