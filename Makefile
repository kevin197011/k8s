.PHONY: p l c

all: push

l:
	git pull

p:
	git add .
	git commit -m "Update."
	git pull
	git push origin master

# sudo make create
c:
	test -f /usr/local/bin/kind || (sudo curl -Lo /usr/local/bin/kind https://kind.sigs.k8s.io/dl/v0.9.0/kind-linux-amd64 && sudo chmod +x /usr/local/bin/kind)
	kind create cluster --config ./lab/k8s-multi-nodes-cluster.yaml --name k8s
	kubectl cluster-info --context kind-k8s
