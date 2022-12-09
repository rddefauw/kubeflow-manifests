import argparse
import boto3
import subprocess
import json
import yaml
import time

from importlib.metadata import metadata
from e2e.fixtures.cluster import create_iam_service_account
from e2e.utils.config import configure_env_file
from e2e.utils.utils import (
    get_ec2_client,
    get_rds_client,
    get_eks_client,
    get_s3_client,
    get_iam_client,
    get_datasync_client,
    kubectl_apply,
    print_banner,
    write_yaml_file,
    load_yaml_file,
    wait_for,
    WaitForCircuitBreakerError,
    write_env_to_yaml
)

from shutil import which

INSTALLATION_PATH_FILE_RDS_S3 = "./resources/installation_config/rds-s3.yaml"
INSTALLATION_PATH_FILE_RDS_ONLY = "./resources/installation_config/rds-only.yaml"
INSTALLATION_PATH_FILE_S3_ONLY = "./resources/installation_config/s3-only.yaml"
path_dic_rds_s3 = load_yaml_file(INSTALLATION_PATH_FILE_RDS_S3)
path_dic_rds_only = load_yaml_file(INSTALLATION_PATH_FILE_RDS_ONLY)
path_dic_s3_only = load_yaml_file(INSTALLATION_PATH_FILE_S3_ONLY)

def main():
    verify_prerequisites()
    s3_client = get_s3_client(
        region=CLUSTER_REGION,
    )
    datasync_client = get_datasync_client( region=CLUSTER_REGION )
    iam_client = get_iam_client( region=CLUSTER_REGION )
    setup_s3(s3_client, datasync_client, iam_client)
    rds_client = get_rds_client(CLUSTER_REGION)
    eks_client = get_eks_client(CLUSTER_REGION)
    ec2_client = get_ec2_client(CLUSTER_REGION)
    setup_rds(rds_client, eks_client, ec2_client)
    setup_cluster_secrets()
    setup_kubeflow_pipeline()
    print_banner("RDS S3 Setup Complete")
    script_metadata = [
        f"bucket_name={S3_BUCKET_NAME_BLUE}",
        f"db_instance_name={DB_INSTANCE_NAME_BLUE}",
        f"db_subnet_group_name={DB_SUBNET_GROUP_NAME_BLUE}",
        f"s3_secret_name={S3_SECRET_NAME}",
        f"rds_secret_name={RDS_SECRET_NAME}",
    ]
    script_metadata = {}
    script_metadata["S3"] = {"bucket": S3_BUCKET_NAME_BLUE, "secretName": S3_SECRET_NAME}
    script_metadata["RDS"] = {
        "instanceName": DB_INSTANCE_NAME_BLUE,
        "secretName": RDS_SECRET_NAME,
        "subnetGroupName": DB_SUBNET_GROUP_NAME_BLUE,
    }
    script_metadata["CLUSTER"] = {"region": CLUSTER_REGION, "name": CLUSTER_NAME_BLUE}
    write_yaml_file(
        yaml_content=script_metadata, file_path="utils/rds-s3/metadata.yaml"
    )


def verify_prerequisites():
    print_banner("Prerequisites Verification")
    verify_eksctl_is_installed()
    verify_kubectl_is_installed()


def verify_eksctl_is_installed():
    print("Verifying eksctl is installed...")

    is_prerequisite_met = which("eksctl") is not None

    if is_prerequisite_met:
        print("eksctl found!")
    else:
        raise Exception(
            "Prerequisite not met : eksctl could not be found, make sure it is installed or in your PATH!"
        )


def verify_kubectl_is_installed():
    print("Verifying kubectl is installed...")

    is_prerequisite_met = which("kubectl") is not None

    if is_prerequisite_met:
        print("kubectl found!")
    else:
        raise Exception(
            "Prerequisite not met : kubectl could not be found, make sure it is installed or in your PATH!"
        )


def setup_s3(s3_client, datasync_client, iam_client):
    print_banner("S3 Setup")
    setup_s3_bucket(s3_client)
    clone_s3_bucket(datasync_client, iam_client)

def does_datasync_role_exist(iam_client):
    try:
        role = iam_client.get_role(RoleName=DATASYNC_ROLE_NAME)
        return role["Role"]["Arn"]
    except iam_client.exceptions.NoSuchEntityException:
        return None

