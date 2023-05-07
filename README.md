# About

This is a [tinkerbell](https://github.com/tinkerbell) on [k3s](https://github.com/k3s-io/k3s) kubernetes cluster playground wrapped in a Vagrant environment.

# Usage

Configure the host machine `hosts` file with:

```
10.11.0.4  registry.example.test
10.11.0.10 s.example.test
10.11.0.50 traefik.example.test
10.11.0.50 kubernetes-dashboard.example.test
```

Install the base [Debian 11 (Bullseye) vagrant box](https://github.com/rgl/debian-vagrant).

Optionally, connect the environment to the physical network through the host `br-lan` bridge. The environment assumes that the host bridge was configured as:

```bash
sudo -i
# review the configuration in the files at /etc/netplan and replace them all
# with a single configuration file:
ls -laF /etc/netplan
upstream_interface=eth0
upstream_mac=$(ip link show $upstream_interface | perl -ne '/ether ([^ ]+)/ && print $1')
cat >/etc/netplan/00-config.yaml <<EOF
network:
  version: 2
  renderer: networkd
  ethernets:
    eth0: {}
  bridges:
    br-lan:
      # inherit the MAC address from the enslaved eth0 interface.
      # NB this is required in machines that have intel AMT with shared IP
      #    address to prevent announcing multiple MAC addresses (AMT and OS
      #    eth0) for the same IP address.
      macaddress: $upstream_mac
      #link-local: []
      dhcp4: false
      addresses:
        - 192.168.1.11/24
      routes:
        - to: default
          via: 192.168.1.254
      nameservers:
        addresses:
          - 192.168.1.254
        search:
          - lan
      interfaces:
        - $upstream_interface
EOF
netplan apply
```

And open the `Vagrantfile`, uncomment and edit the block that starts at
`bridge_name` with your specific network details. Also ensure that the
`hosts` file has the used IP addresses.

Since tinkerbell boots DHCP server does not support proxyDHCP you must
ensure that your existing DHCP server does not respond to tinkerbell
controlled machines. In [OpenWRT configure a static lease with `ip=ignore`](https://openwrt.org/docs/guide-user/base-system/dhcp#static_leases),
as, e.g.:

```bash
# see https://openwrt.org/docs/guide-user/base-system/dhcp#static_leases
# see https://openwrt.org/docs/techref/odhcpd#host_section
# see /etc/config/dhcp
# see /tmp/hosts/odhcpd
ssh root@192.168.1.254
#uci delete dhcp.@host[-1]
id="$(uci add dhcp host)"
uci set "dhcp.$id.mac=08:00:27:00:00:46"
# NB even with this configuration, the host is not being ignored. instead, you
#    have to create:
#       * an ipset at http://openwrt.lan/cgi-bin/luci/admin/network/firewall/ipsets
#         * Name: dhcp-ignore
#         * Packet Field Match: src_mac
#         * IPs/Networks/MACs: 08:00:27:00:00:46
#       * an firewall traffic rule at http://openwrt.lan/cgi-bin/luci/admin/network/firewall/rules
#         * Name: Deny-DHCP
#         * Protocol: UDP
#         * Source zone: lan
#         * Destination port: 67
#         * Action: drop
#         * Match device: Inbound device
#         * Device name: br-lan
#         * Restrict to address family: IPv4 only
#         * Use ipset: dhcp-ignore
#       * an firewall traffic rule at http://openwrt.lan/cgi-bin/luci/admin/network/firewall/rules
#         * TODO why is openwrt still letting DHCPv6 in?
#         * Name: Deny-DHCPv6
#         * Protocol: UDP
#         * Source zone: lan
#         * Destination port: 547
#         * Action: drop
#         * Match device: Inbound device
#         * Device name: br-lan
#         * Restrict to address family: IPv6 only
#         * Use ipset: dhcp-ignore
# see https://github.com/openwrt/odhcpd/issues/198
uci set "dhcp.$id.ip=ignore"
#uci set "dhcp.$id.name=t1"
uci changes dhcp
uci commit dhcp
uci show dhcp
service odhcpd reload
exit
```

Launch the environment:

```bash
time vagrant up --no-destroy-on-error --no-tty --provider=libvirt # or --provider=virtualbox
```

**NB** The server nodes (e.g. `s1`) are [tainted](https://kubernetes.io/docs/concepts/scheduling-eviction/taint-and-toleration/) to prevent them from executing non control-plane workloads. That kind of workload is executed in the agent nodes (e.g. `a1`).

Install tinkerbell:

```bash
vagrant ssh s1
sudo -i
bash /vagrant/provision-tinkerbell.sh
```

Watch for the `t1` workflow progress:

```bash
watch kubectl -n tink-system describe workflow t1
```

In the Virtual Machine Manager UI, restart the `t1` VM, and see if it boots
correctly into the `hello` workflow.

Show information:

```bash
kubectl get services -A
kubectl -n tink-system describe template hello
kubectl -n tink-system describe hardware t1
kubectl -n tink-system describe workflow t1
kubectl -n tink-system get -o yaml template hello
kubectl -n tink-system get -o yaml hardware t1
kubectl -n tink-system get -o yaml workflow t1
```

Verify there are no duplicate IP addresses (e.g. two lines with the same IP but
different MAC):

```bash
arp-scan --localnet --interface eth1
```

In the Hook OSIE, you can troubleshoot with:

```bash
cat /proc/cmdline | tr ' ' '\n' | sort
# NB to get the endpoints, execute this in a k8s node:
#     kubectl get services -n tink-system
#     NAME          TYPE           CLUSTER-IP      EXTERNAL-IP    PORT(S)                                                AGE
#     hegel         ClusterIP      10.13.47.232    <none>         50061/TCP                                              25h
#     tink-server   ClusterIP      10.13.186.115   <none>         42113/TCP                                              25h
#     boots         LoadBalancer   10.13.65.159    10.11.0.60     80:32001/TCP,514:31255/UDP,67:30362/UDP,69:30225/UDP   25h
#     tink-stack    LoadBalancer   10.13.226.115   10.11.0.61     50061:31034/TCP,42113:31407/TCP,8080:31947/TCP         25h
wget -qO- http://10.11.0.60/auto.ipxe           # boots ipxe script.
wget -q http://10.11.0.61:8080/vmlinuz-x86_64   # hook osie.
wget -q http://10.11.0.61:8080/initramfs-x86_64 # hook osie.
```

List this repository dependencies (and which have newer versions):

```bash
export GITHUB_COM_TOKEN='YOUR_GITHUB_PERSONAL_TOKEN'
./renovate.sh
```

## Traefik Dashboard

Access the Traefik Dashboard at:

    https://traefik.example.test/dashboard/

## Rancher Server

Access the Rancher Server at:

    https://s.example.test:6443

**NB** This is a proxy to the k8s API server (which is running in port 6444).

**NB** You must use the client certificate that is inside the `tmp/admin.conf`,
`tmp/*.pem`, or `/etc/rancher/k3s/k3s.yaml` (inside the `s1` machine) file.

Access the rancher server using the client certificate with httpie:

```bash
http \
    --verify tmp/default-ca-crt.pem \
    --cert tmp/default-crt.pem \
    --cert-key tmp/default-key.pem \
    https://s.example.test:6443
```

Or with curl:

```bash
curl \
    --cacert tmp/default-ca-crt.pem \
    --cert tmp/default-crt.pem \
    --key tmp/default-key.pem \
    https://s.example.test:6443
```

## Kubernetes Dashboard

Access the Kubernetes Dashboard at:

    https://kubernetes-dashboard.example.test

Then select `Token` and use the contents of `tmp/admin-token.txt` as the token.

You can also launch the kubernetes API server proxy in background:

```bash
export KUBECONFIG=$PWD/tmp/admin.conf
kubectl proxy &
```

And access the kubernetes dashboard at:

    http://localhost:8001/api/v1/namespaces/kubernetes-dashboard/services/https:kubernetes-dashboard:/proxy/

## K9s Dashboard

The [K9s](https://github.com/derailed/k9s) console UI dashboard is also
installed in the server node. You can access it by running:

```bash
vagrant ssh s1
sudo su -l
k9s
```

# Notes

* k3s has a custom k8s authenticator module that does user authentication from `/var/lib/rancher/k3s/server/cred/passwd`.

# Reference

* [k3s Installation and Configuration Options](https://rancher.com/docs/k3s/latest/en/installation/install-options/)
* [k3s Advanced Options and Configuration](https://rancher.com/docs/k3s/latest/en/advanced/)
* [k3s Under the Hood: Building a Product-grade Lightweight Kubernetes Distro (KubeCon NA 2019)](https://www.youtube.com/watch?v=-HchRyqNtkU)
