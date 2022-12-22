#!/bin/bash

VAULT=`terraform output -raw backup_vault`
ROLE_ARN=`terraform output -raw backup_role_arn`
EFS_ARN=`terraform output -raw efs_fs_arn`
S3_ARN=`terraform output -raw s3_bucket_arn`
RDS_ARN=`terraform output -raw rds_arn`

echo "Starting EFS backup job"
EFS_JOB=`aws backup start-backup-job --backup-vault-name $VAULT --iam-role-arn $ROLE_ARN --resource-arn $EFS_ARN | jq -r '.BackupJobId'`

echo "Starting S3 backup job"
S3_JOB=`aws backup start-backup-job --backup-vault-name $VAULT --iam-role-arn $ROLE_ARN --resource-arn $S3_ARN | jq -r '.BackupJobId'`

echo "Starting RDS backup job"
RDS_JOB=`aws backup start-backup-job --backup-vault-name $VAULT --iam-role-arn $ROLE_ARN --resource-arn $RDS_ARN | jq -r '.BackupJobId'`

echo "Checking job states..."
for JOB_ID in $EFS_JOB $S3_JOB $RDS_JOB
do
    JOB_STATE='PENDING'
    while [[ "$JOB_STATE" != "ABORTED" ]] && [[ "$JOB_STATE" != "COMPLETED" ]] && [[ "$JOB_STATE" != "FAILED" ]]
    do
        JOB_STATE=`aws backup describe-backup-job --backup-job-id $JOB_ID | jq -r '.State'`
        echo $JOB_STATE
        sleep 30
    done
done