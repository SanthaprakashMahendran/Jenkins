#!/bin/bash

aws cloudformation update-termination-protection \
  --stack-name eksctl-ci-eks-cluster-addon-iamserviceaccount-kube-system-aws-load-balancer-controller \
  --no-enable-termination-protection \
  --region us-east-1

aws cloudformation delete-stack   --stack-name eksctl-ci-eks-cluster-addon-iamserviceaccount-kube-system-aws-load-balancer-controller   --region us-east-1

sleep 20

eksctl create iamserviceaccount \
  --cluster ci-eks-cluster \
  --namespace kube-system \
  --name aws-load-balancer-controller \
  --attach-policy-arn arn:aws:iam::392746353565:policy/AWSLoadBalancerControllerIAMPolicy \
  --region us-east-1 \
  --approve 

eksctl create iamserviceaccount \
  --cluster ci-eks-cluster \
  --namespace kube-system \
  --name aws-load-balancer-controller \
  --attach-policy-arn arn:aws:iam::392746353565:policy/AWSLoadBalancerControllerIAMPolicy \
  --region us-east-1 \
  --approve \
  --override-existing-serviceaccounts

  helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=ci-eks-cluster \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller

#### EFS ######


aws cloudformation update-termination-protection   --stack-name eksctl-ci-eks-cluster-addon-iamserviceaccount-kube-system-efs-csi-controller-sa   --no-enable-termination-protection   --region us-east-1

aws cloudformation delete-stack   --stack-name eksctl-ci-eks-cluster-addon-iamserviceaccount-kube-system-efs-csi-controller-sa   --region us-east-1

sleep 20

eksctl create iamserviceaccount \
  --cluster ci-eks-cluster \
  --namespace kube-system \
  --name efs-csi-controller-sa \
  --attach-policy-arn arn:aws:iam::392746353565:policy/AmazonEKS_EFS_CSI_Driver_Policy \
  --region us-east-1 \
  --approve

eksctl create iamserviceaccount \
  --cluster ci-eks-cluster \
  --namespace kube-system \
  --name efs-csi-controller-sa \
  --attach-policy-arn arn:aws:iam::392746353565:policy/AmazonEKS_EFS_CSI_Driver_Policy \
  --region us-east-1 \
  --approve \
  --override-existing-serviceaccounts

helm install aws-efs-csi-driver \
  aws-efs-csi-driver/aws-efs-csi-driver \
  -n kube-system \
  --set controller.serviceAccount.create=false \
  --set controller.serviceAccount.name=efs-csi-controller-sa


kubectl get pods -n kube-system | grep -E "load|efs"

