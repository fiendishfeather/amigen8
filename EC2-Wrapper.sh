#!/bin/bash

dnf install -y lvm2

## Attach 2nd EBS

INSTANCE_ID=$(wget -q -O - http://169.254.169.254/latest/meta-data/instance-id)
AZONE_ID=$(wget -q -O - http://169.254.169.254/latest/meta-data/placement/availability-zone)
CREATED_VOLUME=$(aws ec2 create-volume --volume-type gp2 --size 50 --availability-zone $AZONE_ID)
CREATED_VOLUME_ID=$(jq -r '.VolumeId' <<< $CREATED_VOLUME)
sleep 10
aws ec2 attach-volume --volume-id $CREATED_VOLUME_ID --instance-id $INSTANCE_ID  --device /dev/sdf
sleep 10 # Adding to try and avoid a reboot?

####
# I may need to reboot here
###


## Run AMiGen Scripts

# This needs an update to add a /tmp volume I believe
./DiskSetup.sh -d /dev/nvme1n1 -v VolGroup00 -f xfs -B 500m -p "swap:swapVol:5,/home:homeVol:5,/var:varVol:5,/var/tmp:varTmpVol:5,/var/log:logVol:5,/var/log/audit:auditVol:5,/:rootVol:100%FREE"

./MkChrootTree.sh -d /dev/nvme1n1 -f xfs -p "swap:swapVol:5,/home:homeVol:5,/var:varVol:5,/var/tmp:varTmpVol:5,/var/log:logVol:5,/var/log/audit:auditVol:5,/:rootVol:100%FREE"

./OSpackages.sh

# -i flag is invalid?!
# We don't NEED to enable fips here, though it doesn't hurt
# If we mount /tmp to a new partition, we may need --no-tmpfs
# Depending on the nature of the LVM based, we may need to do some other finagling to get ImageBuilder to be able to reconnect,.
# since SSM and CLI will probably go missing
./PostBuild.sh -f xfs -i ec2-user


./Umount.sh


###
# Take Snapshot of CREATED_VOLUME_ID
# This could be mildly problematic if we need to reboot, though instance metadata may have what we need
###

#!/bin/bash
NEW_INSTANCE_ID=$(wget -q -O - http://169.254.169.254/latest/meta-data/instance-id)
NEW_VOLUME_ID=$(aws ec2 describe-volumes --filters Name=attachment.instance-id,Values=$NEW_INSTANCE_ID --query 'Volumes[1].VolumeId' --output text)
SNAPSHOT=$(aws ec2 create-snapshot --volume-id $NEW_VOLUME_ID --description "RHEL LVM based Snapshot")

SNAPSHOT_ID=$(jq -r '.SnapshotId' <<< $SNAPSHOT)
SNAPSHOT_STATUS="incomplete"
# While snapshot is NOT done
while [ $SNAPSHOT_STATUS != "completed" ]
do
    SNAPSHOT_DESCRIBE=$(aws ec2 describe-snapshots --snapshot-ids $SNAPSHOT_ID)
    SNAPSHOT_STATUS=$(jq -r '.Snapshots[0].State' <<< $SNAPSHOT_DESCRIBE)
    SNAPSHOT_PROGRESS=$(jq -r '.Snapshots[0].Progress' <<< $SNAPSHOT_DESCRIBE)
    echo "Snapshot progress: $SNAPSHOT_PROGRESS"
    sleep 5
done

echo "Snapshot Complete!"


###
# Detach the above volume
###
 aws ec2 detach-volume --volume-id $NEW_VOLUME_ID

###
# Replace the root volume
###

aws ec2 create-replace-root-volume-task --instance-id $NEW_INSTANCE_ID --snapshot-id $SNAPSHOT_ID --delete-replaced-root-volume true


aws ec2 create-replace-root-volume-task --instance-id i-004797c92ce1c87c9 --snapshot-id snap-0099ac8700e587640 --delete-replaced-root-volume true