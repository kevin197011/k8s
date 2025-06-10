# frozen_string_literal: true

# Copyright (c) 2025 kk
#
# This software is released under the MIT License.
# https://opensource.org/licenses/MIT

require 'time'
require 'rake'

task default: %w[push]

desc 'Push changes to git repository'
task :push do
  system 'git add .'
  system "git commit -m 'Update #{Time.now}.'"
  # system 'git pull'
  system 'git push origin main'
end

desc 'Run Kubernetes cluster using kind and install kubectl, kubectx, helm'
task :run do
  # check if kind is installed
  unless File.exist?('/usr/local/bin/kind') && File.exist?('/usr/local/bin/kubectl') && File.exist?('/usr/local/bin/kubectx') && File.exist?('/usr/local/bin/helm')
    Rake::Task['install'].invoke
  end

  system 'kind create cluster --config ./kind/k8s-multi-nodes-cluster.yaml --name k8s'
  system 'kubectl cluster-info --context kind-k8s'
  system 'kubectl get nodes'
end

task :install do
  kind_version = `curl -s https://api.github.com/repos/kubernetes-sigs/kind/releases/latest | grep -Po '"tag_name": "v\K[^"]*'`.strip
  kind_url = "https://github.com/kubernetes-sigs/kind/releases/download/v#{kind_version}/kind-linux-amd64"
  system "curl -Lo /usr/local/bin/kind #{kind_url}"
  system 'chmod +x /usr/local/bin/kind'

  kubectl_version = `curl -L -s https://dl.k8s.io/release/stable.txt`.strip
  kubectl_url = "https://dl.k8s.io/release/#{kubectl_version}/bin/linux/amd64/kubectl"
  system "curl -Lo /usr/local/bin/kubectl #{kubectl_url}"
  system 'chmod +x /usr/local/bin/kubectl'

  system 'curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash'

  kubectx_version = `curl -s https://api.github.com/repos/ahmetb/kubectx/releases/latest | grep -Po '"tag_name": "v\K[^"]*'`.strip
  kubectx_url = "https://github.com/ahmetb/kubectx/releases/download/v#{kubectx_version}/kubectx"
  system "curl -Lo /usr/local/bin/kubectx #{kubectx_url}"
  system 'chmod +x /usr/local/bin/kubectx'
end
