CILIUM_SRC ?= /home/louis/git/gopath/src/github.com/cilium/cilium

.PHONY: install

deploy:
	kind create cluster --config ./cluster.yaml

down:
	kind delete cluster --name cilium-testing

.ONESHELL:
install:
	cd $(CILIUM_SRC)
	make docker-operator-generic-image
	make dev-docker-image
	cd -

	kind load --name cilium-testing docker-image quay.io/cilium/operator-generic:latest
	kind load --name cilium-testing docker-image quay.io/cilium/cilium-dev:latest
	helm -n kube-system install cilium chart -f values.yaml

.ONESHELL:
bounce:
	cd $(CILIUM_SRC)
	make docker-operator-generic-image
	make dev-docker-image
	kind load --name cilium-testing docker-image quay.io/cilium/operator-generic:latest
	kind load --name cilium-testing docker-image quay.io/cilium/cilium-dev:latest

echo-service:
	kubectl apply -f "./migrations-svc-deployment.yaml"

reinstall:
	helm -n kube-system uninstall cilium
	helm -n kube-system install cilium chart -f values.yaml