def create_datasync_role(iam_client, src_bucket_arn, tgt_bucket_arn):
    datasync_iam_trust = {
        "Version": "2012-10-17",
        "Statement": [
            {
                "Effect": "Allow",
                "Principal": {
                    "Service": "datasync.amazonaws.com"
                },
                "Action": "sts:AssumeRole"
            }
        ]
    }
    response = iam_client.create_role(
        RoleName=DATASYNC_ROLE_NAME,
        AssumeRolePolicyDocument=json.dumps(datasync_iam_trust)
    )
    datasync_role_arn = response['Role']['Arn']
    datasync_s3_access = {
        "Version": "2012-10-17",
        "Statement": [
            {
                "Action": [
                    "s3:GetBucketLocation",
                    "s3:ListBucket",
                    "s3:ListBucketMultipartUploads"
                ],
                "Effect": "Allow",
                "Resource": [
                    src_bucket_arn,
                    tgt_bucket_arn
                ]
            },
            {
                "Action": [
                    "s3:AbortMultipartUpload",
                    "s3:DeleteObject",
                    "s3:GetObject",
                    "s3:ListMultipartUploadParts",
                    "s3:GetObjectTagging",
                    "s3:PutObjectTagging",
                    "s3:PutObject"
                ],
                "Effect": "Allow",
                "Resource": [
                    f"{src_bucket_arn}/*",
                    f"{tgt_bucket_arn}/*"
                ]
            }
        ]
    }
    response = iam_client.put_role_policy(
        RoleName=DATASYNC_ROLE_NAME,
        PolicyName='datasync_s3_kubeflow',
        PolicyDocument=json.dumps(datasync_s3_access)
    )
    return datasync_role_arn

def clone_s3_bucket(datasync_client, iam_client):
    print(f"Cloning S3 objects from {S3_BUCKET_NAME_GREEN} into {S3_BUCKET_NAME_BLUE}...")

    src_bucket_arn = f"arn:aws:s3:::{S3_BUCKET_NAME_GREEN}"
    tgt_bucket_arn = f"arn:aws:s3:::{S3_BUCKET_NAME_BLUE}"
    datasync_role_arn = does_datasync_role_exist(iam_client)
    if datasync_role_arn is None:
        datasync_role_arn = create_datasync_role(iam_client, src_bucket_arn, tgt_bucket_arn)
        print("Waiting for new IAM role to propagate")
        time.sleep(10)
    else:
        print(f"Skipping DataSync role creation, role '{DATASYNC_ROLE_NAME}' already exists!")
    
    response = datasync_client.create_location_s3(
        Subdirectory='',
        S3StorageClass='STANDARD',
        S3BucketArn=src_bucket_arn,
        S3Config={
            'BucketAccessRoleArn': datasync_role_arn
        }
    )
    src_location = response['LocationArn']
    response = datasync_client.create_location_s3(
        Subdirectory='',
        S3StorageClass='STANDARD',
        S3BucketArn=tgt_bucket_arn,
        S3Config={
            'BucketAccessRoleArn': datasync_role_arn
        }
    )
    tgt_location = response['LocationArn']

    ctime = int(time.time())
    response = datasync_client.create_task(
        SourceLocationArn=src_location,
        DestinationLocationArn=tgt_location,
        Name=f"kubeflow-sync-{ctime}",
        Options={
            'VerifyMode': 'POINT_IN_TIME_CONSISTENT',
            'OverwriteMode': 'ALWAYS',
            'Atime': 'BEST_EFFORT',
            'Mtime': 'PRESERVE',
            'PreserveDeletedFiles': 'REMOVE',
            'TransferMode': 'CHANGED'
        }
    )
    task_arn = response['TaskArn']

    print("Launching DataSync task...")
    response = datasync_client.start_task_execution(
        TaskArn=task_arn
    )
    task_exec_arn = response['TaskExecutionArn']

    task_status = 'QUEUED'
    while task_status not in ['SUCCESS', 'ERROR']:
        response = datasync_client.describe_task_execution(
            TaskExecutionArn=task_exec_arn
        )
        task_status = response['Status']
        if task_status == 'ERROR':
            raise Exception(f"S3 cloning task failed: {task_exec_arn}")
        print(f"Transfer task status: {task_status}")
        print(f"Files to transfer: {response['EstimatedFilesToTransfer']}")
        print(f"Bytes to transfer: {response['EstimatedBytesToTransfer']}")
        time.sleep(30)

    print("S3 objects cloned!")


def setup_s3_bucket(s3_client):
    if not does_bucket_exist(s3_client):
        create_s3_bucket(s3_client)
    else:
        print(f"Skipping S3 bucket creation, bucket '{S3_BUCKET_NAME_BLUE}' already exists!")


