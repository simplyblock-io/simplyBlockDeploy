#!/bin/bash

KEY="$HOME/.ssh/simplyblock-ohio.pem"

SECRET_VALUE=$(terraform output -raw secret_value)
KEY_NAME=$(terraform output -raw key_name)

ssh_dir="$HOME/.ssh"

if [ ! -d "$ssh_dir" ]; then
    mkdir -p "$ssh_dir"
    echo "Directory $ssh_dir created."
else
    echo "Directory $ssh_dir already exists."
fi

if [[ -n "$SECRET_VALUE" ]]; then
    KEY="$HOME/.ssh/$KEY_NAME"
    if [ -f "$HOME/.ssh/$KEY_NAME" ]; then
        echo "the ssh key: ${KEY} already exits on local"
    else
        echo "$SECRET_VALUE" >"$KEY"
        chmod 400 "$KEY"
    fi
else
    echo "Failed to retrieve secret value. Falling back to default key."
fi

mnodes=($(terraform output -raw extra_nodes_public_ips))

echo "::set-output name=KEY::$KEY"
echo "::set-output name=extra_node_ip::${mnodes[0]}"

master_ip=${mnodes[0]}


ssh -i $KEY -o StrictHostKeyChecking=no ec2-user@$master_ip "
sudo yum install -y fio nvme-cli;
sudo modprobe nvme-tcp
sudo modprobe nbd
sudo sysctl -w vm.nr_hugepages=4096
sudo sysctl -w net.ipv6.conf.all.disable_ipv6=1
sudo sysctl -w net.ipv6.conf.default.disable_ipv6=1
sudo systemctl disable nm-cloud-setup.service nm-cloud-setup.timer
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC='--advertise-address=$master_ip' bash
sudo /usr/local/bin/k3s kubectl taint nodes --all node-role.kubernetes.io/master-
sudo /usr/local/bin/k3s kubectl get node
sudo yum install -y pciutils
lspci
sudo chown ec2-user:ec2-user /etc/rancher/k3s/k3s.yaml
sudo yum install -y make golang
sudo yum install -y yum-utils
sudo yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
sudo yum install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo systemctl start docker
"

TOKEN=$(ssh -i $KEY -o StrictHostKeyChecking=no ec2-user@$master_ip "sudo cat /var/lib/rancher/k3s/server/node-token")

for ((i=1; i<${#mnodes[@]}; i++)); do
    ssh -i $KEY -o StrictHostKeyChecking=no ec2-user@${mnodes[${i}]} "
    sudo yum install -y fio nvme-cli;
    sudo modprobe nvme-tcp
    sudo modprobe nbd
    sudo sysctl -w vm.nr_hugepages=4096
    sudo sysctl -w net.ipv6.conf.all.disable_ipv6=1
    sudo sysctl -w net.ipv6.conf.default.disable_ipv6=1
    sudo systemctl disable nm-cloud-setup.service nm-cloud-setup.timer
    curl -sfL https://get.k3s.io | K3S_URL=https://$master_ip:6443 K3S_TOKEN=$TOKEN bash
    sudo /usr/local/bin/k3s kubectl get node
    sudo yum install -y pciutils
    lspci
    sudo yum install -y make golang
    sudo yum install -y yum-utils
    sudo yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
    sudo yum install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    sudo systemctl start docker
    "
done

