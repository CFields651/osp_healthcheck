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

controller0=172.16.0.21
controller1=172.16.0.26
controller2=172.16.0.28

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
ssh root@$controller0 "mysql -e \"show variables like 'wsrep_cluster%'\""
ssh root@$controller0 "mysql  -e \"show status;\" | grep -E \"(wsrep_local_state_comment|wsrep_cluster_size|wsrep_ready|state_uuid|conf_id|cluster_status|wsrep_ready|wsrep_connected|local_state_comment|incoming_address|last_committed)\""
echo " "
echo "### rabbitmq status ###"
#keep this command around for deeper troubleshooting
#rabbitmqctl list_queues | awk '{ print $1,$2 }'| while read queue value; do if [ "$value" != "0" ]; then echo $queue $value;fi; don
ssh root@$controller0 rabbitmqctl cluster_status
echo " "
echo "Stopped Pacemaker resources"
ssh root@$controller0 pcs status | grep Stopped -B 2
echo " "
echo "Pacemaker failed actions"
ssh root@$controller0 crm_mon  -1 | grep 'Failed Actions' -A 99
echo " "
echo "### ceph status ###"
ssh root@$controller0 ceph -s 
echo " "
ssh root@$controller0 ceph osd tree 
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
echo "Show ERROR|WARN messages in service log for last $minutes minutes"
read -p "Press enter to continue..."
echo " "
ssh root@$controller0 'for service in nova neutron glance cinder ceph; do echo -e "\n######## controller0 $service #################"; tail -n 500 /var/log/$service/*.log | egrep "(ERROR|WARN)" | tail -3 ; done' | while read line; do filterLog "$line"; done
echo " "
ssh root@$controller1 'for service in nova neutron glance cinder ceph; do echo -e "\n######## controller1 $service #################"; tail -n 500 /var/log/$service/*.log | egrep "(ERROR|WARN)" | tail -3 ; done' | while read line; do filterLog "$line"; done
echo " "
ssh root@$controller2 'for service in nova neutron glance cinder ceph; do echo -e "\n######## controller2 $service #################"; tail -n 500 /var/log/$service/*.log | egrep "(ERROR|WARN)" | tail -3 ; done' | while read line; do filterLog "$line"; done
echo " "
if [ "$tests" = "all" ]; then 
  echo "Show scenario issues in service logs that are type INFO"
  read -p "Press enter to continue..."
  echo -e "\n#########controller 0 Port not present##########"
  ssh root@$controller0 'grep "Port [0-9a-z].* not present in bridge" /var/log/neutron/openvswitch-agent.log' | while read line; do filterLog "$line"; done
  echo -e "\n#########controller 1 Port not present##########"
  ssh root@$controller1 'grep "Port [0-9a-z].* not present in bridge" /var/log/neutron/openvswitch-agent.log' | while read line; do filterLog "$line"; done
  echo -e "\n#########controller 2 Port not present##########"
  ssh root@$controller2 'grep "Port [0-9a-z].* not present in bridge" /var/log/neutron/openvswitch-agent.log' | while read line; do filterLog "$line"; done
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
