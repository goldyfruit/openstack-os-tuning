#!/bin/bash
#
# Tuning for Swift storage node
#   - Virtual memory
#   - TCP/IP I/O
#   - nf_conntrack
#   - Disk I/O
#
# Author: Gaëtan Trellu <gaetan.trellu@incloudus.com>
# Twitter: @goldyfruit
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the gnu general public license as published by
# the free software foundation, either version 3 of the license, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but without any warranty; without even the implied warranty of
# merchantability or fitness for a particular purpose.  see the
# gnu general public license for more details.
#
# You should have received a copy of the gnu general public license
# along with this program.  if not, see .
#

# Filesystem type of the Swift devices
fs_type="xfs"

# Device type (virtual|vd, SCSI|sd, ATA|hd, ect...)
dev_type="sd"

# Profile for server with 32GB RAM or more and SATA 7200RPM/Min or 10KRPM/Min disks
vm_dirty_bg_ratio=5
vm_dirty_ratio=10
vm_vfs_cache_pressure=50
vm_swappiness=5
vm_min_free_kbytes=131072
net_tcp_tw_recyle=1
net_tcp_rw_reuse=1
net_tcp_syncookies=0
net_nf_conntrack_max=1310720
net_nf_conntrack_hashsize=163840
net_ip_local_port_range="1024 65000"
net_tcp_netdev_max_backlog=16384
net_tcp_somaxconn=16384
net_tcp_rmem_max=8388608
net_tcp_wmem_max=8388608
net_tcp_rmem_default=65536
net_tcp_wmem_default=65536
net_tcp_rmem="8192 873800 8388608"
net_tcp_wmem="4096 655360 8388608"
net_tcp_mem="8388608 8388608 8388608"
net_tcp_max_tw_buckets=6000000
net_tcp_max_syn_backlog=65536
net_tcp_max_orphans=262144
net_tcp_synack_retries=2
net_tcp_syn_retries=2
net_tcp_fin_timeout=7
net_tcp_slow_start_after_idle=0
net_tcp_timestamps=0
sys_block_scheduler="deadline"
sys_block_nr_requests=2048
sys_block_read_ahead_kb=2048
sys_block_front_merges=0
sys_block_read_expire=150
sys_block_write_expire=1500
sys_block_rq_affinity=2

# Path to some files
systool_bin=/usr/bin/systool
sysctl_file=/etc/sysctl.d/80-mem_tcp_vfs.conf
udev_io_rules=/etc/udev/rules.d/60-io_schedulers.rules

# Detect Debian like or RedHat like
if [ -f /etc/debian_version ]
then
  debian=true
  modules_file=/etc/modules
  modprobe_conntrack_file=/etc/modprobe.d/nf_conntrack.conf
elif [ -f /etc/redhat-release ]
then
  redhat=true
  modprobe_conntrack_file=/etc/modprobe.d/nf_conntrack.conf
  modules_file=/etc/sysconfig/modules/conntrack.modules
fi

# Modules that should be used
nf_conntrack_module="nf_conntrack"
modules_conntrack="$nf_conntrack_module nf_conntrack_ipv4 xt_state nf_nat_ftp"

# Help as usual
usage() {
cat << EOF

Tuning for Swift storage node:
  - Virtual memory
  - TCP/IP I/O
  - nf_conntrack
  - Disk I/O

Options:
  tune     : Launch tuning only for the current session, tuning will be reset after reboot
  dry      : Dry mode, nothing happens to the system, it just shows you :)
  persist  : Optimizes the system permanently, reboot will not affect optimizations
  orig     : Restore default values

EOF
}

if [ -z $1 ]
then
  usage
  exit 0
fi

echo "#########################################"
echo "#       Load nf_conntrack modules       #"
echo "#########################################"

if [ ! -z $1 -a  "$1" = "tune" -o "$1" = "persist" -o "$1"  = "orig" ]
then
  echo -ne "[~] Processing..."
elif [ ! -z $1 -a  "$1" = "dry" ]
then
  echo "" >> /dev/null
else
  usage
  exit 0
fi

