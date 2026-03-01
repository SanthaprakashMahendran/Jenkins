# Jenkins on EKS with EFS and ALB

This repo deploys Jenkins on Amazon EKS with persistent storage on EFS and access via an Application Load Balancer (ALB).

---

## Prerequisites

- AWS CLI configured with sufficient permissions
- `eksctl` and `kubectl` installed
- `helm` 3.x installed
- An EKS cluster named `ci-eks-cluster` in `us-east-1`
- Cluster nodes labeled (e.g. `dedicated=controller` for Jenkins, `dedicated=runner` for agents)

---

## Setup Order

### 1) Create infrastructure

- Provision the EKS cluster (e.g. with `eksctl` or Terraform).
- Ensure the cluster has:
  - Private subnets (for EFS mount targets)
  - A security group for the cluster nodes (needed as EFS inbound source)

### 2) Create EFS file system

- In AWS Console: **EFS → Create file system**, or use AWS CLI/CloudFormation.
- Choose the same VPC as the EKS cluster.

### 3) Security group for EFS

- Create a security group for EFS (e.g. `efs-sg`).
- **Inbound rule:**
  - Type: **NFS** (port 2049)
  - Source: **Cluster nodes security group** (so EKS nodes can mount EFS)

### 4) EFS mount targets

- Add **mount targets** for the EFS file system in **private subnets** of the cluster VPC.
- Attach the **EFS security group** from step 3 to each mount target.

### 5) Configure EFS CSI driver

Add Helm repo and create the IAM service account, then install the driver:

```bash
helm repo add aws-efs-csi-driver https://kubernetes-sigs.github.io/aws-efs-csi-driver/
helm repo update
```

```bash
eksctl create iamserviceaccount \
  --cluster ci-eks-cluster \
  --namespace kube-system \
  --name efs-csi-controller-sa \
  --attach-policy-arn arn:aws:iam::392746353565:policy/AmazonEKS_EFS_CSI_Driver_Policy \
  --region us-east-1 \
  --approve \
  --override-existing-serviceaccounts
```

```bash
helm install aws-efs-csi-driver \
  aws-efs-csi-driver/aws-efs-csi-driver \
  -n kube-system \
  --set controller.serviceAccount.create=false \
  --set controller.serviceAccount.name=efs-csi-controller-sa
```

### 6) Configure AWS Load Balancer Controller

Add Helm repo and create the IAM service account, then install the controller:

```bash
helm repo add eks https://aws.github.io/eks-charts
helm repo update
```

```bash
eksctl create iamserviceaccount \
  --cluster ci-eks-cluster \
  --namespace kube-system \
  --name aws-load-balancer-controller \
  --attach-policy-arn arn:aws:iam::392746353565:policy/AWSLoadBalancerControllerIAMPolicy \
  --region us-east-1 \
  --approve \
  --override-existing-serviceaccounts
```

```bash
helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=ci-eks-cluster \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller
```

### 7) Label nodes (controller and runner)

- **Controller** (e.g. for Jenkins master):
  ```bash
  kubectl label nodes <node-name> dedicated=controller
  kubectl taint nodes <node-name> dedicated=controller:NoSchedule
  ```
- **Runner** (for agent pods):
  ```bash
  kubectl label nodes <node-name> dedicated=runner
  ```

### 8) Jenkins namespace, ServiceAccount, StorageClass, PVC

Apply in this order:

```bash
kubectl apply -f jenkins-namespace-sa.yaml   # namespace + ServiceAccount
kubectl apply -f gp3-sc.yaml                 # EFS StorageClass (update fileSystemId)
kubectl apply -f pvc.yaml                    # PVC jenkins-efs
```

**Important:** Edit `gp3-sc.yaml` and set `fileSystemId` to your EFS file system ID.

### 9) StatefulSet, Service, Ingress

```bash
kubectl apply -f jenkins-statefulset.yaml
kubectl apply -f jenkins-service.yaml
kubectl apply -f jenkins-ingress.yaml
```

### 10) RBAC

```bash
kubectl apply -f jenkins-rbac.yaml
```

---

## Jenkins Kubernetes Cloud configuration

After Jenkins is running, configure the Kubernetes cloud:

1. **Manage Jenkins → Manage Nodes and Clouds → Configure Clouds → Add a new cloud → Kubernetes.**

2. **Kubernetes configuration:**
   - **Kubernetes URL:** `https://kubernetes.default`
   - **Namespace:** `jenkins`
   - **Credentials:** (leave empty for in-cluster SA)
   - **Jenkins URL:** `http://jenkins.jenkins.svc.cluster.local:8080`
   - **Jenkins tunnel:** `jenkins.jenkins.svc.cluster.local:50000`

3. **Pod Template:**
   - **Containers:**
     - **jnlp**
       - Name: `jnlp`
       - Image: `jenkins/inbound-agent:latest`
       - Command: (leave empty)
     - **kaniko**
       - Name: `kaniko`
       - Image: `gcr.io/kaniko-project/executor:debug`
       - Command: `cat`
       - Allocate pseudo-TTY: enabled
     - **git**
       - Name: `git`
       - Image: `alpine/git:latest`
       - Command: `cat`
       - Allocate pseudo-TTY: enabled
   - **Volumes:** Add **EmptyDir** for workspace volume.

---

## Repository layout

| File | Purpose |
|------|--------|
| `jenkins-namespace-sa.yaml` | Namespace and ServiceAccount for Jenkins (create this if missing) |
| `gp3-sc.yaml` | EFS StorageClass (rename to efs-sc.yaml recommended) |
| `pvc.yaml` | PVC jenkins-efs (ReadWriteMany, EFS) |
| `jenkins-statefulset.yaml` | Jenkins master StatefulSet |
| `jenkins-service.yaml` | ClusterIP Service |
| `jenkins-ingress.yaml` | ALB Ingress (preferred) |
| `ingress.yaml` | Alternate Ingress (deprecated) |
| `jenkins-rbac.yaml` | Role + RoleBinding for Jenkins SA |
| `jenkins-values.yaml` | Helm values reference |
| `install.sh` | EFS CSI + ALB controller script |
| `iam-policy.json` | ALB controller IAM policy |
| `efs-policy.json` | EFS CSI IAM policy |

---

## Quick apply (after EFS/ALB/EFS CSI are ready)

```bash
# Update fileSystemId in gp3-sc.yaml first; create jenkins-namespace-sa.yaml if missing
kubectl apply -f jenkins-namespace-sa.yaml
kubectl apply -f gp3-sc.yaml
kubectl apply -f pvc.yaml
kubectl apply -f jenkins-rbac.yaml
kubectl apply -f jenkins-statefulset.yaml
kubectl apply -f jenkins-service.yaml
kubectl apply -f jenkins-ingress.yaml
```

---

## Access

- **In-cluster:** http://jenkins.jenkins.svc.cluster.local:8080
- **External:** Use the Ingress host (e.g. jenkins.drtest.org) after DNS points to the ALB.
