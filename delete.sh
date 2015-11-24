#!/bin/bash

source config

sudo lxc-stop -n ${LXC_NAME}
sudo lxc-destroy -n ${LXC_NAME}
