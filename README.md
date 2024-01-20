### Intro

Terraform template to setup simple cluster

### Deploy infra

```
# change count for mgmt_nodes and storage_nodes variables in variables.tf

# review the resources
terraform plan

terraform init
terraform apply -var mgmt_nodes=3 -var storage_nodes=3 --auto-approve
```

### Cluster bootstrapping

```
# in the boostrap-cluster.sh update KEY

chmod +x ./bootstrap-cluster.sh
./bootstrap-cluster.sh

```


create sn nodes of type: m6id.large
add sn to cluster --> wil get an error: nvme devices not found.

and change to i3en.large
we observe that the private IPs didn't change.
add sn to cluster  -->wil get an error: nvme devices not found.