def does_bucket_exist(s3_client):
    buckets = s3_client.list_buckets()["Buckets"]
    return any(bucket["Name"] == S3_BUCKET_NAME_BLUE for bucket in buckets)


def create_s3_bucket(s3_client):
    print("Creating S3 bucket...")

    args = {"ACL": "private", "Bucket": S3_BUCKET_NAME_BLUE}
    # CreateBucketConfiguration is necessary to provide LocationConstraint unless using default region of us-east-1
    if CLUSTER_REGION != "us-east-1":
        args["CreateBucketConfiguration"] = {"LocationConstraint": CLUSTER_REGION}

    s3_client.create_bucket(**args)
    print("S3 bucket created!")

def snapshot_db(rds_client):
    ctime = int(time.time())
    snapshot_id = f"kf-rds-snap-{ctime}"
    response = rds_client.create_db_snapshot(
        DBSnapshotIdentifier=snapshot_id,
        DBInstanceIdentifier=DB_INSTANCE_NAME_GREEN
    )

    snapshot_status = 'creating'
    while snapshot_status != 'available':
        response = rds_client.describe_db_snapshots(
            DBInstanceIdentifier=DB_INSTANCE_NAME_GREEN,
            DBSnapshotIdentifier=snapshot_id
        )
        snapshot_status = response['DBSnapshots'][0]['Status']

    print("Database snapshot created!")
    return snapshot_id

def setup_rds(rds_client, eks_client, ec2_client):
    print_banner("RDS Setup")

    if not does_database_exist(rds_client):
        print("Creating snapshot...")
        snapshot_id = snapshot_db(rds_client) 

        setup_db_instance(
            rds_client, eks_client, ec2_client, snapshot_id
        )

    else:
        print(f"Skipping RDS setup, DB instance '{DB_INSTANCE_NAME_BLUE}' already exists!")


def does_database_exist(rds_client):
    matching_databases = rds_client.describe_db_instances(
        Filters=[{"Name": "db-instance-id", "Values": [DB_INSTANCE_NAME_BLUE]}]
    )["DBInstances"]

    return len(matching_databases) > 0


def setup_db_instance(rds_client, eks_client, ec2_client, snapshot_id):
    setup_db_subnet_group(rds_client, eks_client, ec2_client)
    create_db_instance(
        rds_client, eks_client, ec2_client, snapshot_id
    )


def setup_db_subnet_group(rds_client, eks_client, ec2_client):
    if not does_db_subnet_group_exist(rds_client):
        create_db_subnet_group(rds_client, eks_client, ec2_client)
    else:
        print(
            f"Skipping DB subnet group creation, DB subnet group '{DB_SUBNET_GROUP_NAME_BLUE}' already exists!"
        )


def does_db_subnet_group_exist(rds_client):
    try:
        rds_client.describe_db_subnet_groups(DBSubnetGroupName=DB_SUBNET_GROUP_NAME_BLUE)
        return True
    except rds_client.exceptions.DBSubnetGroupNotFoundFault:
        return False


def create_db_subnet_group(rds_client, eks_client, ec2_client):
    print("Creating DB subnet group...")

    subnet_ids = get_cluster_private_subnet_ids(eks_client, ec2_client)

    rds_client.create_db_subnet_group(
        DBSubnetGroupName=DB_SUBNET_GROUP_NAME_BLUE,
        DBSubnetGroupDescription="Subnet group for Kubeflow metadata db",
        SubnetIds=subnet_ids,
    )

    print("DB subnet group created!")


def get_cluster_private_subnet_ids(eks_client, ec2_client):
    subnet_ids = eks_client.describe_cluster(name=CLUSTER_NAME_BLUE)["cluster"][
        "resourcesVpcConfig"
    ]["subnetIds"]

    # TODO handle pagination
    subnets = ec2_client.describe_subnets(SubnetIds=subnet_ids)["Subnets"]
    private_subnets = []
    for subnet in subnets:
        for tags in subnet["Tags"]:
            # eksctl generated clusters       
            if "SubnetPrivate" in tags["Value"]:
                private_subnets.append(subnet)
            # cdk generated clusters
            if "aws-cdk:subnet-type" in tags["Key"]:
                if "Private" in tags["Value"]:
                    private_subnets.append(subnet)

    def get_subnet_id(subnet):
        return subnet["SubnetId"]

    return list(map(get_subnet_id, private_subnets))


