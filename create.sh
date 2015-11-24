#!/bin/bash

source config

# create container
sudo lxc-create -n ${LXC_NAME} -t download -- -d ubuntu -r trusty -a amd64

source create_common.sh
