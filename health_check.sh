#!/bin/bash
echo -e "This script assumes that: \n \
  1) It will be run from the undercloud as root\n \
  2) root can ssh to each overcloud controller\n \
  3) The Undercloud is not using UTC time and overcloud is. \n \
     If this is not the case see the comments in filterLog function\n \
  4) It will be run from the directory where tempest tests can be executed\n \
  5) Controler IP address variables have been set in the script"
read -p "Press Enter to continue..."
echo " "

minutes=360 #go back 6 hours for ERROR|WARN messages
controller0=172.16.0.87
controller1=172.16.0.86
controller2=172.16.0.88

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
ssh root@$controller0 rabbitmqctl cluster_status
echo " "
ssh root@$controller0 pcs status | grep Stopped -B 2
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
echo -e "Run tempest.scenario.test_network_basic_ops - \nAre you in a directory where tempest tests can be run?" 
read -p "Press Enter to continue..."
if [ -e etc/tempest.conf ]; then  su -c "ostestr --pdb tempest.scenario.test_network_basic_ops" stack
else echo "etc/tempest.conf not found; won't try to run test" 
fi

