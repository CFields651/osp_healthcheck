# osp_healthcheck
tools for estimating the health of my openstack cluster  

heath_check.sh is intended to be a quick troubleshooting tool  
that can spot high-level issues with your openstack cluster.  

It shows:  
 - galera replication health  
 - rabbitmq cluster health  
 - pcs resource status health  
 - ceph cluster health  
 - runs cli commands to display  
   - openstack baremetal node list  
   - openstack catalog  
   - neutron agent-list  
   - nova service-list  
 - shows api polling from haproxy stats  
 - checks for failed systemd services  
 - checks for updates  
 - checks if a reboot is necessary  
 - displays ERROR|WARN messages from service log for the last 60 minutes (configurable)  
 - runs the single most useful tempest test: tempest.scenario.test_network_basic_ops  
   
If tempest is not installed follow this guide:  
  https://access.redhat.com/documentation/en/red-hat-openstack-platform/9/paged/manual-installation-procedures/chapter-17-install-openstack-integration-test-suite  

The script does make some assumptions which are displayed when it runs so pay attention.    