def create_db_instance(rds_client, eks_client, ec2_client, snapshot_id):
    print("Creating DB instance...")

    vpc_security_group_id = get_vpc_security_group_id(eks_client)

    rds_client.restore_db_instance_from_db_snapshot(
        DBInstanceIdentifier=DB_INSTANCE_NAME_BLUE,
        DBSnapshotIdentifier=snapshot_id,
        DBInstanceClass=DB_INSTANCE_TYPE,
        MultiAZ=True,
        PubliclyAccessible=False,
        Engine="mysql",
        StorageType=DB_STORAGE_TYPE,
        DBSubnetGroupName=DB_SUBNET_GROUP_NAME_BLUE,
        DeletionProtection=True,
        VpcSecurityGroupIds=[vpc_security_group_id]
    )

    print("DB instance created!")

    wait_for_rds_db_instance_to_become_available(rds_client)


def get_vpc_security_group_id(eks_client):
    security_group_id = eks_client.describe_cluster(name=CLUSTER_NAME_BLUE)["cluster"][
        "resourcesVpcConfig"
    ]["clusterSecurityGroupId"]

    # Note : We only need to return 1 security group because we use the shared node security group, this fixes https://github.com/awslabs/kubeflow-manifests/issues/137
    return security_group_id


def wait_for_rds_db_instance_to_become_available(rds_client):

    print("Waiting for RDS DB instance to become available...")

    def callback():
        status = rds_client.describe_db_instances(
            DBInstanceIdentifier=DB_INSTANCE_NAME_BLUE
        )["DBInstances"][0]["DBInstanceStatus"]
        if status == "failed":
            raise WaitForCircuitBreakerError(
                "An unexpected error occurred while waiting for the RDS DB instance to become available!"
            )
        assert status == "available"
        if status == "available":
            print("RDS DB instance is available!")

    wait_for(callback, 1500)

def get_db_instance_info():
    rds_client = get_rds_client(CLUSTER_REGION)

    return rds_client.describe_db_instances(DBInstanceIdentifier=DB_INSTANCE_NAME_BLUE)[
        "DBInstances"
    ][0]


def setup_cluster_secrets():
    print_banner("Cluster Secrets Setup")

    setup_iam_service_account()
    setup_secrets_provider()


def setup_iam_service_account():
    create_secrets_iam_service_account()


def create_secrets_iam_service_account():
    print("Creating secrets IAM service account...")
    iam_policies = [
        "arn:aws:iam::aws:policy/AmazonSSMReadOnlyAccess",
        "arn:aws:iam::aws:policy/SecretsManagerReadWrite",
    ]

    create_iam_service_account(
        service_account_name="kubeflow-secrets-manager-sa",
        namespace="kubeflow",
        cluster_name=CLUSTER_NAME_BLUE,
        region=CLUSTER_REGION,
        iam_policy_arns=iam_policies,
    )

    print("Secrets IAM service account created!")


def setup_secrets_provider():
    print("Installing secrets provider...")
    install_secrets_store_csi_driver()
    print("Secrets provider install done!")


def install_secrets_store_csi_driver():
    kubectl_apply(
        "https://raw.githubusercontent.com/kubernetes-sigs/secrets-store-csi-driver/v1.0.0/deploy/rbac-secretproviderclass.yaml"
    )
    kubectl_apply(
        "https://raw.githubusercontent.com/kubernetes-sigs/secrets-store-csi-driver/v1.0.0/deploy/csidriver.yaml"
    )
    kubectl_apply(
        "https://raw.githubusercontent.com/kubernetes-sigs/secrets-store-csi-driver/v1.0.0/deploy/secrets-store.csi.x-k8s.io_secretproviderclasses.yaml"
    )
    kubectl_apply(
        "https://raw.githubusercontent.com/kubernetes-sigs/secrets-store-csi-driver/v1.0.0/deploy/secrets-store.csi.x-k8s.io_secretproviderclasspodstatuses.yaml"
    )
    kubectl_apply(
        "https://raw.githubusercontent.com/kubernetes-sigs/secrets-store-csi-driver/v1.0.0/deploy/secrets-store-csi-driver.yaml"
    )
    kubectl_apply(
        "https://raw.githubusercontent.com/kubernetes-sigs/secrets-store-csi-driver/v1.0.0/deploy/rbac-secretprovidersyncing.yaml"
    )
    kubectl_apply(
        "https://raw.githubusercontent.com/aws/secrets-store-csi-driver-provider-aws/main/deployment/aws-provider-installer.yaml"
    )

