---
title: "Free Kubernetes Clusters for Development and Learning"
date: 2020-01-26T12:55:31-08:00
tags: ["Kubernetes", "Katacoda", "KinD", "Docker", "Minikube"]
---

When we are either developing on Kubernetes or learning Kubernetes, we need access to free Kubernetes clusters. Most of these options are not even close to the production environment but they work for most of the scenarios.

In this post I'll show you 6 possible Kubernetes cluster that you can use for some development and Kubernetes learning. I will divide these clusters in 2 groups:

**Online clusters**: These are clusters that are available on internet for free with some limitations but also some good advantage versus the local clusters such as having multiple nodes.

1. [Katacoda](https://www.katacoda.com/courses/kubernetes/playground) 
2. [Play with Kubernetes](https://labs.play-with-k8s.com) 

**Local clusters**: These are the most common and known options. The main weakness is the performance and that they only offer one node: the master node.

1. Minikube 
2. Kubernetes on Docker Desktop 
3. KinD 

## Katacoda

[Katacoda](https://www.katacoda.com) is an interactive learning platform. It offers multiple learning platforms such as Kubernetes, Docker, OpenShift, Hashicorp tools, Jenkins, Ansible, Machine Learning, Go and many others.

You can learn Kubernetes and many other services following the published trainings. You can also create your own trainings or sessions and publish them on Katacoda from your GitHub repository. 

One of the learning platforms is a Kubernetes playground with two nodes (master and worker), to open it go to https://www.katacoda.com/courses/kubernetes/playground, then click on Start Scenario and execute in the `master` node the script `launch.sh`. When the script ends, the cluster is ready to be used. It's possible to open extra terminals and open a browser to the exposed services. To terminate the session, click on `Continue`.

This playground has only a 1x1 cluster but it's possible to have cluster with multiple masters and workers. It's also possible to have multiple hosts and build a custom Kubernetes cluster with `kubeadm`.

With Katacoda you can expose services and access them with a new tab to view the host on the exposed port. Regarding Persistent Volumes you can create local PV's on the hosts and it's possible to simulate NFS or provide storage in S3 with some Docker containers.

Let's try some examples starting the [Kubernetes Playground](https://www.katacoda.com/courses/kubernetes/playground) scenario and executing the following commands:

```bash
kubectl run www --image=nginx --restart=Never
kubectl expose po www --type=NodePort --port=80
kubectl get po,svc www
curl $(kubectl get svc www -o jsonpath='{ .spec.clusterIP }')
# Print the nodePort exposing the service
kubectl get svc www -o jsonpath='{ .spec.ports[*].nodePort }{"\n"}'
```

The last command prints the node port exposing the service (i.e. `31870`), highlight and copy the port, click on the `+` sign next to the `Terminal Host 1` tab to select `Select port to view on Host 1`, paste the copied port and click on `Display Port` button. You'll see the web page published by Nginx in the pod/service `www`.

## Play with Kubernetes

Play with Kubernetes is a lab provided by Docker and it's another playground. They also offer a Kubernetes training for beginners but it's not like Katacoda which offer more topics and the community can publish their own trainings.

To access the playground, go to http://labs.play-with-k8s.com/ and click on Start after login in. Then create as many instances as you need.

Initialize the cluster from the master (the first node) using `kubeadm` executing the first printed instruction. When `kubeadm init` finishes it prints a `kubeadm join` instruction, execute it in the following worker nodes.

When you are done, click on `Close Session`.

Play with Kubernetes is not bad but Katacoda is simpler when it's time to create the cluster and more reliable, while using Play with Kubernetes I lost the session and lost all the job done. Also, Play with Kubernetes has a session that expire in 4 hrs.

## Minikube

Minikube was the first local Kubernetes cluster for developers, it starts a single node Kubernetes cluster on a VM. Minikube works on Linux, MacOS and Windows.

To install Minikube on Mac, execute `brew install minikube`, for Linux or Windows go to https://minikube.sigs.k8s.io/docs/start/

To start a Kubernetes cluster, execute: `minikube start` and to terminate it, execute: `minikube stop`.

Minikube offer some commands to make your life easier such as:

* `minikube dashboard` to open the Kubernetes Dashboard
* `minikube service NAME` to open the exposed service NAME in a browser.

Example:

```bash
# Terminal 1
minikube start
minikube dashboard
```

```bash
# Terminal 2
kubectl create deployment nginx --image=nginx
kubectl expose deployment nginx --type=NodePort --port=80
minikube service nginx
minikube stop
```

## Kubernetes on Docker Desktop

The current version of Docker Desktop (MacOS and Windows) is bundled with Kubernetes. To start it go to the Docker preferences > Kubernetes and Enable Kubernetes. It will take some time the first time but then you'll have Kubernetes on your machine for free.

The advantage of Kubernetes on Docker Desktop over Minikube is that most of us already have Docker to build our containers, so that means that we already have Kubernetes and there is no need to install something else. The disadvantage is that there is no Docker Desktop on Linux, so our only option there is Minikube. The other main disadvantage is that Minikube usually runs the latest version of Kubernetes, Kubernetes on Docker does not.

Something important with Docker Desktop is to select the correct directories for local volumes. These should be in the list of shared files. Go to Preferences > File Sharing and add the directories you would like to use for local volumes.

Example:

```bash
kubectl create deployment nginx --image=nginx
kubectl expose deployment nginx --type=NodePort --port=80
kubectl get services -o wide
PORT=$(kubectl get services nginx -o wide | grep nginx | awk '{print $5}' | cut -f2 -d: | cut -f1 -d/)
open http://localhost:$PORT
```

## KinD or Kubernetes in Docker

KinD is kind of new but it's an amazing and lighter Kubernetes cluster. It's often used in Travis to test your Microservices on Docker.

According to the authors, KinD cannot be used in production, it was not made to provide a stable Kubernetes cluster but it's incredible for development, testing and learning.

If you have Go in your system, it can be installed with `GO111MODULE="on" go get sigs.k8s.io/kind`. If not, go to https://github.com/kubernetes-sigs/kind and follow the installation instructions for your OS.

The common workflow to use KinD is:

```bash
kind create cluster
kind get clusters
export KUBECONFIG="$(kind get kubeconfig-path)"

kind delete cluster
```

An example to deploy and expose a Nginx server:

```bash
kubectl create deployment nginx --image=nginx
kubectl expose deployment nginx --type=NodePort --port=80
kubectl port-forward service/nginx 8080:80 &
open http://localhost:8080
```

## Other options

These are not the only options, there are more such as [MicroK8s](https://github.com/ubuntu/microk8s), [Kube-spawn](https://github.com/kinvolk/kube-spawn) and maybe others.

You can also create your own Kubernetes cluster using Vagrant and kubeadm, the project [KoV](https://github.com/johandry/KoV) create a MxW cluster using a single Vagrant file. You can use it or copy it to your needs, and there are many other similar projects in GitHub.

## Conclusion

If you need to publish a training or a post about Kubernetes, my first option would be to use Katacoda. It's also useful if you don't have your laptop near or using a mobile device like an iPad or Chrome.

If you are using Windows or Mac, my first option would be to use Docker Desktop. You also need Docker to work with your images and containers, so you already have Kubernetes and it's very stable for me so far.

If you want something to run on any OS (Mac, Windows and Linux), my first option would be KinD, then MiniKube.

To learn how to create a cluster from scratch, I'd recommend using Vagrant with `kubeadm`.

These are my suggestions for a free Kubernetes cluster but these clusters may not be similar to your production environment, so after finish your development and some simple tests, my recommendation is to test your code in an environment similar to your production environment which may be a Kubernetes cluster on some cloud (i.e. EKS, GKS, AKS, PKS, etc...) or bare-metal.
