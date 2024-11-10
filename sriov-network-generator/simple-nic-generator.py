import argparse
import os
import yaml
import json
import sys

def delete_yaml_files():
    for filename in os.listdir():
        if filename.startswith("network_attachment_") or filename.startswith("sriov_network_policy_") or filename.startswith("sriov_ib_network_"):
            if filename.endswith(".yaml"):
                os.remove(filename)

def generate_network_attachment_yaml(port, ip, network_type):
    cni_type = "ib-sriov" if network_type == "SriovIBNetwork" else "sriov"

    config = {
        "cniVersion": "0.3.1",
        "name": f"network-port-{port}",
        "type": cni_type,
        "logLevel": "info",
        "ipam": {  # Adding IPAM here for network attachment
            "type": "whereabouts",
            "range": f"192.168.1.{ip}/24",
            "exclude": [
                "192.168.1.1", "192.168.1.2", "192.168.1.254", "192.168.1.255"
            ],
            "routes": [{"dst": "192.168.1.0/24"}]
        }
    }

    yaml_data = {
        "apiVersion": "k8s.cni.cncf.io/v1",
        "kind": "NetworkAttachmentDefinition",
        "metadata": {
            "annotations": {
                "k8s.v1.cni.cncf.io/resourceName": f"openshift.io/port{port}"
            },
            "name": f"network-port-{port}",
            "namespace": "default"
        },
        "spec": {
            "config": json.dumps(config, indent=4, separators=(',', ': '))
        }
    }
    return yaml_data

def generate_sriov_network_policy_yaml(ports, num_vfs, pf_names, network_type):
    yaml_data = {
        "apiVersion": "sriovnetwork.openshift.io/v1",
        "kind": "SriovNetworkNodePolicy",
        "metadata": {
            "name": f"mlnx-port-{ports[0]}",
            "namespace": "openshift-sriov-network-operator"
        },
        "spec": {
            "nodeSelector": {
                "feature.node.kubernetes.io/network-sriov.capable": "true"
            },
            "nicSelector": {
                "vendor": "15b3",
                "pfNames": pf_names
            },
            "deviceType": "netdevice",
            "numVfs": num_vfs,
            "priority": 99,
            "resourceName": f"port{ports[0]}",
            "isRdma": True
        }
    }

    # If the network type is SriovIBNetwork, add linkType: IB and relevant fields
    if network_type == "SriovIBNetwork":
        yaml_data["spec"]["rdma"] = True
        yaml_data["spec"]["ibverbs"] = True
        yaml_data["spec"]["linkType"] = "IB"  # Adding linkType: IB

    return yaml_data

def generate_sriov_ib_network_yaml(ports, pf_names):
    yaml_data = {
        "apiVersion": "sriovnetwork.openshift.io/v1",
        "kind": "SriovIBNetwork",
        "metadata": {
            "name": f"sriov-ib-network-port-{ports[0]}",
            "namespace": "openshift-sriov-network-operator"
        },
        "spec": {
            "resourceName": f"port{ports[0]}",
            "rdma": True,
            "pfNames": pf_names  # No IPAM here
        }
    }
    return yaml_data

def write_yaml_file(filename, yaml_data):
    try:
        with open(filename, 'w') as file:
            yaml.dump(yaml_data, file, default_flow_style=False)
        print(f"Successfully created {filename}")
    except IOError as e:
        print(f"Error writing {filename}: {e}")

def main():
    parser = argparse.ArgumentParser(description="Generate YAML files with incremented port and IP address values.")
    parser.add_argument("--num-network-configs", type=int, default=3, help="Number of network configurations to generate (default: 3)")
    parser.add_argument("--starting-port", type=int, default=1, help="Starting port number (default: 1)")
    parser.add_argument("--starting-ip", type=int, default=2, help="Starting IP address (default: 2)")
    parser.add_argument("--num-vfs", type=int, default=1, help="Number of VFs for the network policy (default: 1)")
    parser.add_argument("--ports-per-network-config", type=int, default=1, help="Number of ports to handle per network config (default: 1)")
    parser.add_argument("--pf-names", nargs='+', default=["ens3f0np0", "ens3f1np1"], help="List of pfNames for the ports (default: ['ens3f0np0', 'ens3f1np1'])")
    parser.add_argument("--network-type", choices=["SriovIBNetwork", "SriovNetworkNodePolicy"], default="SriovNetworkNodePolicy", help="Type of network to generate (default: SriovNetworkNodePolicy)")

    args = parser.parse_args()

    if len(args.pf_names) < args.num_network_configs:
        print("Error: Number of pfNames must be at least equal to the number of network configs.")
        sys.exit(1)

    delete_yaml_files()  # Delete existing YAML files

    for i in range(args.num_network_configs):
        ports = [args.starting_port + (i * args.ports_per_network_config) + j for j in range(args.ports_per_network_config)]
        ips = [args.starting_ip + (i * args.ports_per_network_config) + j for j in range(args.ports_per_network_config)]

        pf_names = args.pf_names[i:i + args.ports_per_network_config]

        for port, ip in zip(ports, ips):
            network_attachment_yaml = generate_network_attachment_yaml(port, ip, args.network_type)
            write_yaml_file(f'network_attachment_{port}.yaml', network_attachment_yaml)

        sriov_network_policy_yaml = generate_sriov_network_policy_yaml(ports, args.num_vfs, pf_names, args.network_type)
        write_yaml_file(f'sriov_network_policy_{ports[0]}.yaml', sriov_network_policy_yaml)

        if args.network_type == "SriovIBNetwork":
            sriov_ib_network_yaml = generate_sriov_ib_network_yaml(ports, pf_names)
            write_yaml_file(f'sriov_ib_network_{ports[0]}.yaml', sriov_ib_network_yaml)

if __name__ == "__main__":
    main()
