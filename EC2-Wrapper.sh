#!/bin/bash

## Attach 2nd EBS

INSTANCE_ID=$(wget -q -O - http://169.254.169.254/latest/meta-data/instance-id)
AZONE_ID=$(wget -q -O - http://169.254.169.254/latest/meta-data/placement/availability-zone)
CREATED_VOLUME=$(aws ec2 create-volume --volume-type gp2 --size 50 --availability-zone $AZONE_ID)
CREATED_VOLUME_ID=$(jq -r '.VolumeId' <<< $CREATED_VOLUME)
sleep 10
aws ec2 attach-volume --volume-id $CREATED_VOLUME_ID --instance-id $INSTANCE_ID  --device /dev/xvdb


## Run AMiGen Scripts

./DiskSetup.sh -d /dev/nvme1n1 -v VolGroup00 -f xfs -B 500m -p "swap:swapVol:5,/home:homeVol:5,/var:varVol:5,/var/tmp:varTmpVol:5,/var/log:logVol:5,/var/log/audit:auditVol:5,/:rootVol:100%FREE"

./MkChrootTree.sh -d /dev/nvme1n1 -f xfs -p "swap:swapVol:5,/home:homeVol:5,/var:varVol:5,/var/tmp:varTmpVol:5,/var/log:logVol:5,/var/log/audit:auditVol:5,/:rootVol:100%FREE"

./OSPackaages.sh

./PostBuild.sh -f xfs -i maintuser

./Umount.sh