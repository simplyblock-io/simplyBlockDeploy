import yaml
import json
from .ssh_keys import generate_create_ssh_keypair
from .cf_construct import cf_construct
from .aws_functions import cloudformation_deploy, get_instances_from_cf_resources
from .sb_deploy import sb_deploy
from .print_info import print_info, print_connectivity_info
from .setup_csi import setup_csi
import pprint


def parse_instances_yaml(instances_yaml_file):
    with open(instances_yaml_file, "r") as stream:
        try:
            instances = yaml.safe_load(stream)
        except yaml.YAMLError as exc:
            print(exc)
    return instances


def provisioner(namespace=None, az=None, deploy=None, instances=None, dry_run=False, sbcli_pkg=None):
    # Set up key filename
    instances['PublicKeyMaterial'] = generate_create_ssh_keypair(namespace=namespace)

    # Get the CF stack
    cf_stack = cf_construct(namespace=namespace, instances=instances, region=az)
    print(json.dumps(cf_stack, indent=4))
    if dry_run or not deploy:
        print("Dry run! No deployment done.")
        return

    # cloudformation will deploy and return when the stack is green.
    # If the stack is already deployed in that namespace it will catch the error and return.
    stack_id = cloudformation_deploy(namespace=namespace, cf_stack=cf_stack, region_name=az["RegionName"])
    if not stack_id:
        return

    instances_dict_of_lists = get_instances_from_cf_resources(namespace=namespace, region_name=az['RegionName'])
    cluster_create_output = sb_deploy(namespace=namespace, instances=instances_dict_of_lists, sbcli_pkg=sbcli_pkg)

    if instances_dict_of_lists["kubernetes"]:
        from pkg_resources import Requirement
        sbcli_cmd = Requirement.parse(sbcli_pkg).name
        setup_csi(namespace=namespace, instances_dict_of_lists=instances_dict_of_lists,
                  cluster_uuid=cluster_create_output["cluster_uuid"], sbcli_cmd=sbcli_cmd)
    else:
        print("Kubernetes nodes are not defined. Csi setup skipped.")
    print_info(instances_dict_of_lists)
    print_connectivity_info(instances_dict_of_lists, namespace)