#TO DO: decouple kustomize params.env and helm values.yaml write up in future
def setup_kubeflow_pipeline():
    print("Setting up Kubeflow Pipeline...")

    print("Retrieving DB instance info...")
    db_instance_info = get_db_instance_info()
    
    #helm
    #pipelines helm path
    pipeline_rds_s3_helm_path = path_dic_rds_s3["kubeflow-pipelines"]["installation_options"]["helm"]["paths"]
    pipeline_rds_only_helm_path = path_dic_rds_only["kubeflow-pipelines"]["installation_options"]["helm"]["paths"]
    pipeline_s3_only_helm_path = path_dic_s3_only["kubeflow-pipelines"]["installation_options"]["helm"]["paths"]
    
    #secrets-manager helm path
    secrets_manager_rds_s3_helm_path = path_dic_rds_s3["aws-secrets-manager"]["installation_options"]["helm"]["paths"]
    secrets_manager_rds_only_helm_path = path_dic_rds_only["aws-secrets-manager"]["installation_options"]["helm"]["paths"]
    secrets_manager_s3_only_helm_path = path_dic_s3_only["aws-secrets-manager"]["installation_options"]["helm"]["paths"]

    #pipelines values file
    pipeline_rds_s3_values_file = f"{pipeline_rds_s3_helm_path}/values.yaml" 
    pipeline_rds_only_values_file = f"{pipeline_rds_only_helm_path}/values.yaml" 
    pipeline_s3_only_values_file = f"{pipeline_s3_only_helm_path}/values.yaml" 
    
    #secrets-manager values file
    secrets_manager_rds_s3_values_file = f"{secrets_manager_rds_s3_helm_path}/values.yaml" 
    secrets_manager_rds_only_values_file = f"{secrets_manager_rds_only_helm_path}/values.yaml" 
    secrets_manager_s3_only_values_file = f"{secrets_manager_s3_only_helm_path}/values.yaml" 
    
    #kustomize params
    pipeline_rds_params_env_file = "../../awsconfigs/apps/pipeline/rds/params.env"
    pipeline_rds_secret_provider_class_file = (
        "../../awsconfigs/common/aws-secrets-manager/rds/secret-provider.yaml"
    )

    rds_params = {
        "dbHost": db_instance_info["Endpoint"]["Address"],
        "mlmdDb": "metadb",
    }
    rds_secret_params = {
        "secretName": RDS_SECRET_NAME
    }
    edit_pipeline_params_env_file(rds_params, pipeline_rds_params_env_file)
    write_env_to_yaml(rds_params, pipeline_rds_s3_values_file, module="rds")
    write_env_to_yaml(rds_params, pipeline_rds_only_values_file, module="rds")
    write_env_to_yaml(rds_secret_params, secrets_manager_rds_s3_values_file, module="rds")
    write_env_to_yaml(rds_secret_params, secrets_manager_rds_only_values_file, module="rds")
    update_secret_provider_class(
        pipeline_rds_secret_provider_class_file, RDS_SECRET_NAME
    )

    pipeline_s3_params_env_file = "../../awsconfigs/apps/pipeline/s3/params.env"
    pipeline_s3_secret_provider_class_file = (
        "../../awsconfigs/common/aws-secrets-manager/s3/secret-provider.yaml"
    )

    s3_params = {
        "bucketName": S3_BUCKET_NAME_BLUE,
        "minioServiceRegion": CLUSTER_REGION,
        "minioServiceHost": "s3.amazonaws.com",
    }
    s3_secret_params = {
        "secretName": S3_SECRET_NAME
    }
    edit_pipeline_params_env_file(s3_params, pipeline_s3_params_env_file)
    write_env_to_yaml(s3_params, pipeline_rds_s3_values_file, module="s3")
    write_env_to_yaml(s3_params, pipeline_s3_only_values_file, module="s3")
    write_env_to_yaml(s3_secret_params, secrets_manager_rds_s3_values_file, module="s3")
    write_env_to_yaml(s3_secret_params, secrets_manager_s3_only_values_file, module="s3")
    update_secret_provider_class(pipeline_s3_secret_provider_class_file, S3_SECRET_NAME)

    print("Kubeflow pipeline setup done!")


def edit_pipeline_params_env_file(params_env, pipeline_params_env_file):
    print(f"Editing {pipeline_params_env_file} with appropriate values...")

    configure_env_file(pipeline_params_env_file, params_env)


