# The calls are coming from inside the container! Scenario 3 Defense

We've gotten paged.  AGAIN!  Let's check the cluster.

Any unwanted open ports?  `kubectl get service -A` 

Any unwanted pods? `kubectl get pods -A`

Where's the spike coming from? `kubectl top node`

What pods?  `kubectl top pod`

Wait...what is this `bitcoin-injector`?  It's showing as completed, so it's not running anymore, so it can't be causing the problem. Did the hackers get sloppy and leave something behind?  We'll check this out later because we need to stop the bleeding.

Why is our app running so hot?
```
kubectl get pods -n dev
POD=$(kubectl get pods -n dev -l=app=insecure-app -o json | jq '.items[0].metadata.name' -r)
echo $POD
kubectl exec -it $POD -n dev -- ps -ef
```

There's a foreign workload `moneymoneymoney` running in our app!  How did this get in here?!

Let's delete the pod: `kubectl delete pod --force --grace-period=0 $POD`

But just to be sure, let's verify that process is gone.

```
POD=$(kubectl get pods -n dev -l=app=insecure-app -o json | jq '.items[0].metadata.name' -r)
kubectl exec -it $POD -n dev -- ps -ef
```

This...is not good.  The miner is running inside the app and restarting the app also restarted the miner.  Is our app infected?!  How could this have happened?!

Let's go re-investigate that `bitcoin-injector` pod:
```
kubectl describe pods -n dev bitcoin-injector-xxxxx
# Looks like it was started as Job/bitcoin-injector

kubectl logs -n dev bitcoin-injector-xxxxx
# Looks like the output of a Docker build command
```

It seems like they got our container registry credentials and then used that to pull our image and then push a new one with the exact same name!  But how did they get that?

Let's look at the Log Analytics Audit Logs:
```kql
AKSAuditAdmin
| where RequestUri startswith "/apis/batch"
    and Verb == "create" 
| project ObjectRef, User, SourceIps, UserAgent, TimeGenerated
```

It appears that the request came from `insecure-app`.  But how?

Looking at the source code, it appears there's an `/admin` page which Frank added this to the code years ago and was fired after that "inappropriate use of company resources" issue.

And the attackers were able to use this really permissive Service Account role binding to get escalated privledges to the cluster.

We need a plan of defense:

* Delete the infected image
* Stop using container registry admin credentials
* Enable Defender for Containers 
* Downgrade/remove SA permissions (change verbs from * to GET)
* Open Issue to tell developer to remove /admin page
* Re-build and deploy image

## Delete the infected image

We'll have the developers re-build each of the containers and push to our ACR; however, since the infected insecure-app and bitcoinero images are still on the node, we need to make sure it's removed.  To prevent another container from using old images, let's install the [AKS Image Cleaner](https://learn.microsoft.com/en-us/azure/aks/image-cleaner).  This will prevent them re-installing the old insecure-app or bitcoinero images.

```
az aks update --name $AKS_NAME --resource-group $RESOURCE_GROUP  --enable-image-cleaner
```

## Stop using container registry admin credentials

Instead of providing the ACR admin credentials, let's [Attach the ACR to the cluster](https://learn.microsoft.com/en-us/azure/aks/cluster-container-registry-integration?tabs=azure-cli#attach-an-acr-to-an-existing-aks-cluster).

```
kubectl delete -n dev secrets/acr-secret
az aks update --name $AKS_NAME --resource-group $RESOURCE_GROUP --attach-acr $ACR_NAME
```

## Enable Defender for Containers

Now that you've fixed the permissions on pulling images from ACR, you want to get alerted in case anything else gets added to our registry or the cluster.  

For this, we'll enable [Azure Defender for Containers](https://learn.microsoft.com/en-us/azure/defender-for-cloud/defender-for-containers-enable)

The image injection would have been detected with [Binary drift detection](https://learn.microsoft.com/en-us/azure/defender-for-cloud/binary-drift-detection).  

```
The binary drift detection feature alerts you when there's a difference between the workload that came from the image, and the workload running in the container. It alerts you about potential security threats by detecting unauthorized external processes within containers.
```

## Fix container permissions

Our container was given a cluster role that was too permissive.

https://github.com/azure/aks-ctf/blob/main/workshop/manifests/omnibus.yml#L7-L14

We got confirmation from the developer that the app needs to be able to see (but not modify) other pods in the namespace.  Let's update that role to be less permissive:

```
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: insecure-app-role
rules:
- apiGroups: [""] # "" indicates the core API group
  resources: ["pods"]
  verbs: ["get", "watch", "list"]
```