# Load the nf_conntrack modules
# /etc/modprobe.d/nf_conntrack.conf will be created
for module in $modules_conntrack
do
  case $1 in
    tune)
      modprobe $module
      ;;
    dry)
      if [ $module == $nf_conntrack_module ]
      then
          echo "echo \"options $nf_conntrack_module hashsize=$net_nf_conntrack_hashsize\" > $modprobe_conntrack_file"
          echo "modprobe $nf_conntrack_module"
          echo "echo \"#!/bin/sh\" >> $modules_file"
          echo "echo \"exec /sbin/modprobe $nf_conntrack_module\" >> $modules_file"
      else
          echo "modprobe $module"
          echo "echo \"exec /sbin/modprobe $module\" >> $modules_file"
      fi
      ;;
    persist)
      if [ $module == $nf_conntrack_module ]
      then
          echo "options $nf_conntrack_module hashsize=${net_nf_conntrack_hashsize}" > $modprobe_conntrack_file
          modprobe $nf_conntrack_module
          if [ $debian ]
          then
              echo "$nf_conntrack_module" >> $modules_file
          elif [ $redhat ]
          then
              echo "#!/bin/sh" >> $modules_file
              echo "exec /sbin/modprobe $nf_conntrack_module" >> $modules_file
          fi
      else
          modprobe $module
          if [ $debian ]
          then
              echo "$module" >> $modules_file
          elif [ $redhat ]
          then
              echo "exec /sbin/modprobe $module" >> $modules_file
          fi
      fi
      ;;
    orig)
      if [ $module == $nf_conntrack_module ]
      then
          if [ -f $modprobe_conntrack_file ]
          then
              rm -f $modprobe_conntrack_file
          fi
 
          if [ $debian ]
          then
              sed -i "/^$nf_conntrack_module/d" $modules_file
          fi
      else
          if [ $debian ]
          then
              sed -i "/^$module/d" $modules_file
          elif [ $redhat ]
          then
              if [ -f $modules_file ]
              then
                  rm -f $modules_file
              fi
          fi
      fi
      ;;
    *)
      usage
      exit 0
      ;;
   esac
done
if [ ! -z $1 -a  "$1" = "dry" ]
then
  echo ""
else
  echo -e "\t\t[done]\n"
fi

# Options that will be tuned \o/
# Memory
change_dirty_ratio=/proc/sys/vm/dirty_ratio
change_vfs_pressure=/proc/sys/vm/vfs_cache_pressure
change_swappiness=/proc/sys/vm/swappiness
change_min_free_kbytes=/proc/sys/vm/min_free_kbytes
change_dirty_bg_ratio=/proc/sys/vm/dirty_background_ratio
# TCP/IP
change_tcp_recyle=/proc/sys/net/ipv4/tcp_tw_recycle
change_tcp_reuse=/proc/sys/net/ipv4/tcp_tw_reuse
change_tcp_syncookies=/proc/sys/net/ipv4/tcp_syncookies
change_nf_conntrack_max=/proc/sys/net/netfilter/nf_conntrack_max
change_hash_size_table=/sys/module/nf_conntrack/parameters/hashsize
change_ip_local_port_range=/proc/sys/net/ipv4/ip_local_port_range
change_tcp_netdev_max_backlog=/proc/sys/net/core/netdev_max_backlog
change_tcp_somaxconn=/proc/sys/net/core/somaxconn
change_tcp_rmem_max=/proc/sys/net/core/rmem_max
change_tcp_wmem_max=/proc/sys/net/core/wmem_max
change_tcp_rmem_default=/proc/sys/net/core/rmem_default
change_tcp_wmem_default=/proc/sys/net/core/wmem_default
change_tcp_rmem=/proc/sys/net/ipv4/tcp_rmem
change_tcp_wmem=/proc/sys/net/ipv4/tcp_wmem
change_tcp_mem=/proc/sys/net/ipv4/tcp_mem
change_tcp_max_tw_buckets=/proc/sys/net/ipv4/tcp_max_tw_buckets
change_tcp_max_syn_backlog=/proc/sys/net/ipv4/tcp_max_syn_backlog
change_tcp_max_orphans=/proc/sys/net/ipv4/tcp_max_orphans
change_tcp_synack_retries=/proc/sys/net/ipv4/tcp_synack_retries
change_tcp_syn_retries=/proc/sys/net/ipv4/tcp_syn_retries
change_tcp_fin_timeout=/proc/sys/net/ipv4/tcp_fin_timeout
change_tcp_slow_start_after_idle=/proc/sys/net/ipv4/tcp_slow_start_after_idle
change_tcp_timestamps=/proc/sys/net/ipv4/tcp_timestamps

echo "#########################################"
echo "#     Memory | TCP/IP | VFS Tuning      #"
echo "#########################################"

