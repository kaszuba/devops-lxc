#!/bin/bash

source config

cat iso/MirantisOpenStack-7.0.iso | sudo lxc-attach -n ${LXC_NAME} -- bash -c "cat >/home/ubuntu/MirantisOpenStack-7.0.iso"
