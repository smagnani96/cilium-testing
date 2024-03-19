CILIUM_SRC ?= /home/louis/git/gopath/src/github.com/cilium/cilium-enterprise

.PHONY: install

deploy:
	kind create cluster --config ./cluster.yaml
	-kubectl taint nodes cilium-testing-control-plane node-role.kubernetes.io/control-plane:NoSchedule- node-role.kubernetes.io/master:NoSchedule- 

destroy:
	kind delete cluster --name cilium-testing

.ONESHELL:
install:
	export DOCKER_IMAGE_TAG="local"
	cd $(CILIUM_SRC)
	make docker-operator-generic-image
	make dev-docker-image
	cd -

	kind load --name cilium-testing docker-image quay.io/cilium/operator-generic:local
	kind load --name cilium-testing docker-image quay.io/cilium/cilium-dev:local
	helm -n kube-system install cilium chart -f values.yaml

.ONESHELL:
bounce:
	export DOCKER_IMAGE_TAG="local"
	cd $(CILIUM_SRC)
	make docker-operator-generic-image
	make dev-docker-image
	kind load --name cilium-testing docker-image quay.io/cilium/operator-generic:local
	kind load --name cilium-testing docker-image quay.io/cilium/cilium-dev:local

.ONESHELL:
install-debug:
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
	helm -n kube-system install cilium chart -f values.yaml

.ONESHELL:
bounce-debug:
	export DOCKER_IMAGE_TAG="local"
	export NOSTRIP=1
	export NOOPT=1
	export DEBUG_HOLD=true
	cd $(CILIUM_SRC)
	make docker-operator-generic-image
	make dev-docker-image-debug
	kind load --name cilium-testing docker-image quay.io/cilium/operator-generic:local
	kind load --name cilium-testing docker-image quay.io/cilium/cilium-dev:local

update-values:
	helm -n kube-system upgrade cilium ./chart -f values.yaml

echo-service:
	kubectl apply -f "./migrations-svc-deployment.yaml"

reinstall:
	helm -n kube-system uninstall cilium
	helm -n kube-system install cilium chart -f values.yaml
