.PHONY: pull push create

all: push

pull:
	git pull

push:
	git add .
	git commit -m "Update."
	git pull
	git push origin master

create:
	kind create cluster --config ./lab/k8s-multi-nodes-cluster.yaml --name k8s
	kubectl cluster-info --context kind-k8s
