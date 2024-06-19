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

echo "Set your AWS credentials and region"

AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID
AWS_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY
AWS_DEFAULT_REGION=$AWS_REGION
S3_BUCKET=$S3_BUCKET_NAME

mnodes=$(terraform output -raw mgmt_private_ips)
echo "mgmt_private_ips: ${mnodes}"
IFS=' ' read -ra mnodes <<<"$mnodes"
BASTION_IP=$(terraform output -raw bastion_public_ip)
storage_private_ips=$(terraform output -raw storage_private_ips)

ssh -i "$KEY" -o IPQoS=throughput -o StrictHostKeyChecking=no \
    -o ServerAliveInterval=60 -o ServerAliveCountMax=10 \
    -o ProxyCommand="ssh -o StrictHostKeyChecking=no -i "$KEY" -W %h:%p ec2-user@${BASTION_IP}" \
    ec2-user@${mnodes[0]} "
sudo yum install -y unzip
if [ ! -f "awscliv2.zip" ]; then
    curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
    unzip awscliv2.zip
    sudo ./aws/install
else
    echo "awscli already exists."
fi

aws configure set aws_access_key_id $AWS_ACCESS_KEY_ID
aws configure set aws_secret_access_key $AWS_SECRET_ACCESS_KEY
aws configure set default.region $AWS_DEFAULT_REGION
aws configure set default.output json

LOCAL_LOGS_DIR="$RUN_ID"

mkdir -p "\$LOCAL_LOGS_DIR"

DOCKER_CONTAINER_IDS=\$(sudo docker ps -aq)

echo "\$DOCKER_CONTAINER_IDS"
for CONTAINER_ID in \$DOCKER_CONTAINER_IDS; do
    CONTAINER_NAME=\$(sudo docker inspect --format="{{.Name}}" "\$CONTAINER_ID" | sed 's/\///')

    sudo docker logs "\$CONTAINER_ID" &> "\$LOCAL_LOGS_DIR/\$CONTAINER_NAME.txt"

    aws s3 cp "\$LOCAL_LOGS_DIR/\$CONTAINER_NAME.txt" "s3://$S3_BUCKET/\$LOCAL_LOGS_DIR/mgmt/\$CONTAINER_NAME.txt"
done
rm -rf "\$LOCAL_LOGS_DIR"
"

## get logs for storage nodes
for node in $storage_private_ips; do
    echo "getting logs from storage node: ${node}"
    ssh -i "$KEY" -o IPQoS=throughput -o StrictHostKeyChecking=no \
        -o ServerAliveInterval=60 -o ServerAliveCountMax=10 \
        -o ProxyCommand="ssh -o StrictHostKeyChecking=no -i "$KEY" -W %h:%p ec2-user@${BASTION_IP}" \
        ec2-user@${node} "

sudo yum install -y unzip
if [ ! -f "awscliv2.zip" ]; then
    curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
    unzip awscliv2.zip
    sudo ./aws/install
else
    echo "awscli already exists."
fi

aws configure set aws_access_key_id $AWS_ACCESS_KEY_ID
aws configure set aws_secret_access_key $AWS_SECRET_ACCESS_KEY
aws configure set default.region $AWS_DEFAULT_REGION
aws configure set default.output json


LOCAL_LOGS_DIR="$RUN_ID"

mkdir -p "\$LOCAL_LOGS_DIR"

# Look for core dump files and upload to S3
for DUMP_FILE in /etc/simplyblock/*; do
    if [ -f "\$DUMP_FILE" ]; then
        aws s3 cp "\$DUMP_FILE" "s3://$S3_BUCKET/\$LOCAL_LOGS_DIR/storage/${node}/\$(basename \$DUMP_FILE)" --storage-class STANDARD --only-show-errors
    fi
done

DOCKER_CONTAINER_IDS=\$(sudo docker ps -aq)

echo "\$DOCKER_CONTAINER_IDS"
for CONTAINER_ID in \$DOCKER_CONTAINER_IDS; do
    CONTAINER_NAME=\$(sudo docker inspect --format="{{.Name}}" "\$CONTAINER_ID" | sed 's/\///')

    sudo docker logs "\$CONTAINER_ID" &> "\$LOCAL_LOGS_DIR/\$CONTAINER_NAME.txt"

    aws s3 cp "\$LOCAL_LOGS_DIR/\$CONTAINER_NAME.txt" "s3://$S3_BUCKET/\$LOCAL_LOGS_DIR/storage/${node}/\$CONTAINER_NAME.txt"
done
rm -rf "\$LOCAL_LOGS_DIR"
"
    echo "done getting logs from node: ${node}"
done
