# Build the installer USB:
#   mkksiso --ks install/exedore.ks CentOS-Stream-10-latest-x86_64-boot.iso exedore.iso
# Any EL10 boot.iso works; the ISO only delivers the image below.
# Kickstart for exedore.dc2.crunchtools.com (RT#1628)
# Installs the rhel10-bootc-server image (same as gloval) onto the internal NVMe.
# The installer ISO only delivers the image; nothing from it survives.

text
lang en_US.UTF-8
keyboard us
timezone America/New_York --utc

network --bootproto=dhcp --device=link --activate --onboot=yes --hostname=exedore.dc2.crunchtools.com

# Only ever touch the internal NVMe. The 4 TB cold-copy drive must never be a
# candidate, even if someone plugs it in early.
ignoredisk --only-use=nvme0n1
zerombr
clearpart --all --initlabel --drives=nvme0n1
reqpart --add-boot
part / --grow --fstype=xfs

ostreecontainer --url=quay.io/crunchtools/rhel10-bootc-server:latest --transport=registry --no-signature-verification

# Key-only root, matching gloval.
rootpw --lock

firstboot --disable
reboot --eject

%post --erroronfail
install -d -m 0700 /root/.ssh
cat > /root/.ssh/authorized_keys <<'KEYS'
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOShcSBdLmP9zL3uAqBGGF3RSg8fuaGqnJ5lnZ+q8lzJ crunchtools (breetai/dolza -> servers)
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPaBoMWkxQxQYVise4oQRd0SrXqnH25YMienQWikM3q9 smccarty-csb (breetai<->dolza CSB peer)
KEYS
chmod 0600 /root/.ssh/authorized_keys
restorecon -R /root/.ssh || true
%end
