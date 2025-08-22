# aks-awx

AWX on Kubernetes

## Goal

In this repository I uploaded the files that I used to create a working AWX installation on Azure Kubernetes Services (AKS). I used the GUI for everything, one day I might add the az command line options to create everything.

Design choices:

-   Private AKS cluster (so that the API service is not exposed publicly).
-   Ingress through an Azure Application Gateway.
-   Private PostgreSQL server.
-   Because the Let's encrypt certificate issuance will be done with a DNS verification, I advise to create a separate DNS zone as a sub zone of your primary DNS zone. E.g. if you are 'company.com', create an 'azure.company.com' subzone with a NS record in your primary zone pointing to the Azure zone.

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

| Property                            | Configname        | Value |
| ----------------------------------- | ----------------- | ----- |
| AWX operator version                | awxoperator       |       |
| AWX replica count                   | replicacount      |       |
| AWX servicename                     | servicename       |       |
| App registration ID                 | appid             |       |
| App registration Secret             | appsecret         |       |
| App registration Tenant ID          | tenantid          |       |
| Azure AWX resource group            | awxrg             |       |
| Azure infrastructure resource group | infrarg           |       |
| Cert manager version                | certmgr           |       |
| DNS zone name                       | dnszone           |       |
| DNS zone subscription ID            | dnssubscriptionid |       |
| Kubernetes cluster name             | kubecluster       |       |
| PostgreSQL admin password           | pgdminpwd         |       |
| PostgreSQL admin user               | pgadmin           |       |
| PostgreSQL server name              | pgserver          |       |
| PostgreSQL user password            | pguserpwd         |       |

**Table 1:** Custom properties

In the rest of the documentation and files, I will use **[configname]** which should be replaced with the value from this table.

## AWX

Decide on the servicename. E.g. `awxtest` for a test environment, or `awxprod` for a production environment.

After finishing, the AWX installation will be reachable at `https://[servicename].[dnszone]`.

Check `https://github.com/ansible/awx-operator/tags` for the list of AWX operator versions, and pick the one you want.

Check `https://github.com/cert-manager/cert-manager/tags` for the list of cert-manager versions, and pick the one you want.

Decide on how many replica's you want to run.

Fill in the following line in the info sheet:

-   `AWX operator version`
-   `AWX replica count`
-   `AWX servicename`
-   `Cert manager version`

## Resource groups

I decided to split everything up into two resource groups:

-   `[infrarg]` - In this RG the infrastructure items are placed: DNS, VNET
-   `[awxrg]` - In this resource group the AWX items are placed: PostgreSQL, management VM, AKS

Create the resource groups.

Fill in the following lines in the info sheet:

-   `Azure AWX resource group`
-   `Azure infrastructure resource group`

## App registration

Create an app registration in Entra ID.

Create a secret for this app registration.

Fill in the following lines in the info sheet:

-   `App registration ID`
-   `App registration secret`
-   `App registration tenant ID`

## Virtual network

Create a new Virtual network 'VNET' in the `[infrarg]` resource group.
Create three subnets in the vnet:

-   SNET-VMS - The management VM will be placed in this subnet.
-   SNET-POSTGRES - The PostgreSQL server will be placed in this subnet. In order to do this the subnet should be delegated to 'Microsoft.DBforPostgreSQL/flexibleServers'.
-   SNET-KUBERNETES - The Kubernetes pods will be placed in this subnet.
-   SNET-APPGW - The application gateway for Kubernetes will be connected to this subnet.

For the lab I chose the following ranges:

| Network         | IP range     |
| --------------- | ------------ |
| VNET            | 10.0.0.0/16  |
| SNET-VMS        | 10.0.0.0/24  |
| SNET-POSTGRES   | 10.0.1.0/28  |
| SNET-KUBERNETES | 10.0.16.0/20 |
| SNET-APPGW      | 10.0.32.0/20 |

**Table 2:** IP ranges for virtual network and subnets

## DNS zone

Create a new DNS zone in the `[infrarg]` resource group.

Add the app registration as 'DNS Zone Contributor' to the zone.

Fill in the following lines in the info sheet:

-   `DNS zone name`
-   `DNS zone subscription ID`

If needed, create a NS record to the DNS zone in your parent zone.

## PostgreSQL server

Create an 'Azure Database for PostgreSQL Flexible Server' in the `[awxrg]` resource group, with the following options:

-   Basics tab
    -   server name
    -   Version: 15 (or higher)
    -   PostgreSQL authentication only (create an admin 'pgadmin' and write down the password in the info sheet)
-   Networking tab
    -   Private access. If you created `SNET-POSTGRES` correctly, it will be filled in by default. If not, you should go back to the subnet and check that the delegation is created correctly

Settings not mentioned can be left to the default, or set to your own preferences.

Note that the version is dependent on the AWX version you want to install. 15 works good for AWX 24.6.1 (latest version available at the monent of writing).

Fill in the following lines in the info sheet:

-   `PostgreSQL admin password`
-   `PostgreSQL admin user`
-   `PostgreSQL server name`

## Windows management VM

Create a Windows Server management VM in the `[awxrg]` resource group which allows virtualization (e.g. a D4v), and link it to the `SNET-VMS` snet.
Install WSL (`wsl --install`), reboot, and start WSL, it'll install Ubuntu as a default WSL distribution.
Open Ubuntu and install the following packages:

