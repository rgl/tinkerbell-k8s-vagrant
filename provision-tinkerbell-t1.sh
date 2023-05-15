#!/bin/bash
set -euxo pipefail

t1_mac='08:00:27:00:00:46'
t1_ip='10.11.0.70'
t1_gw='10.11.0.1'
t1_bmc_ip='10.11.0.1'
t1_bmc_port='8070'

# delete existing data.
bash /vagrant/provision-tinkerbell-t1-delete.sh

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

# install the hardware, workflow, bmc machine and bmc job.
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
        uefi: true
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