case $1 in
  tune)
    echo -ne "[~] Processing..."
    echo $vm_dirty_bg_ratio > $change_dirty_bg_ratio
    echo $vm_dirty_ratio > $change_dirty_ratio
    echo $vm_vfs_cache_pressure > $change_vfs_pressure
    echo $vm_swappiness > $change_swappiness
    echo $vm_min_free_kbytes > $change_min_free_kbytes
    echo $net_tcp_tw_recyle > $change_tcp_recyle
    echo $net_tcp_rw_reuse > $change_tcp_reuse
    echo $net_tcp_syncookies > $change_tcp_syncookies
    echo $net_nf_conntrack_max > $change_nf_conntrack_max
    echo $net_nf_conntrack_hashsize > $change_hash_size_table
    echo $net_ip_local_port_range > $change_ip_local_port_range
    echo $net_tcp_netdev_max_backlog > $change_tcp_netdev_max_backlog
    echo $net_tcp_somaxconn > $change_tcp_somaxconn
    echo $net_tcp_rmem_max > $change_tcp_rmem_max
    echo $net_tcp_wmem_max > $change_tcp_wmem_max
    echo $net_tcp_rmem_default > $change_tcp_rmem_default
    echo $net_tcp_wmem_default > $change_tcp_wmem_default
    echo $net_tcp_rmem > $change_tcp_rmem
    echo $net_tcp_wmem > $change_tcp_wmem
    echo $net_tcp_mem > $change_tcp_mem
    echo $net_tcp_max_tw_buckets > $change_tcp_max_tw_buckets
    echo $net_tcp_max_syn_backlog > $change_tcp_max_syn_backlog
    echo $net_tcp_max_orphans > $change_tcp_max_orphans
    echo $net_tcp_synack_retries > $change_tcp_synack_retries
    echo $net_tcp_syn_retries > $change_tcp_syn_retries
    echo $net_tcp_fin_timeout > $change_tcp_fin_timeout
    echo $net_tcp_slow_start_after_idle > $change_tcp_slow_start_after_idle
    echo $net_tcp_timestamps > $change_tcp_timestamps
    echo -e "\t\t[done]\n"
  ;;
  dry)
    echo "echo $vm_dirty_bg_ratio > $change_dirty_bg_ratio"
    echo "echo $vm_dirty_ratio > $change_dirty_ratio"
    echo "echo $vm_vfs_cache_pressure > $change_vfs_pressure"
    echo "echo $vm_swappiness > $change_swappiness"
    echo "echo $vm_min_free_kbytes > $change_min_free_kbytes"
    echo "echo $net_tcp_tw_recyle > $change_tcp_recyle"
    echo "echo $net_tcp_rw_reuse > $change_tcp_reuse"
    echo "echo $net_tcp_syncookies > $change_tcp_syncookies"
    echo "echo $net_nf_conntrack_max > $change_nf_conntrack_max"
    echo "echo $net_nf_conntrack_hashsize > $change_hash_size_table"
    echo "echo $net_ip_local_port_range > $change_ip_local_port_range"
    echo "echo $net_tcp_netdev_max_backlog > $change_tcp_netdev_max_backlog"
    echo "echo $net_tcp_somaxconn > $change_tcp_somaxconn"
    echo "echo $net_tcp_rmem_max > $change_tcp_rmem_max"
    echo "echo $net_tcp_wmem_max > $change_tcp_wmem_max"
    echo "echo $net_tcp_rmem_default > $change_tcp_rmem_default"
    echo "echo $net_tcp_wmem_default > $change_tcp_wmem_default"
    echo "echo $net_tcp_rmem > $change_tcp_rmem"
    echo "echo $net_tcp_wmem > $change_tcp_wmem"
    echo "echo $net_tcp_mem > $change_tcp_mem"
    echo "echo $net_tcp_max_tw_buckets > $change_tcp_max_tw_buckets"
    echo "echo $net_tcp_max_syn_backlog > $change_tcp_max_syn_backlog"
    echo "echo $net_tcp_max_orphans > $change_tcp_max_orphans"
    echo "echo $net_tcp_synack_retries > $change_tcp_synack_retries"
    echo "echo $net_tcp_syn_retries > $change_tcp_syn_retries"
    echo "echo $net_tcp_fin_timeout > $change_tcp_fin_timeout"
    echo "echo $net_tcp_slow_start_after_idle > $change_tcp_slow_start_after_idle"
    echo "echo $net_tcp_timestamps > $change_tcp_timestamps"
    echo ""
  ;;
  persist)
    echo -ne "[~] Processing..."
    echo "# Swift tuning for VM (Virtual Memory)" > $sysctl_file
    echo "vm.dirty_background_ratio = $vm_dirty_bg_ratio" >> $sysctl_file
    echo "vm.dirty_ratio = $vm_dirty_ratio" >> $sysctl_file
    echo "vm.vfs_cache_pressure = $vm_vfs_cache_pressure" >> $sysctl_file
    echo "vm.swappiness = $vm_swappiness" >> $sysctl_file
    echo "vm.min_free_kbytes = $vm_min_free_kbytes" >> $sysctl_file
    echo "" >> $sysctl_file
    echo "# Swift tuning for TCP/IP" >> $sysctl_file
    echo "net.ipv4.tcp_tw_recycle = $net_tcp_tw_recyle" >> $sysctl_file
    echo "net.ipv4.tcp_tw_reuse = $net_tcp_rw_reuse" >> $sysctl_file
    echo "net.ipv4.tcp_syncookies = $net_tcp_syncookies" >> $sysctl_file
    echo "net.ipv4.netfilter.ip_conntrack_max = $net_nf_conntrack_max" >> $sysctl_file
    echo "net.ipv4.ip_local_port_range = $net_ip_local_port_range" >> $sysctl_file
    echo "net.core.netdev_max_backlog = $net_tcp_netdev_max_backlog" >> $sysctl_file
    echo "net.core.somaxconn = $net_tcp_somaxconn" >> $sysctl_file
    echo "net.core.rmem_max = $net_tcp_rmem_max" >> $sysctl_file
    echo "net.core.wmem_max = $net_tcp_wmem_max" >> $sysctl_file
    echo "net.core.rmem_default = $net_tcp_rmem_default" >> $sysctl_file
    echo "net.core.wmem_default = $net_tcp_wmem_default" >> $sysctl_file
    echo "net.ipv4.tcp_rmem = $net_tcp_rmem" >> $sysctl_file
    echo "net.ipv4.tcp_wmem = $net_tcp_wmem" >> $sysctl_file
    echo "net.ipv4.tcp_mem = $net_tcp_mem" >> $sysctl_file
    echo "net.ipv4.tcp_max_tw_buckets = $net_tcp_max_tw_buckets" >> $sysctl_file
    echo "net.ipv4.tcp_max_syn_backlog = $net_tcp_max_syn_backlog" >> $sysctl_file
    echo "net.ipv4.tcp_max_orphans = $net_tcp_max_orphans" >> $sysctl_file
    echo "net.ipv4.tcp_synack_retries = $net_tcp_synack_retries" >> $sysctl_file
    echo "net.ipv4.tcp_syn_retries = $net_tcp_syn_retries" >> $sysctl_file
    echo "net.ipv4.tcp_fin_timeout = $net_tcp_fin_timeout" >> $sysctl_file
    echo "net.ipv4.tcp_slow_start_after_idle = $net_tcp_slow_start_after_idle" >> $sysctl_file
    echo "net.ipv4.tcp_timestamps = $net_tcp_timestamps" >> $sysctl_file
    echo -e "\t\t[done]\n"
  ;;
  orig)
    echo -ne "[~] Processing..."
    echo 10 > $change_dirty_bg_ratio
    echo 20 > $change_dirty_ratio
    echo 100 > $change_vfs_pressure
    echo 60 > $change_swappiness
    echo 90112 > $change_min_free_kbytes
    echo 0 > $change_tcp_recyle
    echo 0 > $change_tcp_reuse
    echo 1 > $change_tcp_syncookies
    echo 65536 > $change_nf_conntrack_max
    echo 16384 > $change_hash_size_table
    echo "32768 61000" > $change_ip_local_port_range
    echo 1000 > $change_tcp_netdev_max_backlog
    echo 128 > $change_tcp_somaxconn
    echo 212992 > $change_tcp_rmem_max
    echo 212992 > $change_tcp_wmem_max
    echo 212992 > $change_tcp_rmem_default
    echo 212992 > $change_tcp_wmem_default
    echo "4096	87380	6291456" > $change_tcp_rmem
    echo "4096	16384	4194304" > $change_tcp_wmem
    echo "41781	55711	83562" > $change_tcp_mem
    echo 8192 > $change_tcp_max_tw_buckets
    echo 128 > $change_tcp_max_syn_backlog
    echo 8192 > $change_tcp_max_orphans
    echo 5 > $change_tcp_synack_retries
    echo 6 > $change_tcp_syn_retries
    echo 60 > $change_tcp_fin_timeout
    echo 1 > $change_tcp_slow_start_after_idle
    echo 1 > $change_tcp_timestamps

    rm -f $sysctl_file
    echo -e "\t\t[done]\n"
  ;;
