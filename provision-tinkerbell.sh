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
  tinkerbell_version='a43cc8b30feb5a7a45b9b5b193a09aec691f55c0' # 2023-05-04T23:05:59Z
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
        sha512sum:
          kernel: 45a83dc747ff05fda09dc7a3b376fca3d82079fbfe99927d9f1c935f2070b5ac6469a41387fefd9e2eeb51062959846900583274a5d02e4131f37162a6167b28  vmlinuz-x86_64
          initramfs: 17ca45318762975464e7abd8f09316d96a658cbbf38c46a47b1ff6f712cffc23d035091883e7e94c21a3b54d8f67c4a982e1fac206449d79f86773ea8c6b7ec6  initramfs-x86_64
      - url: https://github.com/tinkerbell/hook/releases/download/v0.8.0/hook_aarch64.tar.gz
        sha512sum:
          kernel: 80c14e9b2407aabe59b40d7d60e0b96cb2b8812a13d9c278ad1f042aea510d6ff0e4de3c42e39ed049fda871564744cd9f2559d72c3f010331dde62c18af2c77  vmlinuz-aarch64
          initramfs: 5a4eaea8c77c0e574ae3264ddec25a35e758205a75931a61a7911d2b5ac7151e2711a3633b08c05ffc89ab26f81224ea60bb420dab65fd1ccd0b77990db0361a  initramfs-aarch64
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
