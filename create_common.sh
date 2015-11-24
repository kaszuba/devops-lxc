#!/bin/bash

LXC_DIR="$(sudo lxc-config lxc.lxcpath)/${LXC_NAME}"

cat << 'EOF' | sudo bash -c "cat >>${LXC_DIR}/config"
lxc.cgroup.devices.allow = c 1:1 rwm
lxc.cgroup.devices.allow = c 10:232 rwm
lxc.aa_profile = unconfined
lxc.autodev = 0
EOF

cat << 'EOF' | sudo chroot ${LXC_DIR}/rootfs bash
update-rc.d -f ondemand remove
cd /etc/init
rm tty[2-6].conf plymouth* hwclock* kmod* udev* upstart* console-font.conf

mkdir /dev/net
mknod -m 666 /dev/net/tun c 10 200
mknod -m 666 /dev/fuse c 10 229
EOF

# Start container
sudo lxc-start -d -n ${LXC_NAME}
# Wait for IP address, in standard LXC get it from DHCP
COUNT=0
while [[ $(sudo lxc-attach -n ${LXC_NAME} -- ip addr show dev eth0|grep "inet "|wc -l) == 0 ]]; do
 echo "wait for IP ..."
 sleep 1
 if [[ ${COUNT} -ge 10 ]]; then
  echo "Problem with ip address in container"
  exit 1
 fi
done

# Add apt-cacher proxy
if [[ -n "${APT_CACHER_IP}" ]]; then
 cat << EOF | sudo bash -c "cat >${LXC_DIR}/rootfs/etc/apt/apt.conf.d/01proxy"
Acquire::http { Proxy "http://${APT_CACHER_IP}:3142"; };
EOF
fi

cat << 'EOF' | sudo bash -c "cat >${LXC_DIR}/rootfs/etc/sudoers.d/ubuntu"
ubuntu ALL=(ALL) NOPASSWD: ALL
EOF
sudo chmod 440 ${LXC_DIR}/rootfs/etc/sudoers.d/ubuntu

# Update and install required packages
sudo lxc-attach -n ${LXC_NAME} -- apt-get update
sudo lxc-attach -n ${LXC_NAME} -- apt-get -y install wget ca-certificates git python \
 postgresql postgresql-server-dev-all libyaml-dev libffi-dev python-dev python-libvirt python-pip \
 qemu-kvm qemu-utils libvirt-bin libvirt-dev ubuntu-vm-builder bridge-utils \
 python-virtualenv libpq-dev libgmp-dev
sudo lxc-attach -n ${LXC_NAME} -- mkdir /home/ubuntu/.ssh
cat << 'EOF' | sudo lxc-attach -n ${LXC_NAME} -- bash -c "cat >/home/ubuntu/.ssh/config"
Host *
 StrictHostKeyChecking no
 UserKnownHostsFile /dev/null
EOF
sudo lxc-attach -n ${LXC_NAME} -- chown -R ubuntu /home/ubuntu/.ssh


# Disable modprobe and depmod, prepare devs
cat << 'EOF' | sudo lxc-attach -n ${LXC_NAME} -- su -l -s /bin/bash
dpkg-divert --local --rename --add /sbin/modprobe
ln -s /bin/true /sbin/modprobe
dpkg-divert --local --rename --add /sbin/depmod
ln -s /bin/true /sbin/depmod
EOF

###
# Prepare system for devops scripts
# libvirt
sudo lxc-attach -n ${LXC_NAME} -- virsh pool-define-as --type=dir --name=default --target=/var/lib/libvirt/images
sudo lxc-attach -n ${LXC_NAME} -- virsh pool-autostart default
sudo lxc-attach -n ${LXC_NAME} -- virsh pool-start default
cat << 'EOF' | sudo lxc-attach -n ${LXC_NAME} -- bash -c "cat >> /etc/libvirt/qemu.conf"
security_driver = "none"
EOF
sudo lxc-attach -n ${LXC_NAME} -- usermod ubuntu -a -G libvirtd
sudo lxc-attach -n ${LXC_NAME} -- service libvirt-bin restart

# setup db
sudo lxc-attach -n ${LXC_NAME} -- sed -ir 's/peer/trust/' /etc/postgresql/9.*/main/pg_hba.conf
sudo lxc-attach -n ${LXC_NAME} -- service postgresql restart
cat << 'EOF' | sudo lxc-attach -n ${LXC_NAME} -- su -l postgres -s /bin/bash
echo "CREATE ROLE fuel_devops login password 'fuel_devops'" | psql postgres
createdb fuel_devops -O fuel_devops
EOF

# install devops scripts
cat << 'EOF' | sudo lxc-attach -n ${LXC_NAME} -- su -l ubuntu -s /bin/bash
virtualenv --system-site-packages /home/ubuntu/fuel-devops-venv
source /home/ubuntu/fuel-devops-venv/bin/activate
pip install git+https://github.com/stackforge/fuel-devops.git@2.9.12 --upgrade
django-admin.py syncdb --settings=devops.settings
django-admin.py migrate devops --settings=devops.settings
# fuel-qa
git clone https://github.com/stackforge/fuel-qa /home/ubuntu/fuel-qa
cd /home/ubuntu/fuel-qa
~/fuel-devops-venv/bin/pip install -r ./fuelweb_test/requirements.txt --upgrade
EOF