esac

if [ $1 == "persist" ]
then
  echo "# Swift I/O tuning" > $udev_io_rules
fi

# Tune the Swift devices
# Found by /proc/mounts and parsed with fs_type (change the value at the top of this script)
for disk in $(awk '$3 ~ /^'$fs_type'/ { print $1 }' /proc/mounts | grep $dev_type | awk -F"/" '{ print $NF }')
do

  change_scheduler=/sys/block/$disk/queue/scheduler
  change_nr_requests=/sys/block/$disk/queue/nr_requests
  change_read_ahead_kb=/sys/block/$disk/queue/read_ahead_kb
  change_front_merges=/sys/block/$disk/queue/iosched/front_merges
  change_read_expire=/sys/block/$disk/queue/iosched/read_expire
  change_write_expire=/sys/block/$disk/queue/iosched/write_expire
  change_rq_affinity=/sys/block/$disk/queue/rq_affinity

  echo "#########################################"
  echo "#         Tuning for disk : $disk         #"
  echo "#########################################"

  case $1 in
    tune)
      echo -ne "[~] Processing..."
      echo $sys_block_scheduler > $change_scheduler
      echo $sys_block_nr_requests > $change_nr_requests
      echo $sys_block_read_ahead_kb > $change_read_ahead_kb
      echo $sys_block_front_merges > $change_front_merges
      echo $sys_block_read_expire > $change_read_expire
      echo $sys_block_write_expire > $change_write_expire
      echo $sys_block_rq_affinity > $change_rq_affinity
      echo -e "\t\t[done]\n"
    ;;
    dry)
      echo "echo $sys_block_scheduler > $change_scheduler"
      echo "echo $sys_block_nr_requests > $change_nr_requests"
      echo "echo $sys_block_read_ahead_kb > $change_read_ahead_kb"
      echo "echo $sys_block_front_merges > $change_front_merges"
      echo "echo $sys_block_read_expire > $change_read_expire"
      echo "echo $sys_block_write_expire > $change_write_expire"
      echo "echo $sys_block_rq_affinity > $change_rq_affinity"
      echo 
    ;;
    persist)
      echo -ne "[~] Processing..."
      echo "ACTION==\"add|change\", KERNEL==\""${dev_type}"[a-z]\", ATTR{queue/scheduler}=\""$sys_block_scheduler"\"" >> $udev_io_rules
      echo "ACTION==\"add|change\", KERNEL==\""${dev_type}"[a-z]\", ATTR{queue/nr_requests}=\""$sys_block_nr_requests"\"" >> $udev_io_rules
      echo "ACTION==\"add|change\", KERNEL==\""${dev_type}"[a-z]\", ATTR{queue/read_ahead_kb}=\""$sys_block_read_ahead_kb"\"" >> $udev_io_rules
      echo "ACTION==\"add|change\", KERNEL==\""${dev_type}"[a-z]\", ATTR{queue/iosched/front_merges}=\""$sys_block_front_merges"\"" >> $udev_io_rules
      echo "ACTION==\"add|change\", KERNEL==\""${dev_type}"[a-z]\", ATTR{queue/iosched/read_expire}=\""$sys_block_read_expire"\"" >> $udev_io_rules
      echo "ACTION==\"add|change\", KERNEL==\""${dev_type}"[a-z]\", ATTR{queue/iosched/write_expire}=\""$sys_block_write_expire"\"" >> $udev_io_rules
      echo "ACTION==\"add|change\", KERNEL==\""${dev_type}"[a-z]\", ATTR{queue/rq_affinity}=\""$sys_block_rq_affinity"\"" >> $udev_io_rules
      echo -e "\t\t[done]\n"
    ;;
    orig)
      echo -ne "[~] Processing..."
      echo cfq > $change_scheduler
      echo 128 > $change_nr_requests
      echo 128 > $change_read_ahead_kb
      echo 1 > $change_rq_affinity
      rm -f $udev_io_rules
      echo -e "\t\t[done]\n"
    ;;
  esac
done

# Apply the changes if it's "persist" or "orig"
# Reload the sysctl and restart udev
case $1 in
  persist)
    sysctl -p > /dev/null
    udevadm control --reload-rules > /dev/null
    udevadm trigger > /dev/null
    if [ $? != 0 ]
    then
        echo "Unable to restart udev service."
    fi
  ;;
  orig)
    sysctl -p > /dev/null
    udevadm control --reload-rules > /dev/null
    udevadm trigger > /dev/null
    if [ $? != 0 ]
    then
        echo "Unable to restart udev service."
    fi
  ;;
esac
