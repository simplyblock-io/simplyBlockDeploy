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
    key_name="$HOME/.ssh/$KEY_NAME"
    if [ ! -f "$key_name" ]; then
        echo "$SECRET_VALUE" > "$HOME/.ssh/$KEY_NAME"
        KEY="$HOME/.ssh/$KEY_NAME"
        echo "running chmod 400"
        chmod 400 "$KEY"
        echo "$key_name created successfully"
    else
        KEY="$HOME/.ssh/$KEY_NAME"
        echo "$key_name already exists."
    fi
else
    echo "Failed to retrieve secret value. Falling back to default key."
fi

mnodes=$(terraform output -raw mgmt_public_ips)
storage_private_ips=$(terraform output -raw storage_private_ips)

echo "bootstrapping cluster..."

while true; do
    echo "mgmt_public_ips: ${mnodes[0]}"
    dstatus=$(ssh -i "$KEY" -o StrictHostKeyChecking=no ec2-user@${mnodes[0]} "sudo cloud-init status" 2>/dev/null)
    echo "Current status: $dstatus"

    if [[ "$dstatus" == "status: done" ]]; then
        echo "Cloud-init is done. Exiting loop."
        break
    fi

    echo "Waiting for cloud-init to finish..."
    sleep 10
done

echo ""
echo "Deploying management node..."
echo ""

# node 1
ssh -i $KEY -o StrictHostKeyChecking=no ec2-user@${mnodes[0]} "
sbcli-dev cluster create
"

echo ""
echo "Adding other management nodes if they exist.."
echo ""

for ((i = 2; i <= $#mnodes; i++)); do
    echo ""
    echo "Adding mgmt node ${i}.."
    echo ""

    ssh -i $KEY -o StrictHostKeyChecking=no ec2-user@${mnodes[${i}]} "
    MANGEMENT_NODE_IP=${mnodes[0]}
    CLUSTER_ID=\$(curl -X GET http://\${MANGEMENT_NODE_IP}/cluster/ | jq -r '.results[].uuid')
    echo \"Cluster ID is: \${CLUSTER_ID}\"
    sbcli-dev mgmt add \${MANGEMENT_NODE_IP} \${CLUSTER_ID} eth0
    "
done

echo ""
sleep 60
echo "Adding storage nodes..."
echo ""
# node 1
ssh -i $KEY -o StrictHostKeyChecking=no ec2-user@${mnodes[0]} "
MANGEMENT_NODE_IP=${mnodes[0]}
CLUSTER_ID=\$(curl -X GET http://\${MANGEMENT_NODE_IP}/cluster/ | jq -r '.results[].uuid')
echo \"Cluster ID is: \${CLUSTER_ID}\"
sbcli cluster unsuspend \${CLUSTER_ID}

for node in ${storage_private_ips}; do
    echo ""
    echo "joining node \${node}"
    sbcli-dev storage-node add-node \$CLUSTER_ID \${node}:5000 eth0
    sleep 5
done
"

echo ""
echo "getting cluster secret"
echo ""

ssh -i $KEY -o StrictHostKeyChecking=no ec2-user@${mnodes[0]} "
MANGEMENT_NODE_IP=${mnodes[0]}
CLUSTER_ID=\$(curl -X GET http://\${MANGEMENT_NODE_IP}/cluster/ | jq -r '.results[].uuid')
CLUSTER_SECRET=(sbcli-dev cluster get-secret \${CLUSTER_ID})
"

echo ""
echo "adding pool testing1"
echo ""

ssh -i $KEY -o StrictHostKeyChecking=no ec2-user@${mnodes[0]} "
sbcli-dev pool add testing1
"

echo "::set-output name=cluster_id::$CLUSTER_ID"
echo "::set-output name=cluster_secret::$CLUSTER_SECRET"
echo "::set-output name=cluster_ip::$MANGEMENT_NODE_IP"

echo ""
echo "Successfully deployed the cluster"
echo ""
