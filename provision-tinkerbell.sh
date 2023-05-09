#!/bin/bash
set -euxo pipefail

boots_ip="${1:-10.11.0.60}"
stack_ip="${2:-10.11.0.61}"
trusted_proxies="$(kubectl get nodes -o jsonpath='{.items[*].spec.podCIDR}' | tr ' ' ',')"
t1_mac='08:00:27:00:00:46'
t1_ip='10.11.0.70'
t1_gw='10.11.0.1'

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

# install tinkerbell.
# see https://docs.tinkerbell.org/hardware-data/
helm dependency build
if [ "$(helm list -n tink-system -o json --filter stack | jq length)" != '0' ]; then
  helm uninstall -n tink-system --wait stack
fi
if kubectl -n tink-system get workflow t1 >/dev/null 2>&1; then
  kubectl -n tink-system delete workflow t1
fi
if kubectl -n tink-system get hardware t1 >/dev/null 2>&1; then
  kubectl -n tink-system delete hardware t1
fi
if kubectl -n tink-system get template t1 >/dev/null 2>&1; then
  kubectl -n tink-system delete template hello
fi
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

# install the template.
kubectl apply -n tink-system -f - <<EOF
---
apiVersion: tinkerbell.org/v1alpha1
kind: Template
metadata:
  name: hello
spec:
  data: |
    version: "0.1"
    name: hello
    global_timeout: 1800
    tasks:
      - name: hello
        worker: "{{.device_1}}"
        volumes:
          - /dev:/dev
          - /dev/console:/dev/console
          - /lib/firmware:/lib/firmware:ro
        actions:
          - name: hello
            image: docker.io/library/busybox:1.33
            timeout: 800
            pid: host
            command:
              - sh
              - -c
              - |
                cat >/dev/tty0 <<EOF
                \$(env | sort)
                \$(date)


                  HHHHHHHHH     HHHHHHHHH                   lllllll lllllll
                  H:::::::H     H:::::::H                   l:::::l l:::::l
                  H:::::::H     H:::::::H                   l:::::l l:::::l
                  HH::::::H     H::::::HH                   l:::::l l:::::l
                    H:::::H     H:::::H      eeeeeeeeeeee    l::::l  l::::l    ooooooooooo
                    H:::::H     H:::::H    ee::::::::::::ee  l::::l  l::::l  oo:::::::::::oo
                    H::::::HHHHH::::::H   e::::::eeeee:::::eel::::l  l::::l o:::::::::::::::o
                    H:::::::::::::::::H  e::::::e     e:::::el::::l  l::::l o:::::ooooo:::::o
                    H:::::::::::::::::H  e:::::::eeeee::::::el::::l  l::::l o::::o     o::::o
                    H::::::HHHHH::::::H  e:::::::::::::::::e l::::l  l::::l o::::o     o::::o
                    H:::::H     H:::::H  e::::::eeeeeeeeeee  l::::l  l::::l o::::o     o::::o
                    H:::::H     H:::::H  e:::::::e           l::::l  l::::l o::::o     o::::o
                  HH::::::H     H::::::HHe::::::::e         l::::::ll::::::lo:::::ooooo:::::o
                  H:::::::H     H:::::::H e::::::::eeeeeeee l::::::ll::::::lo:::::::::::::::o
                  H:::::::H     H:::::::H  ee:::::::::::::e l::::::ll::::::l oo:::::::::::oo
                  HHHHHHHHH     HHHHHHHHH    eeeeeeeeeeeeee llllllllllllllll   ooooooooooo


                                               A  C  T  I  O  N
                EOF
                echo 'Sleeping 5m...' >/dev/tty0
                sleep 300
                echo 'Exiting...' >/dev/tty0
EOF

# install the hardware and workflow.
kubectl apply -n tink-system -f - <<EOF
---
apiVersion: tinkerbell.org/v1alpha1
kind: Hardware
metadata:
  name: t1
spec:
  metadata:
    instance:
      hostname: t1
      id: $t1_mac
      # TODO create a boots issue to make operating_system optional.
      operating_system: {}
  interfaces:
    - dhcp:
        hostname: t1
        mac: $t1_mac
        ip:
          address: $t1_ip
          gateway: $t1_gw
          netmask: 255.255.255.0
        name_servers:
         - $t1_gw
        #time_servers:
        #  - $t1_gw
        lease_time: 300
        arch: x86_64
        uefi: false
      netboot:
        allowPXE: true
        allowWorkflow: true
---
apiVersion: tinkerbell.org/v1alpha1
kind: Workflow
metadata:
  name: t1
spec:
  templateRef: hello
  hardwareRef: t1
  hardwareMap:
    device_1: $t1_mac
EOF
