MAKEFLAGS += --no-print-directory
SHELL := /bin/bash

CILIUM_SRC ?= $(HOME)/Desktop/cilium
CILIUM_HELM_CHART ?= $(CILIUM_SRC)/install/kubernetes/cilium
CILIUM_AGENT_LABEL ?= app.kubernetes.io/name=cilium-agent
CILIUM_OPERATOR_LABEL ?= app.kubernetes.io/name=cilium-operator

.ONESHELL:

.PHONY: install

deploy:
	set -e
	kind create cluster --config ./cluster.yaml
	-kubectl taint nodes cilium-testing-control-plane node-role.kubernetes.io/control-plane:NoSchedule-
	make create-ipsec-key

destroy:
	kind delete cluster --name cilium-testing

install:
	set -e
	export DOCKER_IMAGE_TAG="local"
	cd $(CILIUM_SRC)
	make docker-operator-generic-image
	make dev-docker-image
	cd -

	kind load --name cilium-testing docker-image quay.io/cilium/operator-generic:local
	kind load --name cilium-testing docker-image quay.io/cilium/cilium-dev:local
	helm -n kube-system install cilium $(CILIUM_HELM_CHART) -f values.yaml

bounce:
	set -e
	export DOCKER_IMAGE_TAG="local"
	cd $(CILIUM_SRC)
	make docker-operator-generic-image
	make dev-docker-image
	kind load --name cilium-testing docker-image quay.io/cilium/operator-generic:local
	kind load --name cilium-testing docker-image quay.io/cilium/cilium-dev:local

install-debug:
	set -e
	export DOCKER_IMAGE_TAG="local"
	export NOSTRIP=1
	export NOOPT=1
	export DEBUG_HOLD=true
	cd $(CILIUM_SRC)
	make docker-operator-generic-image
	make dev-docker-image-debug
	cd -

	kind load --name cilium-testing docker-image quay.io/cilium/operator-generic:local
	kind load --name cilium-testing docker-image quay.io/cilium/cilium-dev:local
	helm -n kube-system install cilium $(CILIUM_HELM_CHART) -f values.yaml


bounce-debug:
	set -e
	export DOCKER_IMAGE_TAG="local"
	export NOSTRIP=1
	export NOOPT=1
	export DEBUG_HOLD=true
	cd $(CILIUM_SRC)
	make docker-operator-generic-image
	make dev-docker-image-debug
	kind load --name cilium-testing docker-image quay.io/cilium/operator-generic:local
	kind load --name cilium-testing docker-image quay.io/cilium/cilium-dev:local

bounce-agents:
	kubectl --namespace=kube-system delete pod -l $(CILIUM_AGENT_LABEL)

bounce-operator:
	kubectl --namespace=kube-system delete pod -l $(CILIUM_OPERATOR_LABEL)

update-values:
	helm -n kube-system upgrade cilium $(CILIUM_HELM_CHART) -f values.yaml

echo-service:
	kubectl apply -f "./migrations-svc-deployment.yaml"

reinstall:
	set -e
	helm -n kube-system uninstall cilium
	helm -n kube-system install cilium $(CILIUM_HELM_CHART) -f values.yaml

create-ipsec-key:
	kubectl create -n kube-system secret generic cilium-ipsec-keys \
		--from-literal=keys="3+ rfc4106(gcm(aes)) $(shell dd if=/dev/urandom count=20 bs=1 2> /dev/null | xxd -p -c 64) 128"

get-ipsec-key:
	@kubectl get secret cilium-ipsec-keys -n kube-system -o jsonpath='{.data.keys}' | base64 -d
	@echo 

delete-ipsec-key:
	kubectl delete secret -n kube-system cilium-ipsec-keys

rotate-key:
	set -e
	KEYID=$(shell kubectl get secret -n kube-system cilium-ipsec-keys -o go-template --template={{.data.keys}} | base64 -d | grep -oP "^\d+")
	if [[ $${KEYID} -ge 15 ]]; then KEYID=0; fi
	key="rfc4106(gcm(aes)) $(shell dd if=/dev/urandom count=20 bs=1 2> /dev/null | xxd -p -c 64) 128"
	data="{\"stringData\":{\"keys\":\"$$((($${KEYID}+1)))+ $${key}\"}}"
	kubectl patch secret -n kube-system cilium-ipsec-keys -p="$${data}" -v=1
	echo "IPSec key successfully updated"
	make get-ipsec-key
