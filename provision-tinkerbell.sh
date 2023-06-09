#!/bin/bash
set -euxo pipefail

boots_ip="${1:-10.11.0.60}"
stack_ip="${2:-10.11.0.61}"
trusted_proxies="$(kubectl get nodes -o jsonpath='{.items[*].spec.podCIDR}' | tr ' ' ',')"

# when connected to the physical network, these are the used IP addresses:
#   network:                   192.168.1.0/24
#   network gateway:           192.168.1.254
#   manual static IP range:    192.168.1.1-49
#   DHCP IP range:             192.168.1.100-150
#   k8s LoadBalancer IP range: 192.168.1.50-69
#   k8s registry:              192.168.1.4
#   k8s lb:                    192.168.1.30
#   k8s node s1:               192.168.1.31
#   k8s node a1:               192.168.1.41
#   k8s ingress lb:            192.168.1.50
#   k8s tinkerbell boots lb:   192.168.1.60
#   k8s tinkerbell stack lb:   192.168.1.61

# checkout the tinkerbell stack chart.
cd /vagrant/tmp
if [ -d tinkerbell-charts ]; then
  cd tinkerbell-charts
else
  tinkerbell_repository='https://github.com/tinkerbell/charts.git'
  tinkerbell_version='653b6dd9aea530cd1d29e6917a1c80142a209ca5' # 2023-05-15T21:23:39Z
  git clone --no-checkout $tinkerbell_repository tinkerbell-charts
  cd tinkerbell-charts
  git checkout -f $tinkerbell_version
fi
cd tinkerbell/stack

# delete tinkerbell.
bash /vagrant/provision-tinkerbell-t1-delete.sh
if [ "$(helm list -n tink-system -o json --filter stack | jq length)" != '0' ]; then
  helm uninstall -n tink-system --wait stack
fi

# install tinkerbell.
# see https://docs.tinkerbell.org/hardware-data/
helm dependency build
helm upgrade --install \
  stack \
  . \
  --create-namespace \
  --namespace tink-system \
  --wait \
  --values <(cat <<EOF
stack:
  relay:
    # NB this is disabled because with the combination of kvm/libvirt/metallb we end up with two MAC addresses for the stack_ip (because relay creates a macvlan interface with a different MAC address), which prevents the communication between the tink-worker nodes and stack_ip.
    # NB since this is disabled, we have to configure boots to use the host network (see bellow).
    enabled: false
    sourceInterface: eth1
  loadBalancerIP: $stack_ip
  lbClass: ""
  kubevip:
    enabled: false
  hook:
    downloads:
      - url: https://github.com/tinkerbell/hook/releases/download/v0.8.0/hook_x86_64.tar.gz
        sha512sum: 498cccba921c019d4526a2a562bd2d9c8efba709ab760fa9d38bd8de1efeefc8e499c9249af9571aa28a1e371e6c928d5175fa70d5d7addcf3dd388caeff1a45
      - url: https://github.com/tinkerbell/hook/releases/download/v0.8.0/hook_aarch64.tar.gz
        sha512sum: 56e3959722c9ae85aec6c214448108e2dc1d581d2c884ca7a23265c1ae28489589481730fbb941fac8239f6222f9b5bb757987a5238f20194e184ae7e83b6a5b
boots:
  image: quay.io/tinkerbell/boots:v0.8.0
  hostNetwork: true
  service:
    class: ""
  trustedProxies: $trusted_proxies
  remoteIp: $boots_ip
  tinkServer:
    ip: $stack_ip
  osieBase:
    ip: $stack_ip
EOF
)
bash /vagrant/provision-tinkerbell-t1.sh
