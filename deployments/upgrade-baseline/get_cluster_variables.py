import argparse
import boto3
import json

def main():
    efs_client = boto3.client('efs', region_name=CLUSTER_REGION)
    rds_client = boto3.client('rds', region_name=CLUSTER_REGION)
    eks_client = boto3.client('eks', region_name=CLUSTER_REGION)
    ec2_client = boto3.client('ec2', region_name=CLUSTER_REGION)
    with open(VAR_FILE_NAME, 'w') as VF:
        VF.write(f"eks_cluster_id = \"{CLUSTER_NAME}\"\n")
        VF.write(f"eks_cluster_endpoint = \"{get_cluster_endpoint(eks_client)}\"\n")
        VF.write(f"oidc_provider = \"{get_cluster_oidc_provider(eks_client)}\"\n")
        VF.write(f"eks_cluster_version = \"{get_cluster_eks_cluster_version(eks_client)}\"\n")
        VF.write(f"eks_cluster_certificate_authority_data= \"{get_cluster_eks_cluster_certificate_authority_data(eks_client)}\"\n")
        VF.write(f"region = \"{CLUSTER_REGION}\"\n")
    with open(VAR_FILE_NAME_UPGRADE, 'w') as VFU:
        VFU.write(f"src_s3_bucket_name = \"{S3_BUCKET_NAME}\"\n")
        VFU.write(f"src_s3_secret_name = \"{S3_SECRET_NAME}\"\n")
        VFU.write(f"src_rds_secret_name = \"{RDS_SECRET_NAME}\"\n")
        vpc_id = get_db_instance_vpc_id(rds_client)
        VFU.write(f"src_vpc_id = \"{vpc_id}\"\n")
        VFU.write(f"src_vpc_cidr = \"{get_vpc_cidr(ec2_client, vpc_id)}\"\n")
        VFU.write(f"src_vpc_private_subnets = {json.dumps(get_cluster_private_subnet_ids(eks_client, ec2_client))}\n")
        VFU.write(f"src_vpc_public_subnets = {json.dumps(get_cluster_public_subnet_ids(eks_client, ec2_client))}\n")
        VFU.write(f"src_rds_endpoint = \"{get_db_instance_endpoint(rds_client)}\"\n")
        VFU.write(f"src_cluster_sg_id = \"{get_vpc_security_group_id(eks_client)}\"\n")
        VFU.write(f"src_efs_fs_id = \"{get_efs_id(efs_client)}\"\n")


def get_efs_id(efs_client):
    fs = efs_client.describe_file_systems()
    for f in fs['FileSystems']:
        if f['Name'] == EFS_NAME:
            return f['FileSystemId']

    return None

def get_vpc_cidr(ec2_client, vpc_id):
    return ec2_client.describe_vpcs(
        VpcIds=[vpc_id]
    )['Vpcs'][0]['CidrBlock']

def get_cluster_endpoint(eks_client):
    return eks_client.describe_cluster(name=CLUSTER_NAME)["cluster"]["endpoint"]
def get_cluster_eks_cluster_version(eks_client):
    return eks_client.describe_cluster(name=CLUSTER_NAME)["cluster"]["version"]
def get_cluster_eks_cluster_certificate_authority_data(eks_client):
    return eks_client.describe_cluster(name=CLUSTER_NAME)["cluster"]["certificateAuthority"]["data"]
def get_cluster_oidc_provider(eks_client):
    return eks_client.describe_cluster(name=CLUSTER_NAME)["cluster"]["identity"]["oidc"]["issuer"]

