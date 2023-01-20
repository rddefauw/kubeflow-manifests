import argparse
import boto3
import json

def main():
    with open(STATE_FILE, 'r') as SF:
        with open(VAR_FILE_NAME_UPGRADE, 'w') as VFU:
            state = json.load(SF)
            resources = state['resources']
            for r in resources:
                if r['name'] == 'artifact_store' and r['module'] == 'module.kubeflow_components.module.s3[0]':
                    VFU.write(f"src_s3_bucket_name = \"{r['instances'][0]['attributes']['bucket']}\"\n")
                if r['name'] == 's3_secret':
                    VFU.write(f"src_s3_secret_name = \"{r['instances'][0]['attributes']['name']}\"\n")
                if r['name'] == 'rds_secret':
                    VFU.write(f"src_rds_secret_name = \"{r['instances'][0]['attributes']['name']}\"\n")
                if r['name'] == 'eks_efs_fs':
                    VFU.write(f"src_efs_fs_id = \"{r['instances'][0]['attributes']['id']}\"\n")
                if r['name'] == 'kubeflow_db':
                    VFU.write(f"src_rds_endpoint = \"{r['instances'][0]['attributes']['address']}\"\n")
                if r['type'] == 'aws_vpc':
                    VFU.write(f"src_vpc_id = \"{r['instances'][0]['attributes']['id']}\"\n")
                    VFU.write(f"src_vpc_cidr = \"{r['instances'][0]['attributes']['cidr_block']}\"\n")
                if r['type'] == 'aws_cognito_user_pool_domain':
                    VFU.write(f"cognito_user_pool_domain = \"{r['instances'][0]['attributes']['domain']}\"\n")
                if r['type'] == 'aws_cognito_user_pool':
                    VFU.write(f"user_pool_id = \"{r['instances'][0]['attributes']['id']}\"\n")
                    VFU.write(f"cognito_user_pool_arn = \"{r['instances'][0]['attributes']['arn']}\"\n")
                if r['type'] == 'aws_eks_cluster' and r['module'] == 'module.eks_blueuprints':
                    VFU.write(f"src_cluster_sg_id = \"{r['instances'][0]['attributes']['vpc_config'][0]['cluster_security_group_id']}\"\n")
                if r['type'] == 'aws_acm_certificate' and r['name'] == 'deployment_region':
                    VFU.write(f"certificate_arn = \"{r['instances'][0]['attributes']['arn']}\"\n")
                if r['type'] == 'aws_subnet' and r['name'] == 'public':
                    public_subnets = []
                    for s in r['instances']:
                        public_subnets.append(s['attributes']['id'])
                    VFU.write(f"src_vpc_public_subnets = {json.dumps(public_subnets)}\n")
                if r['type'] == 'aws_subnet' and r['name'] == 'private':
                    private_subnets = []
                    for s in r['instances']:
                        private_subnets.append(s['attributes']['id'])
                    VFU.write(f"src_vpc_private_subnets = {json.dumps(private_subnets)}\n")

parser = argparse.ArgumentParser()
parser.add_argument(
    "--statefile",
    type=str,
    help="Location of Terraform state file",
    required=True,
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
    STATE_FILE = args.statefile
    VAR_FILE_NAME_UPGRADE = args.var_file_name_upgrade

    main()
