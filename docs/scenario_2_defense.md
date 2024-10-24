# Persistence: Scenario 2 Defense

## Backstory

### Name: __Blue__

* Still overworked
* Still can only do the bare minimum
* Uses the defaults when configuring systems
* Usually gets blamed for stability or security issues

### Motivations

* A week after the first incident, __Blue__ gets paged at 3am because “the website is slow again”.
* __Blue__, puzzled, takes another look.
* __Blue__ decides to dust off the résumé “just in case”.

## Defense

__Blue__ is paged again with the same message as last time. What is going on? Could this be the same problem again?

### Identifying the Issue

Let's run some basic checks again to see if we can find random workloads:

```console
kubectl get pods --all-namespaces
```

It's back! But how? Let's check the audit logs again:

```kql
AKSAuditAdmin
| where RequestUri startswith "/apis/apps/v1/namespaces/default/deployments" 
    and Verb == "create" 
    and ObjectRef contains "bitcoinero"
| project User, SourceIps, UserAgent, ObjectRef, TimeGenerated
```
![Audit logs showing the bitcoinero deployment was created by the metrics-server-account](img/defense-2-auditlogs.png)

How did a service account associated with the metrics-server create a deployment? And what is that sourceIP, it looks familiar...
```console
#Fetch the public IP address for the cluster API server
az network public-ip show --ids $(az aks show --resource-group $RESOURCE_GROUP --name $AKS_NAME --query "networkProfile.loadBalancerProfile.effectiveOutboundIPs[0].id" --output tsv) --query "ipAddress" --output tsv
```

So let me get this straight... the `bitcoinero deployment` was created by another deployment's service account, using curl, from *inside* the cluster? 

__Blue__ is starting to suspect that there may be an unwanted visitor in the cluster. But how to find them? Let's by looking for `ClusterRoles` with high levels of permissions:
```console
#List all ClusterRoles with unlimited access to all APIs and resource types
kubectl get clusterrole -o json | jq '.items[] | select(.rules[]?.resources == ["*"] and .rules[]?.verbs == ["*"] and .rules[]?.verbs == ["*"]) | .metadata.name'
```

`cluster-admin` is the only role that *should* be in that list. What is this `privileged-role` that we are also seeing?
```console
kubectl get clusterrolebinding -o json | jq '.items[] | select(.roleRef.name == "privileged-role")'
```

Why would the `metrics-server` need such high level privileges? Let's take a closer look at that deployment:
```console
# Look at the details of the deployment
kubectl get deployment -n kube-system metrics-server-deployment -o yaml
# And the associated service
kubectl get svc -n kube-system metrics-server-service -o yaml
```

`metrics-server` is actually running an SSH server! And it's running as a privileged container! This is *bad*. We need to clean this up fast!

### Fixing the Leak
__Blue__ decides it is time to evict this bad actor once and for all. Let's delete all of their work:
```console
# Service
kubectl delete service -n kube-system metrics-server-service
# Deployment
kubectl delete deployment -n kube-system metrics-server-deployment
# ClusterRoleBinding
kubectl delete clusterrolebinding -n kube-system privileged-binding
# ClusterRole
kubectl delete clusterrole -n kube-system privileged-role
# ServiceAccount
kubectl delete sa -n kube-system metrics-server-account
```

The fire is out (for now). But clearly we need more robust security to keep the bad guys out. How can we restrict access to ensure that only trusted users can interact with the cluster control plane?

Let's enable [Entra ID integration](https://learn.microsoft.com/en-us/azure/aks/enable-authentication-microsoft-entra-id) and disable local administrative accounts. This way only users who are authenticated by our Entra tenant will have access to the cluster and we can control what those user can do by managing group membership in Entra.

First we will want to creat a group in Entra that contains all of the cluster admins (and make sure our account is in it so we don't get lockd out):
```console
GROUP_NAME=$(echo AKSAdmins$RANDOM)
ADMIN_GROUP=$(az ad group create --display-name "$GROUP_NAME" --mail-nickname "$GROUP_NAME" --query id -o tsv)
az ad group member add --group "$GROUP_NAME" --member-id $(az ad signed-in-user show --query id -o tsv)
```

Now let's enable EntraID integration and disable local accounts: 
```console
# Enable EntraID authz/authn
az aks update --resource-group $RESOURCE_GROUP --name $AKS_NAME \
  --enable-aad \
  --aad-admin-group-object-ids $ADMIN_GROUP \
  --disable-local-accounts
```

Finally, we need to rotate the cluster certificates in order to invalidate the existing leaked admin credentials. This will require us to authenticate against EntraID for all future cluster administration:
```console
az aks rotate-certs --resource-group $RESOURCE_GROUP --name $AKS_NAME
```

We can verify that we have lost access to cluster by running any kubectl command:
```console
kubectl get pods
```

To reconnect to the cluster we will need to fetch new credentials, this time backed by Entra:
```console
az aks get-credentials --resource-group $RESOURCE_GROUP --name $AKS_NAME
kubectl get pods
```

Now, when we try to interact with the cluster, we are prompted to login with our Entra credentials.

!!! note "Note"
    If you are running this lab inside of a managed tenant with strict conditional access policies you may need to run `az login && kubelogin convert-kubeconfig -l azurecli` before connecting to the cluster.

Confident that the cluster is now running in "Fort Knox" mode, __Blue__ decides to call it a night and head back to bed.

!!! note "Note"
    Another layer of security that would be a good idea to investigate here is [Azure Policy](https://learn.microsoft.com/en-us/azure/aks/use-azure-policy).