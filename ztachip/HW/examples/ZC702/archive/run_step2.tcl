# Close existing project (if open) and delete broken project folder, then recreate.
catch {close_project}
file delete -force /home/eslam-elshokafy/Desktop/AIDAChip_Workshop_01/ztachip/HW/examples/ZC702/ztachip_zc702
cd /home/eslam-elshokafy/Desktop/AIDAChip_Workshop_01/ztachip/HW/examples/ZC702
source create_project_zc702.tcl -notrace