-   Az command line: https://learn.microsoft.com/en-us/cli/azure/install-azure-cli-linux?view=azure-cli-latest&pivots=apt#option-1-install-with-one-command
-   Postgres client: `sudo apt install postgresql-client`

## Kubernetes

Create an AKS cluster to the `[awxrg]` resource group with the following options (options not mentioned can be left default, or chosen as you like):

-   Basics tab
    -   Choose the `[awxrg]` resource group and create a unique AKS clustername
-   Networking
    -   Private cluster
    -   Azure CNI node subnet
    -   Bring your own network
    -   Choose the `SNET-KUBERNETES` subnet you created earlier
    -   Choose a service range that does not overlap with any other network. I used 10.1.0.0/16. Don't forget to update the DNS IP address to be in this range
    -   Azure network policy

After the cluster is created, an application gateway ingress controller should be added in Settings - Networking - Virtual. Click on 'create new' to create a new subnet.

Note that creating the AG can take a long (30+ minutes) time.

After the AG is created, create an alias record for `[servicename]` in the `[dnszone]` DNS zone, linked to the public IP address of the application gateway.

Fill in the following line in the info sheet:

-   `Kubernetes cluster name`

## Testing if everything works

Open an Ubuntu terminal on the management VM and test if everything works:

### Kubernetes

1. Log in into Azure: `az login --use-device-code`
2. Install the Kubernetes tools: `sudo az aks install-cli`
3. Get the AKS credentials: `az aks get-credentials --resource-group [awxrg] --name [kubecluster] --overwrite-existing`
4. Check access to the cluster: `kubectl get nodes`

### PostgreSQL

Add the following lines to `~/.profile`:

```bash
export PGHOST=[pgserver].postgres.database.azure.com
export PGUSER=[pgadmin]
export PGPORT=5432
export PGDATABASE=postgres
```

Dot-source the profile (`. ~/.profile`) and log in with `psql`. Check the version of the server.

Create the database and database user for your AWX installation, and grant all privileges to the database and the public schema:

```sql
CREATE DATABASE [servicename];
CREATE USER [servicename] PASSWORD 'P@ssw0rd.123';
GRANT CONNECT ON DATABASE [servicename] TO [servicename];
GRANT ALL PRIVILEGES ON DATABASE [servicename] TO [servicename];
\c [servicename]
GRANT ALL PRIVILEGES ON SCHEMA public TO [servicename];
REVOKE ALL PRIVILEGES ON SCHEMA public FROM public;
```

Test the connection: `psql -U [servicename] -d [servicename]`.

# AWX

Open two Ubuntu screens, in the first you will execute the commands, in the second you will monitor the deployment.
Start the monitoring in the second screen:

```bash
watch kubectl get awx,all,ingress,secrets -n [servicename]
```

## Get the deployment files

Clone the repo: `git clone https://github.com/ildjarnisdead/aks-awx`

Create a copy of the aks-awx directory with the name of your installation (`[servicename]`) and go to this directory.

## Fill in all the config variables

For every config option, use the following bash line to update the values in the deployment files:

```bash
find . -name \*.yml -exec sed 's/[configname]/[configvalue]/' {} \+
```

E.g. `find . -name \*.yml -exec sed 's/replicacount/2/' {} \+` to set the replicacount to 2.

## Cert manager

**Only do this if you don't have a cluster issuer yet**
In order to give the cluster a certificate, cert manager will be installed.

```bash
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/[certmgr]/cert-manager.yaml
```

## Cluster issuer

Edit the files in the cert-manager/ subdirectory and replace all variables enclosed in [] with the correct values for your installation. See the info sheet for the variable names.

While testing I would suggest the staging server, don't use the prodution server for tests. Once you're ready, you can switch to the production server.

Create the cluster issuer:

```bash
kubectl apply -k cert-manager
```

## AWX Operator

Edit the files in the operator/ subdirectory and replace all variables enclosed in [] with the correct values for your installation. See the info sheet for the variable names.

Create the operator:

```bash
kubectl apply -k operator/
```

Check the monitoring terminal, you should see various resources. Wait until the operator is fully running.

## AWX

Edit the files in the awx/ subdirectory and replace all variables enclosed in [] with the correct values for your installation. See the info sheet for the variable names.

Create the AWX deployment:

```bash
kubectl apply -k awx/
```

In the monitoring screen you will see various resources being created.

If needed, check the deployment logs and wait until PLAY RECAP is shown without any errors, this can take a while.

```
kubectl -n [servicename] logs -f deployments/awx-operator-controller-manager
```

## Ingress

Edit the files in the ingress/ subdirectory and replace all variables enclosed in [] with the correct values for your installation. See the info sheet for the variable names.

Create the ingress:

```bash
kubectl apply -k ingress/
```

Check the monitoring screen, the ingress should show the public IP address of the application gateway.

Also check the secrets, there should be an `awxdev-certificate` secret of type `kubernetes.io/tls`. If there's only an opaque secret `awxdev-certificate-[randomletters]` then something is wrong with the certificate issuance. See https://cert-manager.io/docs/troubleshooting/ for troubleshooting steps.

# Testing the server

Everything should be up and running now.

Open `https://[servicename].[dnszone]/` in a browser. If you used a staging cert and have HSTS activated for your domain you may get an HSTS block, type 'thisisunsafe' in the browser window to continue.

You should see the login page.

In order to get the initial admin password, you can use :

```bash
kubectl -n [servicename] get secret awxdev-admin-password -o jsonpath="{.data.password}" | base64 --decode ; echo
```
