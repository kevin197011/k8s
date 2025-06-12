# frozen_string_literal: true

# Copyright (c) 2025 kk
#
# This software is released under the MIT License.
# https://opensource.org/licenses/MIT

require 'time'
require 'rake'
# require 'open3'
require 'net/http'
require 'uri'
require 'json'
require 'fileutils'
require 'git'

BIN_PATH = '/usr/local/bin'

TOOLS = {
  kind: "#{BIN_PATH}/kind",
  kubectl: "#{BIN_PATH}/kubectl",
  kubectx: "#{BIN_PATH}/kubectx",
  helm: "#{BIN_PATH}/helm"
}

task default: %w[fmt push]

desc 'Push changes to git repository'
task :push do
  puts '🔧 Git Commit and Push...'
  git = Git.open('.')
  git.add(all: true)
  git.commit("Update #{Time.now.strftime('%Y-%m-%d %H:%M:%S')}")
  git.push('origin', 'main')
end

desc 'Run Kubernetes cluster using kind'
task :run do
  unless tools_installed?
    puts '🔍 One or more tools are missing. Installing required tools...'
    Rake::Task[:install].invoke
  end

  puts '🚀 Starting kind Kubernetes cluster...'
  system 'kind create cluster --config ./kind/k8s-multi-nodes-cluster.yaml --name k8s'
  system 'kubectl cluster-info --context kind-k8s'
  system 'kubectl get nodes'
end

desc 'Install kind, kubectl, kubectx, helm'
task :install do
  install_kind
  install_kubectl
  install_helm
  install_kubectx
end

desc 'Check rubocop'
task :fmt do
  puts '🔍 Running RuboCop...'
  system 'rubocop --display-cop-names --force-exclusion'
end


# --- Helper Functions ---

def tools_installed?
  TOOLS.values.all? { |path| File.exist?(path) }
end

def install_kind
  puts '📦 Installing kind...'
  version = latest_github_release('kubernetes-sigs/kind')
  url = "https://github.com/kubernetes-sigs/kind/releases/download/v#{version}/kind-linux-amd64"
  download_to(url, TOOLS[:kind])
end

def install_kubectl
  puts '📦 Installing kubectl...'
  version = `curl -sL https://dl.k8s.io/release/stable.txt`.strip
  url = "https://dl.k8s.io/release/#{version}/bin/linux/amd64/kubectl"
  download_to(url, TOOLS[:kubectl])
end

def install_helm
  puts '📦 Installing helm...'
  script_url = 'https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3'
  response = Net::HTTP.get(URI(script_url))
  temp_file = '/tmp/get_helm.sh'
  File.write(temp_file, response)
  FileUtils.chmod('+x', temp_file)
  system(temp_file)
  FileUtils.rm(temp_file)
end

def install_kubectx
  puts '📦 Installing kubectx...'
  version = latest_github_release('ahmetb/kubectx')
  url = "https://github.com/ahmetb/kubectx/releases/download/v#{version}/kubectx"
  download_to(url, TOOLS[:kubectx])
end

def latest_github_release(repo)
  uri = URI("https://api.github.com/repos/#{repo}/releases/latest")
  response = Net::HTTP.get(uri)
  data = JSON.parse(response)
  version = data['tag_name']&.delete_prefix('v')
  abort "❌ Failed to fetch latest version for #{repo}" if version.nil?
  version
end

def download_to(url, target_path)
  puts "⬇️ Downloading from #{url}..."
  uri = URI(url)
  response = Net::HTTP.get_response(uri)

  if response.is_a?(Net::HTTPSuccess)
    File.binwrite(target_path, response.body)
    FileUtils.chmod('+x', target_path)
  else
    abort "❌ Failed to download from #{url}"
  end
end