def update_secret_provider_class(secret_provider_class_file, secret_name):
    secret_provider = load_yaml_file(secret_provider_class_file)

    secret_provider_objects = yaml.safe_load(
        secret_provider["spec"]["parameters"]["objects"]
    )
    secret_provider_objects[0]["objectName"] = secret_name
    secret_provider["spec"]["parameters"]["objects"] = yaml.dump(
        secret_provider_objects
    )

    write_yaml_file(secret_provider, secret_provider_class_file)


parser = argparse.ArgumentParser()
parser.add_argument(
    "--region",
    type=str,
    metavar="CLUSTER_REGION",
    help="Your cluster region code (eg: us-east-2)",
    required=True,
)
parser.add_argument(
    "--bucket_green",
    type=str,
    metavar="S3_BUCKET_GREEN",
    help="Your green S3 bucket name (eg: mybucket)",
    required=True,
)
DATASYNC_ROLE_NAME_DEFAULT = "datasyncrolekubeflow"
parser.add_argument(
    "--datasync_role_name",
    type=str,
    metavar="DATASYNC_ROLE_NAME",
    default=DATASYNC_ROLE_NAME_DEFAULT,
    help="Your DataSync IAM role name",
    required=False,
)
parser.add_argument(
    "--cluster_blue",
    type=str,
    metavar="CLUSTER_NAME_BLUE",
    help="Your blue cluster name (eg: mycluster-1)",
    required=True,
)
parser.add_argument(
    "--bucket_blue",
    type=str,
    metavar="S3_BUCKET_BLUE",
    help="Your blue S3 bucket name (eg: mybucket)",
    required=True,
)
parser.add_argument(
    "--db_instance_name_green",
    type=str,
    help=f"Unique identifier for the green RDS database instance.",
    required=True,
)
DB_INSTANCE_NAME_DEFAULT_BLUE = "kubeflow-db-blue"
parser.add_argument(
    "--db_instance_name_blue",
    type=str,
    default=DB_INSTANCE_NAME_DEFAULT_BLUE,
    help=f"Unique identifier for the blue RDS database instance. Default is set to {DB_INSTANCE_NAME_DEFAULT_BLUE}",
    required=False,
)
DB_INSTANCE_TYPE_DEFAULT = "db.m5.large"
parser.add_argument(
    "--db_instance_type",
    type=str,
    default=DB_INSTANCE_TYPE_DEFAULT,
    help=f"Default is set to {DB_INSTANCE_TYPE_DEFAULT}",
    required=False,
)
DB_STORAGE_TYPE_DEFAULT = "gp2"
parser.add_argument(
    "--db_storage_type",
    type=str,
    default=DB_STORAGE_TYPE_DEFAULT,
    help=f"Default is set to {DB_STORAGE_TYPE_DEFAULT}",
    required=False,
)
DB_SUBNET_GROUP_NAME_DEFAULT = "kubeflow-db-subnet-group-blue"
parser.add_argument(
    "--db_subnet_group_name_blue",
    type=str,
    default=DB_SUBNET_GROUP_NAME_DEFAULT,
    help=f"Default is set to {DB_SUBNET_GROUP_NAME_DEFAULT}",
    required=False,
)
RDS_SECRET_NAME = "rds-secret"
parser.add_argument(
    "--rds_secret_name",
    type=str,
    default=RDS_SECRET_NAME,
    help=f"Name of the secret containing RDS related credentials. Default is set to {RDS_SECRET_NAME}",
    required=False,
)
S3_SECRET_NAME = "s3-secret"
parser.add_argument(
    "--s3_secret_name",
    type=str,
    default=S3_SECRET_NAME,
    help=f"Name of the secret containing S3 related credentials. Default is set to {S3_SECRET_NAME}",
    required=False,
)

args, _ = parser.parse_known_args()

if __name__ == "__main__":
    CLUSTER_REGION = args.region
    CLUSTER_NAME_BLUE = args.cluster_blue
    S3_BUCKET_NAME_BLUE = args.bucket_blue
    S3_BUCKET_NAME_GREEN = args.bucket_green
    DB_INSTANCE_NAME_BLUE = args.db_instance_name_blue
    DB_INSTANCE_NAME_GREEN = args.db_instance_name_green
    DB_INSTANCE_TYPE = args.db_instance_type
    DB_STORAGE_TYPE = args.db_storage_type
    DB_SUBNET_GROUP_NAME_BLUE = args.db_subnet_group_name_blue
    RDS_SECRET_NAME = args.rds_secret_name
    S3_SECRET_NAME = args.s3_secret_name
    DATASYNC_ROLE_NAME = args.datasync_role_name

    main()