def get_cluster_private_subnet_ids(eks_client, ec2_client):
    subnet_ids = eks_client.describe_cluster(name=CLUSTER_NAME)["cluster"][
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

    tmp_list = list(map(get_subnet_id, private_subnets))
    subnets = []
    for i in tmp_list:
        subnets.append(i.rstrip())
    return subnets


def get_cluster_public_subnet_ids(eks_client, ec2_client):
    subnet_ids = eks_client.describe_cluster(name=CLUSTER_NAME)["cluster"][
        "resourcesVpcConfig"
    ]["subnetIds"]

    # TODO handle pagination
    subnets = ec2_client.describe_subnets(SubnetIds=subnet_ids)["Subnets"]
    public_subnets = []
    for subnet in subnets:
        for tags in subnet["Tags"]:
            # eksctl generated clusters       
            if "SubnetPublic" in tags["Value"]:
                public_subnets.append(subnet)
            # cdk generated clusters
            if "aws-cdk:subnet-type" in tags["Key"]:
                if "Public" in tags["Value"]:
                    public_subnets.append(subnet)

    def get_subnet_id(subnet):
        return subnet["SubnetId"]

    tmp_list = list(map(get_subnet_id, public_subnets))
    subnets = []
    for i in tmp_list:
        subnets.append(i.rstrip())
    return subnets


def get_vpc_security_group_id(eks_client):
    security_group_id = eks_client.describe_cluster(name=CLUSTER_NAME)["cluster"][
        "resourcesVpcConfig"
    ]["clusterSecurityGroupId"]

    # Note : We only need to return 1 security group because we use the shared node security group, this fixes https://github.com/awslabs/kubeflow-manifests/issues/137
    return security_group_id


def get_db_instance_endpoint(rds_client):

    return rds_client.describe_db_instances(DBInstanceIdentifier=DB_INSTANCE_NAME)[
        "DBInstances"
    ][0]['Endpoint']['Address']

def get_db_instance_vpc_id(rds_client):

    return rds_client.describe_db_instances(DBInstanceIdentifier=DB_INSTANCE_NAME)[
        "DBInstances"
    ][0]['DBSubnetGroup']['VpcId']

parser = argparse.ArgumentParser()
parser.add_argument(
    "--region",
    type=str,
    metavar="CLUSTER_REGION",
    help="Your cluster region code (eg: us-east-2)",
    required=True,
)
parser.add_argument(
    "--cluster",
    type=str,
    metavar="CLUSTER_NAME",
    help="Your cluster name (eg: mycluster-1)",
    required=True,
)
parser.add_argument(
    "--bucket",
    type=str,
    metavar="S3_BUCKET",
    help="Your S3 bucket name (eg: mybucket)",
    required=True,
)
parser.add_argument(
    "--efs_name",
    type=str,
    metavar="EFS_NAME",
    help="Your EFS file system name",
    required=True,
)
DB_INSTANCE_NAME_DEFAULT = "kubeflow-db"
parser.add_argument(
    "--db_instance_name",
    type=str,
    default=DB_INSTANCE_NAME_DEFAULT,
    help=f"Unique identifier for the RDS database instance. Default is set to {DB_INSTANCE_NAME_DEFAULT}",
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
VAR_FILE_NAME = "terraform/sample.auto.tfvars"
parser.add_argument(
    "--var_file_name",
    type=str,
    default=VAR_FILE_NAME,
    help=f"Name of the Terraform variables file. Default is set to {VAR_FILE_NAME}",
    required=False,
)
VAR_FILE_NAME_UPGRADE = "upgrade.tfvars"
parser.add_argument(
    "--var_file_name_upgrade",
    type=str,
    default=VAR_FILE_NAME_UPGRADE,
    help=f"Name of the Terraform variables file used for upgrade. Default is set to {VAR_FILE_NAME_UPGRADE}",
    required=False,
)

args, _ = parser.parse_known_args()

if __name__ == "__main__":
    CLUSTER_REGION = args.region
    CLUSTER_NAME = args.cluster
    S3_BUCKET_NAME = args.bucket
    EFS_NAME = args.efs_name
    DB_INSTANCE_NAME = args.db_instance_name
    RDS_SECRET_NAME = args.rds_secret_name
    S3_SECRET_NAME = args.s3_secret_name
    VAR_FILE_NAME = args.var_file_name
    VAR_FILE_NAME_UPGRADE = args.var_file_name_upgrade

    main()
