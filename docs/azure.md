# Getting Started

1. Create a new Azure account or choose an existing one, as you prefer.

1.  Open a new tab to [Azure Cloud Shell](https://learn.microsoft.com/en-us/azure/cloud-shell/get-started/classic?tabs=azurecli).  You can [click here](https://shell.azure.com/).

1. Clone the repo: `git clone https://github.com/azure/aks-ctf.git && cd aks-ctf/workshop`

1. Enable the Resource Providers:
    * `az provider register --namespace Microsoft.OperationsManagement`
    * `az provider register --namespace Microsoft.ContainerService`

1. Once inside the Cloud Shell terminal, run setup.sh. This should create a new Project with a single-node Kubernetes cluster that contains the prerequisites for the workshop:
    ```console
    ./setup.sh
    source .env
    ```

The script will prompt you for a project name (just hit enter to accept the default) and a password for your webshell instances.

1. When the script is finished, verify it worked correctly.

```console
kubectl get pods --namespace dev
```

The output should look similar to this:
```
NAME                           READY   STATUS    RESTARTS   AGE
insecure-app-674cf64dd-qf7md   1/1     Running   0          63m
```

If it looks good, move on to Scenario 1 Attack.
