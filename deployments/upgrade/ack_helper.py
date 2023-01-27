import subprocess
import json
import argparse

parser = argparse.ArgumentParser()
parser.add_argument('--annotations', action='store_true', help="Use annotations to prevent resource deletion")
parser.add_argument('--no-annotations', dest='annotations', action='store_false', help="Override finalizers to prevent resource deletion")
parser.set_defaults(annotations=False)

args, _ = parser.parse_known_args()

endpoints_json = subprocess.run(["kubectl", "get", "endpoints.sagemaker.services.k8s.aws", "-ojson"], capture_output=True, text=True)
endpoints = json.loads(endpoints_json.stdout)

if args.annotations:
    fname = "add-annotations.sh"
else:
    fname = "remove-finalizers.sh"

with open(fname, 'w') as R:
    for e in endpoints['items']:
        endpoint_name = e['metadata']['name']
        endpoint_id = e['spec']['endpointName']
        if args.annotations:
            R.write(f"kubectl annotate endpoints.sagemaker.services.k8s.aws {endpoint_name}")
            R.write(" services.k8s.aws/deletion-policy=retain\n")
        else:
            R.write(f"kubectl patch endpoints.sagemaker.services.k8s.aws {endpoint_name}")
            R.write(" -p '{\"metadata\":{\"finalizers\":null}}' --type=merge\n")
        with open(f"{endpoint_name}-adopted.yaml", 'w') as F:
            F.write("apiVersion: services.k8s.aws/v1alpha1\n")
            F.write("kind: AdoptedResource\n")
            F.write("metadata:\n")
            F.write(f"    name: {endpoint_name}\n")
            F.write("spec:\n")
            F.write("    aws:\n")
            F.write(f"        nameOrID: {endpoint_id}\n")
            F.write("    kubernetes:\n")
            F.write("        group: sagemaker.services.k8s.aws\n")
            F.write("        kind: Endpoint\n")