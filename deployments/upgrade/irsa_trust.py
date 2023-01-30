import subprocess
import json
import argparse
import boto3

iam = boto3.client('iam')

parser = argparse.ArgumentParser()
parser.add_argument('--oidc_url', help="OIDC URL for new cluster", required=True)
parser.add_argument('--account_id', help="AWS Account ID", required=True)

args, _ = parser.parse_known_args()

profiles_json = subprocess.run(["kubectl", "get", "profile", "-ojson"], capture_output=True, text=True)
profiles = json.loads(profiles_json.stdout)

roles_updated = []
for p in profiles['items']:
    profile_name = p['metadata']['name']
    print(f"Working on profile {profile_name}")

    sa_json = subprocess.run(["kubectl", "get", "serviceaccount", "-n", profile_name, "-ojson"], capture_output=True, text=True)
    svcAccts = json.loads(sa_json.stdout)
    for s in svcAccts['items']:
        sa_name = s['metadata']['name']
        print(f"Working on SA {sa_name}")

        sad_json = subprocess.run(["kubectl", "get", "serviceaccount", sa_name, "-n", profile_name, "-ojson"], capture_output=True, text=True)
        svcAcctDetails = json.loads(sad_json.stdout)
        svcAcctMeta = svcAcctDetails['metadata']
        if 'annotations' in svcAcctMeta:
            annotations = svcAcctMeta['annotations']
            if 'eks.amazonaws.com/role-arn' in annotations:
                roleArn = annotations['eks.amazonaws.com/role-arn']
                print(f"Found annotation - {roleArn}")
                roleName = roleArn.split('/')[-1]

                if roleName in roles_updated:
                    print(f"Role {roleName} already updated")
                else:
                    role = iam.get_role(RoleName=roleName)
                    trust_doc = role['Role']['AssumeRolePolicyDocument']
                    print(f"Got trust policy {trust_doc}")

                    trust_doc['Statement'].append({"Effect": "Allow", 
                        "Principal": {
                            "Federated": f"arn:aws:iam::{args.account_id}:oidc-provider/{args.oidc_url}"
                        },
                        "Action": "sts:AssumeRoleWithWebIdentity",
                        "Condition": {
                            "StringEquals": {
                                f"{args.oidc_url}:aud": "sts.amazonaws.com"
                            }
                        }
                    })
                    print(f"New trust policy {trust_doc}")

                    iam.update_assume_role_policy(
                        RoleName=roleName,
                        PolicyDocument=json.dumps(trust_doc)
                    )
                    roles_updated.append(roleName)