# aks-awx

AWX on Kubernetes

## Goal

In this repository I uploaded the files that I used to create a working AWX installation on Azure Kubernetes Services (AKS). I used the GUI for everything, one day I might add the az command line options to create everything.

Design choices:

-   Private AKS cluster (so that the API service is not exposed publicly).
-   Ingress through an Azure Application Gateway.
-   Private PostgreSQL server.
-   Separate DNS zone.

# Steps

The installation is broken down into two sections:

-   Preparation: All the supporting stuff. Chances are that some of these are already present in your environment.
-   AWX installation: All the steps to install AWX on AKS once the infrastructure is in place.

# Preparation

The preparation steps:

-   Info sheet
-   Resource groups
-   App registration for DNS integration
-   Virtual Networks
-   DNS
-   PostgreSQL server
-   Management server
-   Kubernetes cluster

## Info sheet

Create an info sheet with the following items, the values will be filled in during the preparation steps:

| Property                     | Value |
| ---------------------------- | ----- |
| AWX name                     |       |
| App registration Tenant      |       |
| App registration ID          |       |
| App registration Secret      |       |
| DNS zone subscription        |       |
| DNS zone resource group name |       |
| DNS zone name                |       |
| PostgreSQL server FQDN       |       |
| PostgreSQL admin password    |       |
| PostgreSQL user password     |       |
| AWX operator version         |       |

**Table 1:** Custom properties

## Resource groups

I decided to split everything up into two resource groups:

-   Infrastructure - In this RG the infrastructure items are placed: DNS, VNET
-   AWX - In this resource group the AWX items are placed: PostgreSQL, management VM, AKS

## App registration

Create an app registration in Entra ID. Create a secret for this app registration. Write down the app ID, tenant ID, and app secret in the info sheet.

## Virtual network

Create a new Virtual network 'VNET-AWX' in the _Infrastructure_ resource group.
Create three subnets in the vnet:

-   SNET-VMS - The management VM will be placed in this subnet.
-   SNET-POSTGRES - The PostgreSQL server will be placed in this subnet. In order to do this the subnet should be delegated to 'Microsoft.DBforPostgreSQL/flexibleServers'.
-   SNET-KUBERNETES - The Kubernetes pods will be placed in this subnet.

For the lab I chose the following ranges:

| Network         | IP range     |
| --------------- | ------------ |
| VNET            | 10.0.0.0/16  |
| SNET-VMS        | 10.0.0.0/24  |
| SNET-POSTGRES   | 10.0.1.0/28  |
| SNET-KUBERNETES | 10.0.16.0/20 |

**Table 2:** IP ranges for virtual network and subnets

## DNS zone

Create a new DNS zone in the _Infrastructure_ resource group.
Add the app registration as 'DNS Contributor' to the zone.
Write down the values for subscription, resource group, and zone name in the info sheet.
In the rest of the documentation I am going to use `azure.my.domain` as the domain name.

## PostgreSQL server

Create an 'Azure Database for PostgreSQL Flexible Server' in the _AWX_ resource group, with the following options:

-   Basics tab
    -   Version: 15
    -   Workload type: Development
    -   Compute + Storage: Burstable B1ms, 32GB storage, P4 tier
    -   PostgreSQL authentication only (create an admin 'pgadmin' and write down the password in the info sheet)
-   Networking tab
    -   Private access
    -   If you created the PG SNET correctly, it will be filled in by default. If not, you should go back to the subnet and check that the delegation is created correctly

Note that the version is dependent on the AWX version you want to install. 15 works good for AWX 24.6.1 (latest version available at the monent of writing).

## Windows management VM

Create a small Windows Server management VM, and link it to the VMS snet.
Install WSL (`wsl --install`), reboot, and start WSL, it'll install Ubuntu as a default WSL distribution.
Open Ubuntu and install the following packages:

-   Az command line: https://learn.microsoft.com/en-us/cli/azure/install-azure-cli-linux?pivots=apt#option-1-install-with-one-command
-   Postgres client: `sudo apt install postgresql-client`

## Kubernetes

Create an AKS cluster to the _AWX_ resource group with the following options:

-   Basics tab
    -   Choose the _AWX_ resource group and create a unique AKS clustername
    -   Dev/Test cluster
    -   Disable automatic updates
-   Node pools
    -   2 nodes in agent pool, manual scaling
