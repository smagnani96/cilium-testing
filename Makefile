MAKEFLAGS += --no-print-directory
SHELL := /bin/bash

# change these accordingly
CILIUM_VALUES			?=./cilium-values/values-misc.yaml
CILIUM_SRC 				?= $(HOME)/Desktop/cilium

CILIUM_HELM_CHART 		?= $(CILIUM_SRC)/install/kubernetes/cilium
CILIUM_AGENT_LABEL 		?= app.kubernetes.io/name=cilium-agent
CILIUM_OPERATOR_LABEL 	?= app.kubernetes.io/name=cilium-operator

.ONESHELL:

.PHONY: install

#############
# EKS cluster
# TODOs:
# 1. add image push targets
#############

eks-deploy:
	eksctl create cluster --config-file ./clusters/eks.yml;

eks-destroy:
	CLUSTER_NAME=`yq '.metadata.name' ./clusters/eks.yaml`
	eksctl delete cluster $${CLUSTER_NAME}

eks-vpc-ci-delete:
	kubectl delete ds aws-node -n kube-system

##############
# Kind cluster
##############

kind-deploy:
	set -e
	CLUSTER_NAME=`yq '.name' ./clusters/kind.yaml`
	kind create cluster --config ./clusters/kind.yaml
	-kubectl taint nodes $${CLUSTER_NAME}-control-plane node-role.kubernetes.io/control-plane:NoSchedule-
	make create-ipsec-key

kind-destroy:
	CLUSTER_NAME=`yq '.name' ./clusters/kind.yaml`
	kind delete cluster --name $${CLUSTER_NAME}

kind-load-images:
	CLUSTER_NAME=`yq '.name' ./clusters/kind.yaml`
	kind load --name $${CLUSTER_NAME} docker-image quay.io/cilium/operator-generic:local
	kind load --name $${CLUSTER_NAME} docker-image quay.io/cilium/cilium-dev:local

################
# Cilium targets
################

images:
	set -e
	export DOCKER_IMAGE_TAG="local"
	cd $(CILIUM_SRC)
	make docker-operator-generic-image
	make dev-docker-image
	
images-debug:
	set -e
	export DOCKER_IMAGE_TAG="local"
	export NOSTRIP=1
	export NOOPT=1
	export DEBUG_HOLD=true
	cd $(CILIUM_SRC)
	make docker-operator-generic-image
	make dev-docker-image-debug

install:
	-helm -n kube-system uninstall cilium
	helm -n kube-system install cilium $(CILIUM_HELM_CHART) -f ${CILIUM_VALUES}

update-values:
	helm -n kube-system upgrade cilium $(CILIUM_HELM_CHART) -f ${CILIUM_VALUES}

echo-service:
	kubectl apply -f "./migrations-svc-deployment.yaml"

create-ipsec-key:
	kubectl create -n kube-system secret generic cilium-ipsec-keys \
		--from-literal=keys="3+ rfc4106(gcm(aes)) $(shell dd if=/dev/urandom count=20 bs=1 2> /dev/null | xxd -p -c 64) 128"

get-ipsec-key:
	@kubectl get secret cilium-ipsec-keys -n kube-system -o jsonpath='{.data.keys}' | base64 -d -i
	@echo 

delete-ipsec-key:
	kubectl delete secret -n kube-system cilium-ipsec-keys

grafana:
	kubectl apply -f https://raw.githubusercontent.com/cilium/cilium/1.16.0/examples/kubernetes/addons/prometheus/monitoring-example.yaml
	kubectl wait --for=condition=Ready --selector=app=grafana pod -n cilium-monitoring
	kubectl -n cilium-monitoring port-forward service/grafana --address 0.0.0.0 --address :: 3000:3000

rotate-key:
	set -e
	KEYID=$(shell kubectl get secret -n kube-system cilium-ipsec-keys -o go-template --template={{.data.keys}} | base64 -d | grep -oP "^\d+")
	if [[ $${KEYID} -ge 15 ]]; then KEYID=0; fi
	key="rfc4106(gcm(aes)) $(shell dd if=/dev/urandom count=20 bs=1 2> /dev/null | xxd -p -c 64) 128"
	data="{\"stringData\":{\"keys\":\"$$((($${KEYID}+1)))+ $${key}\"}}"
	kubectl patch secret -n kube-system cilium-ipsec-keys -p="$${data}" -v=1
	echo "IPSec key successfully updated"
	make get-ipsec-key
