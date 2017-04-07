# osp_tools
tools for estimating the health of my openstack cluster  

heath_check.sh is intended to be a quick troubleshooting tool  
that can spot high-level issues with your openstack cluster.  

It shows:  
 - galera replication health  
 - rabbitmq cluster health  
 - pcs resource status health  
 - ceph cluster health  
 - runs cli commands to display  
   - openstack catalog  
   - neutron agent-list  
   - nova service-list  
 - displays ERROR|WARN messages from service log for the last 60 minutes (configurable)  
 - runs the single most useful tempest test: tempest.scenario.test_network_basic_ops  
   
If tempest is not installed follow this guide:  
  https://access.redhat.com/documentation/en/red-hat-openstack-platform/9/paged/manual-installation-procedures/chapter-17-install-openstack-integration-test-suite  

The script does make some assumptions:  
   1) It will be run from the undercloud as heat-admin
   2) heat-admin can ssh to each overcloud controller  
   3) The Undercloud is not using UTC time and overcloud is.   
      If this is not the case see the comments in filterLog function  
   4) It will be run from the directory where tempest tests can be executed  
   5) Controler IP address variables have been set in the script  