-   Networking
    -   Private cluster
    -   Azure CNI node subnet
    -   Bring your own network
    -   Choose the Kubernetes subnet you created earlier
    -   Choose a service range that does not overlap with any other network. I used 10.1.0.0/16. Don't forget to update the DNS IP address to be in this range
    -   Azure network policy
-   Monitoring
    -   Disable all monitoring

After the cluster is created, an application gateway ingress controller should be added in Settings - Networking - Virtual. Click on 'create new' to create a new subnet.
I don't know how large this subnet should be, I used 10.0.48.0/20 so it is equal in size to the Kubernetes subnet.
Note that creating the AG can take a long (30+ minutes) time.
After the AG is created, create an alias record for the DNS name you want to use (e.g. `awx` which will be `awx.azure.my.domain` as FQDN).

## Testing if everything works

Open Ubuntu and test if everything works:

### Kubernetes

Log in into Azure: `az login --use-device-code`
Install the Kubernetes tools: `sudo az aks install-cli`
Get the AKS credentials: `az aks get-credentials --resource-group [RG] --name [AKS cluster] --overwrite-existing` (use the correct AG/clustername)
Check access to the cluster: `kubectl get nodes`

### PostgreSQL

Add the following lines to `~/.profile`:

```bash
export PGHOST=[PGhostname].postgres.database.azure.com
export PGUSER=pgadmin
export PGPORT=5432
export PGDATABASE=postgres
```

Dot-source the profile (`. ~/.profile`) and log in with `psql`. Check the version of the server.

Create the database and database user for your AWX installation:

```sql
CREATE DATABASE {servicename};
CREATE USER {servicename} PASSWORD 'P@ssw0rd.123';
GRANT CONNECT ON DATABASE {servicename} TO {servicename};
GRANT ALL PRIVILEGES ON DATABASE {servicename} TO {servicename};
```
(replace {servicename} with the name of your installation, e.g. 'awxdev').
Test the connection: ```psql -U {servicename} -d {servicename}```.

# AWX
Open two Ubuntu screens, in the first you will execute the commands, in the second you will monitor the deployment.
Start the monitoring in the second screen:

```bash
watch kubectl get awx,all,ingress,secrets -n awxdev
```

## Get the deployment files
Clone https://github.com/ildjarnisdead/aks-awx
Create a copy of the aks-awx directory with the name of your installation (e.g. 'awxdev') and go to this directory.

## Cert manager
In order to give the cluster a certificate, cert manager will be installed.

Replace the version number (v1.17.1) in the following line with the latest version.

```bash
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.17.1/cert-manager.yaml
```

## Cluster issuer
Edit the files in the cert-manager/ subdirectory and replace all variables enclosed in {} with the correct values for your installation. E.g. `{dnszone}` with `azure.my.domain` or `{namespace}` with `awxdev`.
Uncomment the correct server, while testing I would suggest the staging server, don't use the prodution server for tests.

Create the cluster issuer:
```bash
kubectl apply -f cert-manager/cluster-issuer.yaml
```

## AWX Operator
Edit the files in the operator/ subdirectory and replace all variables enclosed in {} with the correct values for your installation.

Create the operator:
```bash
kubectl apply -k operator/
```

Check the monitoring terminal, you should see various resources. Wait until the operator is fully running.

## AWX
Edit the files in the awx/ subdirectory and replace all variables enclosed in {} with the correct values for your installation.

Create the AWX deployment:
```bash
kubectl apply -k awx/
```

In the monitoring screen you will see various resources being created.
Check the deployment logs and wait until PLAY RECAP is shown without any errors, this can take a while.

```
kubectl -n awxdev logs -f deployments/awx-operator-controller-manager
```

## Ingress
Edit the files in the ingress/ subdirectory and replace all variables enclosed in {} with the correct values for your installation.

Create the ingress:
```bash
kubectl apply -k ingress/
```

Check the monitoring screen, the ingress should show the public IP address of the application gateway.
Also check the secrets, there should be an `awxdev-certificate` secret of type `kubernetes.io/tls`. If there's only an opaque secret `awxdev-certificate-[randomletters]` then something is wrong with the certificate issuance.

# Testing the server
Everything should be up and running now.

Open https://awx.azure.my.domain/ in a browser. If you used a staging cert and have HSTS activated for your domain you may get an HSTS block, type 'thisisunsafe' in the browser window to continue.
You should see the login page.

In order to get the initial admin password, you can use:
```
kubectl -n awxdev get secret awxdev-admin-password -o jsonpath="{.data.password}" | base64 --decode ; echo
```