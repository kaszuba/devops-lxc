#!/bin/bash

source config

sudo lxc-start -d -n ${LXC_NAME}
sudo lxc-attach -n ${LXC_NAME} -- su - ubuntu
