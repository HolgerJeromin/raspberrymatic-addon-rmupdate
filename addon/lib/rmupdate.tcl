#  RaspMatic update addon
#
#  Copyright (C) 2018  Jan Schneider <oss@janschneider.net>
#
#  This program is free software: you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation, either version 3 of the License, or
#  (at your option) any later version.
#
#  This program is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#  You should have received a copy of the GNU General Public License
#  along with this program.  If not, see <http://www.gnu.org/licenses/>.
#

namespace eval rmupdate {
	variable support_file_url "https://github.com/j-a-n/raspberrymatic-addon-rmupdate/raw/master/support.json"
	variable raspi_fw_url "https://github.com/raspberrypi/firmware/raw/master"
	variable release_url "https://github.com/jens-maus/RaspberryMatic/releases"
	variable addon_dir "/usr/local/addons/rmupdate"
	variable rc_dir "/usr/local/etc/config/rc.d"
	variable addons_www_dir "/usr/local/etc/config/addons/www"
	variable img_dir "/usr/local/addons/rmupdate/var/img"
	variable mnt_sys "/usr/local/addons/rmupdate/var/mnt_sys"
	variable mnt_img "/usr/local/addons/rmupdate/var/mnt_img"
	variable loop_dev "/dev/loop7"
	variable install_log "/usr/local/addons/rmupdate/var/install.log"
	variable install_lock "/usr/local/addons/rmupdate/var/install.lock"
	variable log_file "/tmp/rmupdate-addon-log.txt"
	variable log_level 0
	variable lock_start_port 12100
	variable lock_socket
	variable lock_id_log_file 1
	variable language "de"
}

proc json_string {str} {
	set replace_map {
		"\"" "\\\""
		"\\" "\\\\"
		"\b"  "\\b"
		"\f"  "\\f"
		"\n"  "\\n"
		"\r"  "\\r"
		"\t"  "\\t"
	}
	return "[string map $replace_map $str]"
}

proc array_to_json {a} {
	array set arr $a
	set json "\["
	set keys [array names arr]
	set keys [lsort $keys]
	set cur_id ""
	foreach key $keys {
		regexp {^(.+)::([^:]+)$} $key match id opt
		if {$cur_id != $id} {
			if {$cur_id != ""} {
				set json [string range $json 0 end-1]
				append json "\},"
			}
			append json "\{"
			set cur_id $id
		}
		set val [json_string $arr($key)]
		append json "\"${opt}\":\"${val}\","
	}
	if {$cur_id != ""} {
		set json [string range $json 0 end-1]
		append json "\}"
	}
	append json "\]"
	return $json
}

proc ::rmupdate::i18n {str} {
	variable language
	if {$language == "de"} {
		if {$str == "Checking size of filesystems."} { return "Überprüfe Größe der Dateisysteme." }
		if {$str == "Current filesystem of partition %d (%d bytes) not big enough (new usage: %d bytes)."} { return "Aktuelles Dateisystem der Partition %d (%d Bytes) nicht groß genug (neue Belegung: %d bytes)." }
		if {$str == "Updating filesystems."} { return "Aktualisiere Dateisysteme." }
		if {$str == "Updating system partition %s."} { return "Aktualisiere System-Partition %s." }
		if {$str == "Updating boot configuration."} { return "Aktualisiere Boot-Konfiguration." }
		if {$str == "Downloading firmware from %s."} { return "Lade Firmware von %s herunter." }
		if {$str == "Download completed."} { return "Download abgeschlossen." }
		if {$str == "Extracting firmware %s.\nThis process takes some minutes, please be patient..."} { return "Entpacke Firmware %s.\nBitte haben Sie ein wenig Geduld, dieser Vorgang benötigt einige Minuten..." }
		if {$str == "Failed to find download link for firmware %s."} { return "Download-Link für Firmware %s nicht gefunden." }
		if {$str == "Failed to extract firmware image from archive."} { return "Firmware-Image konnte nicht entpackt werden." }
		if {$str == "Another install process is running."} { return "Es läuft bereits ein andere Installationsvorgang." }
		if {$str == "System not upgradeable."} { return "Dieses System ist nicht aktualisierbar." }
		if {$str == "System will reboot now."} { return "Das System wird jetzt neu gestartet." }
		if {$str == "Latest firmware version: %s"} { return "Aktuellste Firmware-Version: %s" }
		if {$str == "Current firmware version: %s"} { return "Installierte Firmware-Version: %s" }
		if {$str == "Download url missing."} { return "Download-URL fehlt." }
		if {$str == "Addon %s successfully installed."} { return "Addon %s erfolgreich installiert." }
		if {$str == "Addon %s successfully uninstalled."} { return "Addon %s erfolgreich deinstalliert." }
		if {$str == "Using recovery system to update firmware."} { return "Verwende Recovery-System für Firmware-Update." }
		if {$str == "Recovery system will be started now, which will perform the firmware update.\nThis process takes some minutes, please be patient..."} { return "Das Recovery-System wird nun gestartet und das Firmware-Update durchgeführt.\nBitte haben Sie ein wenig Geduld, dieser Vorgang benötigt einige Minuten..." }
	}
	return $str
}

proc ::rmupdate::get_rpi_version {} {
	if {[file exists /var/hm_mode]} {
		set fd [open /var/hm_mode r]
		set data [read $fd]
		close $fd
		foreach d [split $data "\n"] {
			if {[regexp {^HM_HOST='([^']+)'} $d match host]} {
				if {[regexp {^(rpi\d)} $host match rpi_host]} {
					return $rpi_host
				}
				return $host
			}
		}
	}

	# Revison list from http://elinux.org/RPi_HardwareHistory
	set revision_map(0002)    "rpi0"
	set revision_map(0003)    "rpi0"
	set revision_map(0004)    "rpi0"
	set revision_map(0005)    "rpi0"
	set revision_map(0006)    "rpi0"
	set revision_map(0007)    "rpi0"
	set revision_map(0008)    "rpi0"
	set revision_map(0009)    "rpi0"
	set revision_map(000d)    "rpi0"
	set revision_map(000e)    "rpi0"
	set revision_map(000f)    "rpi0"
	set revision_map(0010)    "rpi0"
	set revision_map(0011)    "rpi0"
	set revision_map(0012)    "rpi0"
	set revision_map(0013)    "rpi0"
	set revision_map(0014)    "rpi0"
	set revision_map(0015)    "rpi0"
	set revision_map(900021)  "rpi0"
	set revision_map(900032)  "rpi0"
	set revision_map(900092)  "rpi0"
	set revision_map(900093)  "rpi0"
	set revision_map(920093)  "rpi0"
	set revision_map(9000c1)  "rpi0"
	set revision_map(a01040)  "rpi2"
	set revision_map(a01041)  "rpi2"
	set revision_map(a21041)  "rpi2"
	set revision_map(a22042)  "rpi2"
	set revision_map(a02082)  "rpi3"
	set revision_map(a020a0)  "rpi3"
	set revision_map(a22082)  "rpi3"
	set revision_map(a32082)  "rpi3"
	set revision_map(1a01041) "rpi3"
	set revision_map(a020d3)  "rpi3"
	set revision_map(9020e0)  "rpi3"
	set revision_map(a02100)  "rpi3"
	set revision_map(a03111)  "rpi4"
	set revision_map(b03111)  "rpi4"
	set revision_map(c03111)  "rpi4"
	
	set fd [open /proc/cpuinfo r]
	set data [read $fd]
	close $fd
	foreach d [split $data "\n"] {
		regexp {^Hardware\s*:\s*(\S+)} $d match hardware
		if { [info exists hardware] && $hardware == "Rockchip" } {
			return "tinkerboard"
		}
		regexp {^Revision\s*:\s*(\S+)\s*$} $d match revision
		if { [info exists revision] && [info exists revision_map($revision)] } {
			return $revision_map($revision)
		}
	}
	return ""
}

# return 1 if a>b,  0 if a=b,  -1 if a<b
proc ::rmupdate::compare_versions {a b} {
	return [package vcompare [lindex [split $a "-"] 0] [lindex [split $b "-"] 0]]
}

# error=1, warning=2, info=3, debug=4
proc ::rmupdate::write_log {lvl str {lock 1}} {
	variable log_level
	variable log_file
	variable lock_id_log_file
	if {$lvl <= $log_level && $log_file != ""} {
		if {$lock == 1} {
			acquire_lock $lock_id_log_file
		}
		set fd [open $log_file "a"]
		set date [clock seconds]
		set date [clock format $date -format {%Y-%m-%d %T}]
		set process_id [pid]
		puts $fd "\[${lvl}\] \[${date}\] \[${process_id}\] ${str}"
		close $fd
		#puts "\[${lvl}\] \[${date}\] \[${process_id}\] ${str}"
		if {$lock == 1} {
			release_lock $lock_id_log_file
		}
	}
}

proc ::rmupdate::read_log {} {
	variable log_file
	if { ![file exist $log_file] } {
		return ""
	}
	set fp [open $log_file r]
	set data [read $fp]
	close $fp
	return $data
}

proc ::rmupdate::write_install_log {str args} {
	variable install_log
	write_log 4 [format $str $args]
	puts stderr [format [i18n $str] $args]
	set fd [open $install_log "a"]
	puts $fd [format [i18n $str] $args]
	close $fd
}

proc ::rmupdate::read_install_log {} {
	variable install_log
	if { ![file exist $install_log] } {
		return ""
	}
	set fp [open $install_log r]
	set data [read $fp]
	close $fp
	return $data
}

proc ::rmupdate::acquire_lock {lock_id} {
	variable lock_socket
	variable lock_start_port
	set port [expr { $lock_start_port + $lock_id }]
	set tn 0
	# 'socket already in use' error will be our lock detection mechanism
	while {1} {
		set tn [expr {$tn + 1}]
		if { [catch {socket -server dummy_accept $port} sock] } {
			if {$tn > 10} {
				write_log 1 "Failed to acquire lock ${lock_id} after 2500ms, ignoring lock" 0
				break
			}
			after 25
		} else {
			set lock_socket($lock_id) $sock
			break
		}
	}
}

proc ::rmupdate::release_lock {lock_id} {
	variable lock_socket
	if {[info exists lock_socket($lock_id)]} {
		if { [catch {close $lock_socket($lock_id)} errormsg] } {
			write_log 1 "Error '${errormsg}' on closing socket for lock '${lock_id}'" 0
		}
		unset lock_socket($lock_id)
	}
}

proc ::rmupdate::version {} {
	variable addon_dir
	set fp [open "${addon_dir}/VERSION" r]
	set data [read $fp]
	close $fp
	return [string trim $data]
}

proc ::rmupdate::get_partitions {{device ""}} {
	array set partitions {}
	if {$device != ""} {
		set data [exec /sbin/fdisk -l $device]
	} else {
		set data [exec /sbin/fdisk -l]
	}

	set root_partuuid ""
	set fd [open "/proc/cmdline" r]
	set cmdline_data [read $fd]
	close $fd
	foreach d [split $cmdline_data "\n"] {
		if { [regexp {root=PARTUUID=(\S+)} $d match partuuid] } {
			set root_partuuid $partuuid
			break
		}
	}

	#set fd [open /etc/mtab r]
	#set mtab_data [read $fd]
	#close $fd

	set df_data [exec /bin/df -a -T]

	foreach d [split $data "\n"] {
		if {[regexp {Disk\s+(\S+):.*\s(\d+)\s+bytes} $d match dev size]} {
			if {[regexp {/dev/ram} $dev]} {
				continue
			}
			set partitions(${dev}::0::partition) 0
			set partitions(${dev}::0::disk_device) $dev
			set partitions(${dev}::0::model) ""
			set partitions(${dev}::0::size) $size

			set data2 ""
			catch {set data2 [exec /usr/sbin/parted $dev unit B print]} data2
			foreach d2 [split $data2 "\n"] {
				if {[regexp {^Model:\s*(\S.*)\s*$} $d2 match model]} {
					set partitions(${dev}::0::model) $model
				} elseif {[regexp {^\s*(\d)\s+(\d+)B\s+(\d+)B\s+(\d+)B.*} $d2 match num start end size]} {
					set partitions(${dev}::${num}::partition) $num
					set partitions(${dev}::${num}::disk_device) $dev
					set part_dev [get_partition_device $dev $num]
					set partitions(${dev}::${num}::partition_device) $part_dev
					set partitions(${dev}::${num}::start) $start
					set partitions(${dev}::${num}::end) $end
					set partitions(${dev}::${num}::size) $size
					set partitions(${dev}::${num}::partition_uuid) ""
					set partitions(${dev}::${num}::filesystem_label) ""
					set partitions(${dev}::${num}::filesystem_uuid) ""
					set partitions(${dev}::${num}::filesystem_type) ""
					set partitions(${dev}::${num}::mountpoint) ""
					set partitions(${dev}::${num}::filesystem_size) -1
					set partitions(${dev}::${num}::filesystem_used) -1
					set partitions(${dev}::${num}::filesystem_avail) -1
					set partitions(${dev}::${num}::filesystem_usage) -1

					foreach f [glob /dev/disk/by-partuuid/*] {
						catch {
							if { [file tail [file readlink $f]] == [file tail $part_dev] } {
								set partitions(${dev}::${num}::partition_uuid) [file tail $f]
								break
							}
						}
					}
					
					set data3 ""
					if [catch {
						set data3 [exec /sbin/blkid $part_dev]
					} err] {
						write_log 1 "Command blkid failed for device ${part_dev}: ${err}"
						#error "Command blkid failed for device ${part_dev}: ${err}"
					}
					foreach d3 [split $data3 "\n"] {
						if {[regexp {LABEL="([^"]+)"} $d3 match lab]} {
							set partitions(${dev}::${num}::filesystem_label) $lab
						}
						if {[regexp {UUID="([^"]+)"} $d3 match uuid]} {
							set partitions(${dev}::${num}::filesystem_uuid) $uuid
						}
						if {[regexp {TYPE="([^"]+)"} $d3 match type]} {
							set partitions(${dev}::${num}::filesystem_type) $type
						}
					}

					#foreach d4 [split $mtab_data "\n"] {
					#	if { [regexp {^(\S+)\s+(\S+)\s+} $d4 match md mp] } {
					#		if {$md == $part_dev} {
					#			set partitions(${dev}::${num}::mountpoint) $mp
					#			break
					#		} elseif {$mp == "/" && $partitions(${dev}::${num}::partition_uuid) == $root_partuuid} {
					#			set partitions(${dev}::${num}::mountpoint) $mp
					#			break
					#		}
					#	}
					#}

					# Filesystem           Type       1K-blocks      Used Available Use% Mounted on
					# /dev/root            ext4          991512    346288    577640  37% /
					foreach d4 [split $df_data "\n"] {
						if { [regexp {^(\S+)\s+(\S+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)%\s+(\S+)\s*$} $d4 match dd dt ds du da dp dm] } {
							if {$dd == $part_dev} {
							} elseif {$dm == "/" && $partitions(${dev}::${num}::partition_uuid) == $root_partuuid} {
							} else {
								continue
							}
							set partitions(${dev}::${num}::mountpoint) $dm
							set partitions(${dev}::${num}::filesystem_size) [format "%0.0f" [expr {$ds * 1024.0}]]
							set partitions(${dev}::${num}::filesystem_used) [format "%0.0f" [expr {$du * 1024.0}]]
							set partitions(${dev}::${num}::filesystem_avail) [format "%0.0f" [expr {$da * 1024.0}]]
							set partitions(${dev}::${num}::filesystem_usage) [expr {$dp / 100.0}]
						}
					}
				}
			}
		}
	}
	return [array get partitions]
}

proc ::rmupdate::get_disk_device {partition_device} {
	if { [regexp {^(\S+mmcblk\d)p\d$} $partition_device match disk_device] } {
		return $disk_device
	}
	if { [regexp {^(\S+)\d$} $partition_device match disk_device] } {
		return $disk_device
	}
	return $partition_device
}

proc ::rmupdate::get_partition_device {device partition} {
	if { [regexp {mmcblk} $device match] } {
		return "${device}p${partition}"
	}
	return "${device}${partition}"
}

proc ::rmupdate::get_partion_start_end_and_size {device partition} {
	if [catch {
		array set partitions [get_partitions $device]
		set res [list \
			$partitions(${device}::${partition}::start) \
			$partitions(${device}::${partition}::end) \
			$partitions(${device}::${partition}::size) \
		]
	} err] {
		error "Failed to get partition start and size of device ${device}, partition ${partition}."
	}
	return $res
}

proc ::rmupdate::delete_partition_table {device} {
	exec /bin/dd if=/dev/zero of=$device bs=512 count=1 2>/dev/null
	catch { exec /usr/sbin/partprobe }
}

proc ::rmupdate::is_recoveryfs_available {} {
	if {[compare_versions [get_current_firmware_version] "2.31.25.20180324"] > 0} {
		return 1
	}
	return 0
}

proc ::rmupdate::is_system_upgradeable {{target_version ""}} {
	set sys_dev [get_system_device]
	if { [is_recoveryfs_available] } {
		if { $target_version == "" } {
			return 1
		}
		if {[compare_versions $target_version "2.31.25.20180324"] > 0} {
			return 1
		}
	}
	if { [get_filesystem_label $sys_dev 3] == "rootfs2" } {
		return 1
	}
	return 0
}

proc ::rmupdate::get_part_uuid {device {partition ""}} {
	if {$partition != ""} {
		set device [get_partition_device $device $partition]
	}
	foreach f [glob /dev/disk/by-partuuid/*] {
		set d ""
		catch {
			set d [file readlink $f]
		}
		if { [file tail $d] == [file tail $device] } {
			return [file tail $f]
		}
	}
	error "Failed to get partition uuid of device ${device}."
}

proc ::rmupdate::get_filesystem_label {device {partition ""}} {
	if {$partition != ""} {
		set device [get_partition_device $device $partition]
	}
	set data [exec /sbin/blkid $device]
	foreach d [split $data "\n"] {
		regexp {LABEL="([^"]+)"} $d match lab
		if { [info exists lab] } {
			return $lab
		}
	}
	error "Failed to get filesystem label of device ${device}."
}

proc ::rmupdate::update_cmdline {cmdline root} {
	set fd [open $cmdline r]
	set data [read $fd]
	close $fd

	regsub -all "root=\[a-zA-Z0-9\=/\-\]+ " $data "root=${root} " data

	set fd [open $cmdline w]
	puts -nonewline $fd $data
	close $fd
}

proc ::rmupdate::update_boot_scr {boot_scr rootfs userfs} {
	set boot_script "/tmp/boot.script"

	catch { exec /bin/dd if=$boot_scr of=$boot_script bs=72 skip=1 }

	set fd [open $boot_script r]
	set data [read $fd]
	close $fd

	regsub -all "setenv rootfs \[0-9\]" $data "setenv rootfs ${rootfs}" data
	regsub -all "setenv userfs \[0-9\]" $data "setenv userfs ${userfs}" data

	set fd [open $boot_script w]
	puts -nonewline $fd $data
	close $fd

	set mkimage "/tmp/mkimage"
	if {![file exists $mkimage]} {
		set mkimage "/usr/bin/mkimage"
	}
	exec $mkimage -C none -A arm -T script -d $boot_script $boot_scr

	file delete $boot_script
}

proc ::rmupdate::get_system_device {} {
	set cmdline "/proc/cmdline"
	set fd [open $cmdline r]
	set data [read $fd]
	close $fd
	# Default
	set sys_dev "/dev/mmcblk0"
	foreach d [split $data "\n"] {
		if { [regexp {root=PARTUUID=(\S+)} $d match partuuid] } {
			catch {
				set x [file readlink "/dev/disk/by-partuuid/${partuuid}"]
				if { [regexp {(mmcblk.*)p\d} [file tail $x] match device] } {
					set sys_dev "/dev/${device}"
					break
				} elseif { [regexp {(.*)\d} [file tail $x] match device] } {
					set sys_dev "/dev/${device}"
					break
				}
			}
		}
	}
	return $sys_dev
}

proc ::rmupdate::get_mounted_device {mountpoint} {
	set fd [open /etc/mtab r]
	set data [read $fd]
	close $fd
	foreach d [split $data "\n"] {
		if { [regexp {^(\S+)\s+(\S+)\s+} $d match device mp] } {
			if {$mp == $mountpoint} {
				return $device
			}
		}
	}
	return ""
}

proc ::rmupdate::get_current_root_partition_number {} {
	set cmdline "/proc/cmdline"
	set fd [open $cmdline r]
	set data [read $fd]
	close $fd
	foreach d [split $data "\n"] {
		regexp {root=PARTUUID=[a-f0-9]+-([0-9]+)} $d match partition
		if { [info exists partition] } {
			return [expr {0 + $partition}]
		}
	}
	return 2
}

proc ::rmupdate::update_fstab {fstab {boot ""} {root ""} {user ""}} {
	set ndata ""
	set fd [open $fstab r]
	set data [read $fd]
	foreach d [split $data "\n"] {
		set filesystem ""
		regexp {^([^#]\S+)\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+).*} $d match filesystem mountpoint type options dump pass
		if { [info exists filesystem] } {
			if {$filesystem != ""} {
				if {$mountpoint == "/" && $root != ""} {
					regsub -all $filesystem $d $root d
				} elseif {$mountpoint == "/boot" && $boot != ""} {
					regsub -all $filesystem $d $boot d
				} elseif {$mountpoint == "/usr/local" && $user != ""} {
					regsub -all $filesystem $d $user d
				}
			}
		}
		append ndata "${d}\n"
	}
	close $fd

	set fd [open $fstab w]
	puts -nonewline $fd $ndata
	close $fd
}

proc ::rmupdate::mount_image_partition {image partition mountpoint} {
	variable loop_dev

	write_log 3 "Mounting parition ${partition} of image ${image}."

	set p [get_partion_start_end_and_size $image $partition]
	write_log 4 "Partiton start=[lindex $p 0], size=[lindex $p 2]."

	file mkdir $mountpoint
	catch {exec /bin/umount "${mountpoint}"}
	catch {exec /sbin/losetup -d $loop_dev}
	exec /sbin/losetup -o [lindex $p 0] $loop_dev "${image}"
	exec /bin/mount $loop_dev -o ro "${mountpoint}"
}

proc ::rmupdate::mount_system_partition {partition mountpoint} {
	set sys_dev [get_system_device]
	set remount 1
	set root_partition_number [get_current_root_partition_number]

	if {$partition == 1} {
		set partition "/boot"
	} elseif {$partition == 2 || $partition == 3} {
		if {$partition == $root_partition_number} {
			set partition "/"
		} else {
			set partition [get_partition_device $sys_dev $partition]
			set remount 0
		}
	} elseif {$partition == 4} {
		set partition "/usr/local"
	}

	if {$remount} {
		write_log 3 "Remounting filesystem ${partition} (rw)."
	} else {
		write_log 3 "Mounting device ${partition} (rw)."
	}

	if {![file exists $mountpoint]} {
		file mkdir $mountpoint
	}

	if {$remount} {
		if {$partition != $mountpoint} {
			exec /bin/mount -o bind $partition "${mountpoint}"
		}
		exec /bin/mount -o remount,rw "${mountpoint}"
	} else {
		catch {exec /bin/umount "${mountpoint}"}
		exec /bin/mount -o rw $partition "${mountpoint}"
	}
}

proc ::rmupdate::umount {device_or_mountpoint} {
	if {$device_or_mountpoint == "/boot"} {
		exec /bin/mount -o remount,ro "${device_or_mountpoint}"
	} else {
		exec /bin/umount "${device_or_mountpoint}"
	}
}

proc ::rmupdate::get_filesystem_size_and_usage {device_or_mountpoint} {
	set data [exec /bin/df]
	foreach d [split $data "\n"] {
		regexp {^(\S+)\s+\d+\s+(\d+)\s+(\d+)\s+\d+%\s(\S+)\s*$} $d match device used available mountpoint
		if { [info exists device] } {
			if {$device == $device_or_mountpoint || $mountpoint == $device_or_mountpoint} {
				return [list [expr {$used*1024+$available*1024}] [expr {$used*1024}]]
			}
		}
	}
	return [list -1 -1]
}

proc ::rmupdate::check_sizes {image} {
	variable mnt_img
	variable mnt_sys

	write_install_log "Checking size of filesystems."

	file mkdir $mnt_img
	file mkdir $mnt_sys

	foreach partition [list 1 2] {
		mount_image_partition $image $partition $mnt_img
		mount_system_partition $partition $mnt_sys

		set su_new [get_filesystem_size_and_usage $mnt_img]
		set new_used [lindex $su_new 1]
		set su_cur [get_filesystem_size_and_usage $mnt_sys]
		set cur_size [lindex $su_cur 0]

		write_log 4 "Current filesystem (${partition}) size: ${cur_size}, new filesystem used bytes: ${new_used}."

		umount $mnt_img
		umount $mnt_sys

		if { [expr {$new_used*1.05}] > $cur_size && [expr {$new_used+50*1024*1024}] >= $cur_size } {
			#error "Current filesystem of partition $partition (${cur_size} bytes) not big enough (new usage: ${new_used} bytes)."
			error [format [i18n "Current filesystem of partition %d (%d bytes) not big enough (new usage: %d bytes)."] $partition $cur_size $new_used]
		}
	}
	write_log 3 "Sizes of filesystems checked successfully."
}

proc ::rmupdate::update_filesystems {image {dryrun 0}} {
	variable log_level
	variable mnt_img
	variable mnt_sys

	set sys_dev [get_system_device]
	set root_partition_number [get_current_root_partition_number]

	write_install_log "Updating filesystems."

	file mkdir $mnt_img
	file mkdir $mnt_sys

	foreach img_partition [list 2 1] {
		set sys_partition $img_partition
		set mnt_s $mnt_sys
		if {$img_partition == 2 && $root_partition_number == 2} {
			set sys_partition 3
		}
		if {$sys_partition == 1} {
			set mnt_s "/boot"
		}
		write_install_log "Updating system partition %s." $sys_partition

		mount_image_partition $image $img_partition $mnt_img
		mount_system_partition $sys_partition $mnt_s

		if {$log_level >= 4} {
			write_log 4 "ls -la ${mnt_img}"
			write_log 4 [exec ls -la ${mnt_img}]
			write_log 4 "ls -la ${mnt_s}"
			write_log 4 [exec ls -la ${mnt_s}]
		}
		write_log 3 "Rsyncing filesystem of partition ${sys_partition}."
		if [catch {
			set out ""
			if {$dryrun} {
				write_log 4 "rsync --dry-run --progress --archive --one-file-system --delete ${mnt_img}/ ${mnt_s}"
				set out [exec rsync --dry-run --progress --archive --one-file-system --delete ${mnt_img} ${mnt_s}]
			} else {
				write_log 4 "rsync --progress --archive --one-file-system --delete ${mnt_img}/ ${mnt_s}"
				set out [exec rsync --progress --archive --one-file-system --delete ${mnt_img}/ ${mnt_s}]
			}
			write_log 4 $out
		} err] {
			write_log 4 $err
		}
		write_log 3 "Rsync finished."
		if {$log_level >= 4} {
			write_log 4 "ls -la ${mnt_img}"
			write_log 4 [exec ls -la ${mnt_img}]
			write_log 4 "ls -la ${mnt_s}"
			write_log 4 [exec ls -la ${mnt_s}]
		}

		if {$img_partition == 2} {
			if {![file exists "/usr/bin/mkimage"] && [file exists "${mnt_s}/usr/bin/mkimage"]} {
				file copy -force ${mnt_s}/usr/bin/mkimage /tmp/mkimage
			}
		}

		if {$img_partition == 1} {
			write_install_log "Updating boot configuration."
			if {!$dryrun} {
				set new_root_partition_number 2
				if {$root_partition_number == 2} {
					set new_root_partition_number 3
				}
				set part_uuid [get_part_uuid $sys_dev $new_root_partition_number]
				if {[file exists "${mnt_s}/boot.scr"]} {
					update_boot_scr "${mnt_s}/boot.scr" $new_root_partition_number 4
				} elseif {[file exists "${mnt_s}/extlinux/extlinux.conf"]} {
					update_cmdline "${mnt_s}/extlinux/extlinux.conf" "PARTUUID=${part_uuid}"
				} elseif {[file exists "${mnt_s}/cmdline.txt"]} {
					update_cmdline "${mnt_s}/cmdline.txt" "PARTUUID=${part_uuid}"
				}
			}
		}

		umount $mnt_img
		umount $mnt_s
	}
}

proc ::rmupdate::move_userfs_to_device {target_device {sync_data 0} {repartition 0}} {
	variable mnt_sys

	set current [get_current_firmware_version]
	set versions [list $current "2.31.25.20180226"]
	set versions [lsort -decreasing -command compare_versions $versions]
	if {[lindex $versions 0] != $current} {
		# Old firmware needs udev patch
		exec /bin/mount -o remount,rw /

		set fd [open "/lib/udev/rules.d/usbmount.rules" "w"]
		puts $fd {ENV{ID_FS_LABEL}=="bootfs|rootfs|rootfs1|rootfs2|userfs", GOTO="END"}
		puts $fd {KERNEL=="sd*", DRIVERS=="sbp2",	 ACTION=="add",	RUN+="/usr/share/usbmount/usbmount add"}
		puts $fd {KERNEL=="sd*", SUBSYSTEM=="block", ACTION=="add",	RUN+="/usr/share/usbmount/usbmount add"}
		puts $fd {KERNEL=="ub*", SUBSYSTEM=="block", ACTION=="add",	RUN+="/usr/share/usbmount/usbmount add"}
		puts $fd {KERNEL=="sd*", ACTION=="remove", RUN+="/usr/share/usbmount/usbmount remove"}
		puts $fd {KERNEL=="ub*", ACTION=="remove", RUN+="/usr/share/usbmount/usbmount remove"}
		puts $fd {LABEL="END"}
		close $fd

		exec /bin/mount -o remount,ro /
	}

	if {![file exists $target_device]} {
		error [i18n "Target device does not exist."]
	}

	set target_partition_device ""
	if {[get_disk_device $target_device] != $target_device} {
		set target_partition_device $target_device
		set target_device [get_disk_device $target_partition_device]
		set repartition 0
	}

	set source_partition_device [get_mounted_device "/usr/local"]
	set source_device [get_disk_device $source_partition_device]

	if {$source_partition_device == "" || $source_device == ""} {
		error [i18n "Failed to find source device for /usr/local."]
	}
	if {$source_device == $target_device} {
		error [i18n "Source and target are the same device."]
	}

	if {$target_partition_device == ""} {
		array set partitions [get_partitions $target_device]
		set keys [array names partitions]
		set partition_number 0
		if {$repartition == 1} {
			foreach key $keys {
				regexp {^(.+)::([^:]+)$} $key match id opt
				if {$opt == "partition_device"} {
					catch { exec /bin/umount $partitions($key) }
				}
			}
			set exitcode [catch {
				exec /usr/sbin/parted --script ${target_device} \
				mklabel msdos \
				mkpart primary ext4 0% 100%
			} output]
			if { $exitcode != 0 && $exitcode != 1 } {
				error $output
			}
			set partition_number 1
		} else {
			foreach key $keys {
				regexp {^(.+)::([^:]+)$} $key match id opt
				if {$opt == "filesystem_label"} {
					if {[regexp "^.*userfs$" $partitions($key) match]} {
						set partition_number $partitions(${id}::partition)
					}
				}
			}
			if {$partition_number == 0} {
				error [format [i18n "Failed to find userfs partition on %s, and repartition is not desired."] $target_device]
			}
		}
		set target_partition_device [get_partition_device $target_device $partition_number]
	}
	
	if {$sync_data == 1} {
		catch { exec /bin/umount $target_partition_device }
		set exitcode [catch { exec /sbin/mkfs.ext4 -F -L userfs $target_partition_device } output]
		if { $exitcode != 0 && $exitcode != 1 } {
			error $output
		}
		# Write ReGaHSS state to disk
		load tclrega.so
		rega system.Save()

		file mkdir $mnt_sys
		exec /bin/mount $target_partition_device $mnt_sys
		#set shell_script "cd /usr/local; tar -c . | (cd $mnt_sys; tar -xv)"
		#set exitcode [catch { exec /bin/sh -c $shell_script } output]
		set out [exec rsync --progress --archive --one-file-system --delete /usr/local/ ${mnt_sys}]
		exec /bin/umount $mnt_sys
		if { $exitcode != 0 && $exitcode != 1 } {
			error $output
		}
	}
	
	catch { exec /sbin/tune2fs -L 0userfs $source_partition_device }
	catch { exec /sbin/tune2fs -L userfs $target_partition_device }
}

proc ::rmupdate::clone_system {target_device {activate_clone 0}} {
	variable mnt_sys

	if {![file exists $target_device]} {
		error [i18n "Target device does not exist."]
	}

	set source_device [get_system_device]
	if { $source_device == $target_device} {
		error [i18n "Source and target are the same device."]
	}


	exec /bin/mount -o remount,rw /
	exec /bin/sed -i s/ENABLED=1/ENABLED=0/ /etc/usbmount/usbmount.conf
	exec /bin/mount -o remount,ro /

	file mkdir $mnt_sys
	catch { exec /bin/umount $mnt_sys }
	catch { exec /bin/umount [get_partition_device $target_device 1] }
	catch { exec /bin/umount [get_partition_device $target_device 2] }
	catch { exec /bin/umount [get_partition_device $target_device 3] }
	catch { exec /bin/umount [get_partition_device $target_device 4] }

	set data [exec /bin/mount]
	foreach d [split $data "\n"] {
		if {[regexp {$target_device} $d match]} {
			error [i18n "Target is mounted."]
		}
	}

	set p [get_partion_start_end_and_size $source_device 1]
	set start1 [lindex $p 0]
	set end1 [lindex $p 1]
	set p [get_partion_start_end_and_size $source_device 2]
	set start2 [lindex $p 0]
	set end2 [lindex $p 1]
	set p [get_partion_start_end_and_size $source_device 3]
	set start3 [lindex $p 0]
	set end3 [lindex $p 1]
	set p [get_partion_start_end_and_size $source_device 4]
	set start4 [lindex $p 0]

	set exitcode [catch {
		exec /usr/sbin/parted --script ${target_device} \
		mklabel msdos \
		mkpart primary fat32 ${start1}B ${end1}B \
		set 1 boot on \
		mkpart primary ext4 ${start2}B ${end2}B \
		mkpart primary ext4 ${start3}B ${end3}B \
		mkpart primary ext4 ${start4}B 100%
	} output]
	if { $exitcode != 0 && $exitcode != 1 } {
		error $output
	}

	set exitcode [catch { exec /sbin/mkfs.vfat -F32 -n bootfs [get_partition_device $target_device 1] } output]
	if { $exitcode != 0} {
		error $output
	}
	set exitcode [catch { exec /sbin/mkfs.ext4 -F -L rootfs [get_partition_device $target_device 2] } output]
	if { $exitcode != 0 && $exitcode != 1 } {
		error $output
	}
	set exitcode [catch { exec /sbin/mkfs.ext4 -F -L rootfs2 [get_partition_device $target_device 3] } output]
	if { $exitcode != 0 && $exitcode != 1 } {
		error $output
	}
	set exitcode [catch { exec /sbin/mkfs.ext4 -F -L userfs [get_partition_device $target_device 4] } output]
	if { $exitcode != 0 && $exitcode != 1 } {
		error $output
	}

	set source_uuid [get_part_uuid $source_device 2]
	set target_uuid [get_part_uuid $target_device 2]

	#catch { exec /bin/umount [get_partition_device $target_device 1] }
	#catch { exec /bin/umount [get_partition_device $target_device 2] }
	#catch { exec /bin/umount [get_partition_device $target_device 3] }
	#catch { exec /bin/umount [get_partition_device $target_device 4] }

	exec /bin/mount [get_partition_device $target_device 1] $mnt_sys
	set shell_script "cd /boot; tar -c . | (cd $mnt_sys; tar -xv)"
	set exitcode [catch { exec /bin/sh -c $shell_script } output]
	if { $exitcode == 0 || $exitcode == 1 } {
		# Update boot config for cloned system
		update_cmdline "${mnt_sys}/cmdline.txt" "PARTUUID=${target_uuid}"
	}
	exec /bin/umount $mnt_sys
	if { $exitcode != 0 && $exitcode != 1 } {
		error $output
	}

	for {set p 2} {$p <= 3} {incr p} {
		exec /bin/mount [get_partition_device $target_device $p] $mnt_sys
		set shell_script "cd /; tar -c --exclude=boot/* --exclude=usr/local/* --exclude=tmp/* --exclude=proc/* --exclude=sys/* --exclude=run/* . | (cd $mnt_sys; tar -xv)"
		set exitcode [catch { exec /bin/sh -c $shell_script } output]
		exec /bin/sed -i s/ENABLED=0/ENABLED=1/ ${mnt_sys}/etc/usbmount/usbmount.conf
		exec /bin/umount $mnt_sys
		if { $exitcode != 0 && $exitcode != 1 } {
			error "$output $exitcode"
		}
	}

	# Write ReGaHSS state to disk
	load tclrega.so
	rega system.Save()

	exec /bin/mount [get_partition_device $target_device 4] $mnt_sys
	set shell_script "cd /usr/local; tar -c . | (cd $mnt_sys; tar -xv)"
	set exitcode [catch { exec /bin/sh -c $shell_script } output]
	exec /bin/umount $mnt_sys
	if { $exitcode != 0 && $exitcode != 1 } {
		error $output
	}

	if {$activate_clone == 1} {
		# Relabel ext4 filesystems
		catch { exec tune2fs -L 0rootfs [get_partition_device $source_device 2] }
		catch { exec tune2fs -L 0rootfs2 [get_partition_device $source_device 3] }
		catch { exec tune2fs -L 0userfs [get_partition_device $source_device 4] }

		# Recreate old boot fs with new label (util to relabel fat32 missing)
		exec /bin/umount [get_partition_device $source_device 1]
		exec /sbin/mkfs.vfat -n 0bootfs [get_partition_device $source_device 1]
		exec /bin/mount [get_partition_device $source_device 1] /boot

		exec /bin/mount [get_partition_device $target_device 1] $mnt_sys
		set shell_script "cd $mnt_sys; tar -c . | (cd /boot; tar -xv)"
		set exitcode [catch { exec /bin/sh -c $shell_script } output]
		exec /bin/umount $mnt_sys
		if { $exitcode != 0 && $exitcode != 1 } {
			error $output
		}

		# Update boot config for cloned system
		update_cmdline "/boot/cmdline.txt" "PARTUUID=${source_uuid}"
	}

	exec /bin/mount -o remount,rw /
	exec /bin/sed -i s/ENABLED=0/ENABLED=1/ /etc/usbmount/usbmount.conf
	exec /bin/mount -o remount,ro /
}

proc ::rmupdate::get_current_firmware_version {} {
	if {[file exists "/VERSION"]} {
		set fp [open "/VERSION" r]
	} else {
		set fp [open "/boot/VERSION" r]
	}
	set data [read $fp]
	close $fp
	regexp {\s*VERSION\s*=\s*([\d\.]+)\s*} $data match current_version
	return $current_version
}

proc ::rmupdate::get_available_firmware_downloads {} {
	variable release_url
	set download_urls [list]
	set rpi_version [get_rpi_version]
	if {$rpi_version == ""} {
		return $download_urls
	}
	set data [exec /usr/bin/wget "${release_url}" --no-check-certificate -q -O-]
	foreach d [split $data ">"] {
		set href ""
		regexp {<\s*a\s+href\s*=\s*"([^"]+/releases/download/[^"]+)\.zip"} $d match href
		if { [info exists href] && $href != ""} {
			set fn [lindex [split $href "/"] end]
			set tmp [split $fn "-"]
			set v [lindex $tmp [expr {[llength $tmp] - 1}]]
			if { $v == "rpi3" && $rpi_version == "rpi2" } {
				write_log 4 "Using rpi3 package for rpi2: ${href}"
			} elseif { $v == "ova" && $rpi_version == "ova-KVM" } {
				write_log 4 "Using ova package for ova-KVM: ${href}"
			} elseif { $rpi_version != $v } {
				continue
			}
			#write_log 4 $href
			if {[string first "https://" $href] == -1} {
				set href "https://github.com${href}"
			}
			if {[lsearch -exact $download_urls "${href}.zip"] == -1} {
				lappend download_urls "${href}.zip"
			}
		}
	}
	return $download_urls
}

proc ::rmupdate::get_latest_firmware_version {{experimental 0}} {
	set versions [list]
	foreach e [get_available_firmware_downloads] {
		set version [get_version_from_filename $e]
		if {[string first "-" $version] == -1 || $experimental == 1} {
			lappend versions $version
		}
	}
	set versions [lsort -decreasing -command compare_versions $versions]
	return [lindex $versions 0]
}

proc ::rmupdate::download_firmware {{download_url ""} {version ""}} {
	variable img_dir
	variable install_log

	if {$version == ""} {
		set image_file "${img_dir}/RaspberryMatic-unknown.img"
	} else {
		set image_file "${img_dir}/RaspberryMatic-${version}.img"
	}
	if {$download_url == ""} {
		foreach e [get_available_firmware_downloads] {
			set v [get_version_from_filename $e]
			if {$v == $version} {
				set download_url $e
				break
			}
		}
	}
	if {$download_url == ""} {
		error [format [i18n "Failed to find download link for firmware %s."] $version]
	}
	write_install_log "Downloading firmware from %s." $download_url
	regexp {/([^/]+)$} $download_url match archive_file
	set archive_file "${img_dir}/${archive_file}"
	if {![file exists $img_dir]} {
		file mkdir $img_dir
	}
	if {![file exists "${img_dir}/.nobackup"]} {
		# Create marker file to exclude directory from RaspberryMatic backup
		set fd [open "${img_dir}/.nobackup" "w"]
		close $fd
	}
	if {$install_log != ""} {
		exec /usr/bin/wget "${download_url}" --show-progress --progress=dot:giga --no-check-certificate --quiet --output-document=$archive_file 2>>${install_log}
		write_install_log ""
	} else {
		exec /usr/bin/wget "${download_url}" --no-check-certificate --quiet --output-document=$archive_file
	}

	write_install_log ""
	write_install_log "Download completed."

	if {[regexp {.*\.zip$} $archive_file match]} {
		write_install_log "Extracting firmware %s.\nThis process takes some minutes, please be patient..." [file tail $archive_file]
		set data [exec /usr/bin/unzip -ql "${archive_file}" 2>/dev/null]
		set img_file ""
		foreach d [split $data "\n"] {
			regexp {\s+(\S+\.img)\s*$} $d match img_file
			if { $img_file != "" } {
				break
			}
		}
		if { $img_file == "" } {
			error [i18n "Failed to extract firmware image from archive."]
		}
		exec /usr/bin/unzip "${archive_file}" "${img_file}" -o -d "${img_dir}" 2>/dev/null
		set img_file "${img_dir}/${img_file}"
		file delete $archive_file
	} else {
		set img_file $archive_file
	}
	#puts "${img_file} ${image_file}"
	if {$version == ""} {
		set image_file $img_file
	}
	if {$img_file != $image_file} {
		file rename $img_file $image_file
	}
	return $image_file
}

proc ::rmupdate::get_available_firmware_images {} {
	variable img_dir
	file mkdir $img_dir
	return [glob -nocomplain "${img_dir}/*.img"]
}

proc ::rmupdate::get_version_from_filename {filename} {
	set fn [file rootname [file tail $filename]]
	set tmp [split $fn "-"]
	set version [lindex $tmp 1]
	if {[llength $tmp] == 4} {
		append version "-" [lindex $tmp 2]
	}
	#regexp {\-([\d\.]+)\.[^\.]+-*.*$} $filename match version
	return $version
}

proc ::rmupdate::get_firmware_info {} {
	variable release_url
	variable support_file_url

	set data [exec /usr/bin/wget "${support_file_url}" --no-check-certificate -q -O-]
	if { ! [regexp {\"latest_supported_version\"\s*:\s*\"([^\"]+)\"} $data match latest_supported_version] } {
		write_log 1 "Failed to get latest supported version from ${support_file_url}"
		return "\[\]"
	}
	
	set versions [list]
	set current [get_current_firmware_version]
	set experimental_version ""
	foreach e [get_available_firmware_downloads] {
		set version [get_version_from_filename $e]
		if {$version != "unknown"} {
			set downloads($version) $e
			if {[string first "-" $version] != -1} {
				set experimental_version $version
			} elseif {[lsearch $versions $version] == -1} {
				lappend versions $version
			}
		}
	}
	set versions [lsort -decreasing -command compare_versions $versions]
	set latest [lindex $versions 0]
	
	if {$experimental_version != ""} {
		if {[lsearch $versions $experimental_version] == -1} {
			set tmp [split $experimental_version "-"]
			# experimental version != latest version
			lappend versions $experimental_version
			if {[lindex $tmp 0] == $current && $current != $latest} {
				# assuming that experimental version is installed
				set current $experimental_version
			}
		}
	}
	foreach e [get_available_firmware_images] {
		set version [get_version_from_filename $e]
		if {$version != "unknown"} {
			set images($version) $e
			if {[lsearch $versions $version] == -1} {
				lappend versions $version
			}
		}
	}
	if {[lsearch $versions $current] == -1} {
		lappend versions $current
	}
	set versions [lsort -decreasing -command compare_versions $versions]
	
	set json "\["
	set latest_version ""
	foreach v $versions {
		set experimental "false"
		set latest "false"
		if {[string first "-" $v] != -1} {
			set experimental "true"
		} else {
			if {$latest_version == ""} {
				set latest_version $v
				set latest "true"
			}
		}
		set installed "false"
		if {$v == $current} {
			set installed "true"
		}
		set supported "false"
		if {[compare_versions $v "2.31.25.20180324"] > 0} {
			set supported "true"
		} elseif {[compare_versions $latest_supported_version $v] >= 0} {
			set supported "true"
		}
		set image ""
		catch { set image $images($v) }
		set url ""
		catch { set url $downloads($v) }
		set info_url "${release_url}/tag/${v}"
		if {$experimental == "true"} {
			set info_url "${release_url}/tag/snapshots"
		}
		append json "\{\"version\":\"${v}\",\"installed\":${installed},\"latest\":${latest},\"experimental\":${experimental},\"supported\":${supported},\"url\":\"${url}\",\"info_url\":\"${info_url}\",\"image\":\"${image}\"\},"
		set latest "false"
	}
	if {[llength versions] > 0} {
		set json [string range $json 0 end-1]
	}
	append json "\]"
	return $json
}

proc ::rmupdate::set_running_installation {installation_info} {
	variable install_lock
	variable install_log

	write_log 4 "Set running installation: ${installation_info}"

	foreach var {install_log install_lock} {
		set var [set $var]
		if {$var != ""} {
			set basedir [file dirname $var]
			if {![file exists $basedir]} {
				file mkdir $basedir
			}
		}
	}

	if {$installation_info != ""} {
		set fd [open $install_lock "w"]
		puts $fd [pid]
		puts $fd $installation_info
		close $fd

		if {[file exists $install_log]} {
			write_log 4 "Deleting: ${install_log}"
			file delete $install_log
		}
	} elseif {[file exists $install_lock]} {
		file delete $install_lock
	}
}

proc ::rmupdate::get_running_installation {} {
	variable install_lock

	if {! [file exists $install_lock]} {
		return ""
	}

	set fp [open $install_lock "r"]
	set data [read $fp]
	close $fp

	set tmp [split $data "\n"]
	set lpid [string trim [lindex $tmp 0]]
	set installation_info [string trim [lindex $tmp 1]]

	if {[file exists "/proc/${lpid}"]} {
		return $installation_info
	}

	write_log 4 "Deleting: ${install_lock}"
	file delete $install_lock
	return ""
}

proc ::rmupdate::delete_firmware_image {version} {
	variable img_dir
	eval {file delete [glob "${img_dir}/*${version}*.img"]}
	catch { eval {file delete [glob "${img_dir}/*${version}*.zip"]} }
}

proc ::rmupdate::install_firmware {{download_url ""} {version ""} {lang ""} {reboot 1} {keep_download 0} {dryrun 0}} {
	variable language
	variable addon_dir
	if {[regexp {^([a-z]][a-z])} $lang match l]} {
		set language [string tolower $l]
	}
	if {[get_running_installation] != ""} {
		error [i18n "Another install process is running."]
	}
	if {! [is_system_upgradeable $version]} {
		error [i18n "System not upgradeable."]
	}
	
	set firmware_image ""
	if {$version == ""} {
		set_running_installation "Firmware unknown"
	} else {
		set_running_installation "Firmware ${version}"
		foreach e [get_available_firmware_images] {
			set v [get_version_from_filename $e]
			if {$v == $version} {
				set firmware_image $e
				break
			}
		}
	}

	if {$firmware_image == ""} {
		set firmware_image [download_firmware $download_url $version]
	}

	set sys_dev [get_system_device]
	
	set use_recovery [is_recoveryfs_available]
	if {$use_recovery && $version != ""} {
		if {[compare_versions $version "2.31.25.20180324"] <= 0} {
			set use_recovery 0
		}
	}
	
	if {$use_recovery} {
		# Use recovery system firmware update feature
		write_install_log "Using recovery system to update firmware."
		set usr_local "/usr/local"
		
		# Test if userfs is on the same device as bootfs
		set boot_dev ""
		set user_dev ""
		set user_part ""
		set user0_part ""
		set use_user0 0
		foreach d [split [exec /sbin/blkid] "\n"] {
			if {[regexp {^(/dev.*)(\d):.*LABEL="([^"]+)"} $d match dev pnum lab]} {
				if {$lab == "bootfs"} {
					set boot_dev $dev
				} elseif {$lab == "userfs"} {
					set user_dev $dev
					set user_part "${dev}${pnum}"
				} elseif {$lab == "0userfs"} {
					set user0_part "${dev}${pnum}"
				}
			}
		}
		if {!$dryrun} {
			if {$boot_dev != "" && $user_dev != "" && $boot_dev != $user_dev} {
				if {$user0_part == ""} {
					error "userfs0 not found"
				}
				set usr_local "/tmp/mnt_user0"
				set use_user0 1
				if {[file exists $usr_local]} {
					catch {exec /bin/umount "${usr_local}"}
				} else {
					file mkdir $usr_local
				}
				catch {exec /bin/mount $user0_part "${usr_local}"}
			}
			set tmp_dir "${usr_local}/tmp"
			catch { file mkdir $tmp_dir }
			catch { file delete "${tmp_dir}/new_firmware.img" }
			catch { file delete "${usr_local}/.firmwareUpdate" }
			if {$version == "" || $keep_download == 0} {
				file rename -force $firmware_image "${tmp_dir}/new_firmware.img"
			} else {
				file copy -force $firmware_image "${tmp_dir}/new_firmware.img"
			}
			catch { exec ln -sf "/usr/local/tmp" "${usr_local}/.firmwareUpdate" }
			
			set fd [open "${usr_local}/.recoveryMode" "w"]
			close $fd
			
			file copy -force "${addon_dir}/firmware_update_script" "${tmp_dir}/update_script"
			file attributes "${tmp_dir}/update_script" -permissions 0755
			if { [get_filesystem_label $sys_dev 3] == "rootfs2" } {
				exec /bin/sed -i s/REPARTITION=0/REPARTITION=1/ "${tmp_dir}/update_script"
				# Ensure correct partition number for userfs
				exec /bin/mount -o remount,rw "/boot"
				update_boot_scr "/boot/boot.scr" 2 4
				exec /bin/mount -o remount,ro "/boot"
			}
			
			set ptuuid ""
			catch { set ptuuid [exec blkid -s PTUUID -o value $sys_dev] }
			if { $ptuuid != "deedbeef" } {
				write_log 3 "Update mbr signature"
				catch { exec /bin/echo -en "\\xef\\xbe\\xed\\xde" | /bin/dd of=$sys_dev conv=notrunc seek=440 bs=1 }
			}
			
			#exec /bin/mount -o remount,rw "/boot"
			#set fd [open "/boot/recoveryfs-sshpwd" "w"]
			#puts -nonewline $fd "rmupdate"
			#close $fd
			#exec /bin/mount -o remount,ro "/boot"
			
			if {$use_user0} {
				exec /bin/sed -i s/RELABEL=0/RELABEL=1/ "${tmp_dir}/update_script"
				exec /bin/umount "${usr_local}"
				file delete $usr_local
				catch { exec /sbin/tune2fs -L 0userfs $user_part }
				catch { exec /sbin/tune2fs -L userfs $user0_part }
			}
			
			set reboot 1
		}
	} else {
		check_sizes $firmware_image
		update_filesystems $firmware_image $dryrun
		
		if {$version == ""} {
			file delete $firmware_image
		} elseif {!$keep_download && !$dryrun} {
			file delete $firmware_image
		}
	}
	
	set_running_installation ""

	if {$reboot && !$dryrun} {
		if {$use_recovery} {
			write_install_log "Recovery system will be started now, which will perform the firmware update.\nThis process takes some minutes, please be patient..."
		} else {
			write_install_log "System will reboot now."
		}
	}

	after 5000

	if {$reboot && !$dryrun} {
		exec /sbin/reboot
	}
}

proc ::rmupdate::install_latest_version {{reboot 1} {dryrun 0}} {
	variable language
	set latest_version [get_latest_firmware_version]
	return install_firmware "" $latest_version $language $reboot $dryrun
}

proc ::rmupdate::is_firmware_up_to_date {} {
	set latest_version [get_latest_firmware_version]
	write_install_log "Latest firmware version: %s" $latest_version

	set current_version [get_current_firmware_version]
	write_install_log "Installed firmware version: ${current_version}"

	if {[compare_versions $current_version $latest_version] >= 0} {
		return 1
	}
	return 0
}

proc ::rmupdate::get_addon_info {{fetch_available_version 0} {fetch_download_url 0} {as_json 0} {addon_id ""}} {
	variable rc_dir
	variable addons_www_dir
	array set addons {}
	foreach f [glob ${rc_dir}/*] {
		catch {
			set data [exec $f info]
			set id [file tail $f]
			if {$addon_id != "" && $addon_id != $id} {
				continue
			}
			set addons(${id}::id) $id
			set addons(${id}::name) ""
			set addons(${id}::version) ""
			set addons(${id}::available_version) ""
			set addons(${id}::update) ""
			set addons(${id}::config_url) ""
			set addons(${id}::operations) ""
			set addons(${id}::download_url) ""
			set addons(${id}::cgi) ""
			set addons(${id}::cgi_interpreter) ""
			foreach line [split $data "\n"] {
				regexp {^(\S+)\s*:\s*(\S.*)\s*$} $line match key value
				if { [info exists key] } {
					set keyl [string tolower $key]
					if {$keyl == "name" || $keyl == "version" || $keyl == "update" || $keyl == "config-url" || $keyl == "operations"} {
						if {$keyl == "config-url"} {
							set keyl "config_url"
						}
						set addons(${id}::${keyl}) $value
						if {$keyl == "update" && $fetch_available_version == 1} {
							catch {
								set cgi "${addons_www_dir}/[string range $value 8 end]"
								set cfd [open $cgi r]
								set cgi_data [read $cfd]
								close $cfd
								set firstline [lindex [split $cgi_data "\n"] 0]
								regexp {^#!(.*)$} $firstline match cgi_interpreter
								set cgi_interpreter [string map {"/usr/bin/env " ""} $cgi_interpreter]
								set addons(${id}::cgi) $cgi
								set addons(${id}::cgi_interpreter) $cgi_interpreter
								set ::env(QUERY_STRING) ""
								write_log 4 "exec cgi: ${cgi}"
								if { [catch {
									set tmp [string map {"\r" ""} [exec $cgi_interpreter "$cgi"]]
								} errormsg] } {
									write_log 2 "Error executing cgi ${cgi}: ${errormsg}"
								}
								set available_version [lindex [split $tmp "\n\n"] end]
								write_log 4 "available_version of ${id}: ${available_version}"
								#set available_version [exec /usr/bin/wget "http://localhost${value}" --quiet --output-document=-]
								set addons(${id}::available_version) $available_version
							}
						}
					}
					unset key
				}
			}
		}
	}
	if {$fetch_download_url == 1} {
		write_log 3 "Fetching download urls"
		foreach key [array names addons] {
			set tmp [split $key "::"]
			set addon_id [lindex $tmp 0]
			set opt [lindex $tmp 2]
			#if {$addon_id != "redmatic"} {
			#	continue
			#}
			if {$opt == "update" && $addons($key) != "" && $addons(${addon_id}::available_version) != ""} {
				set available_version $addons(${addon_id}::available_version)
				#set url "http://localhost/$addons($key)?cmd=download&version=${available_version}"
				catch {
					#write_log 4 "Get: ${url}"
					#set data [exec /usr/bin/wget "${url}" --quiet --output-document=-]
					set cgi $addons(${addon_id}::cgi)
					set cgi_interpreter $addons(${addon_id}::cgi_interpreter)
					set ::env(QUERY_STRING) "cmd=download&version=${available_version}"
					set data [exec $cgi_interpreter "$cgi"]
					write_log 4 "Response: ${data}"
					regexp {url=([^\s\"\']+)} $data match download_url
					if { [info exists download_url] } {
						if {$addon_id == "cuxdaemon" && [compare_versions $addons(cuxdaemon::version) "2.0"] < 0} {
							# URL has changed with version 2.0.0
							set download_url "https://homematic-forum.de/forum/viewtopic.php?f=37&t=15298#p121165"
						}
						write_log 4 "Extracted url from response: ${download_url}"
						set data2 ""
						catch {
							set data2 [exec /usr/bin/wget --no-check-certificate --spider "${download_url}"]
						} data2
						if {$data2 != ""} {
							regexp {Length:.*\[([^\]]+)\]} $data2 match content_type
							if { [info exists content_type] } {
								write_log 4 "Content type of ${download_url} is ${content_type}"
								if {$content_type == "application/octet-stream"} {
									write_log 3 "Download url for addon ${addon_id}: ${download_url}"
									set addons(${addon_id}::download_url) $download_url
								} else {
									# Not a direct download link
									set data3 [exec /usr/bin/wget --no-check-certificate --quiet --output-document=- "${download_url}"]
									write_log 4 $data3
									if {[regexp {meta.*http-equiv.*refresh.*url=(.*)['"][\s/>]} $data3 match href]} {
										set download_url $href
										set data3 [exec /usr/bin/wget --no-check-certificate --quiet --output-document=- "${href}"]
									}
									set best_prio 0
									set best_href ""
									regsub -all {\.} $available_version "\\." regex_version
									set regex_version "\[^\\d\]\[\\.\\-\\_v\]${regex_version}\[\\.\\-\\_\]\[^\\d\]"
									
									regsub -all {\n+} $data3 "" oneline
									regsub -all {<a} $oneline "\n<a" alines
									foreach d [split $alines "\n"] {
										if {[regexp {<a[^>]*\shref\s*=\s*"([^"]+)"[^>]*>(.*)</a} $d match href text]} {
											#write_log 4 "Processing link ${href} - ${text}"
											set filename ""
											if {[regexp {\s*(\S.+\.tar.gz)\s*} $href match fn]} {
												set filename $fn
											} elseif {[regexp {([^\s>]+\.tar.gz)\s*} $text match fn]} {
												set filename $fn
											}
											if {$filename != ""} {
												set prio 0
												if {$best_prio == 0} {
													# First link on page
													set prio [expr {$prio + 1}]
												}
												regexp $regex_version $filename m v
												if { [info exists m] } {
													# version match
													set prio [expr {$prio + 3}]
													unset m
												}
												if {[string first "download" $filename] > -1} {
													set prio [expr {$prio + 2}]
												}
												if {[string first "ccurm" $filename] > -1} {
													set prio [expr {$prio + 2}]
												}
												if {[string first "ccu3" $filename] > -1} {
													set prio [expr {$prio + 2}]
												}
												if {$prio > $best_prio} {
													set best_prio $prio
													set best_href $href
												}
												write_log 4 "Link found: filename=\"${filename}\" href=\"${href}\" prio=\"${prio}\""
											}
										}
									}
									if {$best_href != ""} {
										regsub {\?.*} $download_url "" noquery
										regsub {/[^/]+$} $noquery "" base_url
										set tmp2 [split $download_url "/"]
										if {[string first "http://" $best_href] == 0} {
											# absolute link
										} elseif {[string first "https://" $best_href] == 0} {
											# absolute link
										} elseif {[string first "/" $best_href] == 0} {
											set best_href "[lindex $tmp2 0]//[lindex $tmp2 2]${best_href}"
										} else {
											regsub {^./} $best_href "" best_href
											set best_href "${base_url}/${best_href}"
										}
										write_log 3 "Download url for addon ${addon_id}: ${best_href}"
										set addons(${addon_id}::download_url) $best_href
									}
								}
							}
						}
					}
				}
			}
		}
	}

	if {$as_json == 1} {
		return [array_to_json [array get addons]]
	} else {
		return [array get addons]
	}
}

proc ::rmupdate::uninstall_addon {addon_id} {
	variable rc_dir

	if {[get_running_installation] != ""} {
		error [i18n "Another install process is running."]
	}

	set_running_installation "Addon ${addon_id}"

	write_log 3 "Uninstalling addon"
	if { [catch {
		exec "${rc_dir}/${addon_id}" uninstall
	} errormsg] } {
		write_log 2 "${rc_dir}/${addon_id} uninstall failed: ${errormsg}"
	}

	write_log 3 "Addon ${addon_id} successfully uninstalled"

	set_running_installation ""

	return [format [i18n "Addon %s successfully uninstalled."] $addon_id]
}

proc ::rmupdate::install_addon {{addon_id ""} {download_url ""}} {
	variable rc_dir

	if {[get_running_installation] != ""} {
		error [i18n "Another install process is running."]
	}

	if {$addon_id != ""} {
		array set addon [get_addon_info 1 1 0 $addon_id]
		set download_url $addon(${addon_id}::download_url)
	}

	if {$download_url == ""} {
		error [i18n "Download url missing."]
	}
	if {$addon_id == ""} {
		set addon_id "unknown"
	}

	set_running_installation "Addon ${addon_id}"

	set archive_file ""
	regexp {^file://(.*)$} $download_url match archive_file
	if { [info exists archive_file] && $archive_file != "" } {
		write_log 3 "Installing addon from local file ${archive_file}."
	} else {
		write_log 3 "Downloading addon from ${download_url}."
		set archive_file "/tmp/${addon_id}.tar.gz"
		if {[file exists $archive_file]} {
			file delete $archive_file
		}
		exec /usr/bin/wget "${download_url}" --no-check-certificate --quiet --output-document=$archive_file
	}

	write_log 3 "Extracting archive ${archive_file}."
	set tmp_dir "/tmp/rmupdate_addon_install_${addon_id}"
	if {[file exists $tmp_dir]} {
		file delete -force $tmp_dir
	}
	file mkdir $tmp_dir

	cd $tmp_dir
	exec /bin/tar --no-same-owner -xzvf "${archive_file}"

	write_log 3 "Running update_script"
	file attributes update_script -permissions 0755
	if { [catch {
		exec ./update_script HM-RASPBERRYMATIC
	} errormsg] } {
		write_log 2 "Addon update_script failed: ${errormsg}"
	}

	cd /tmp

	file delete -force $tmp_dir
	file delete $archive_file

	write_log 3 "Restarting addon"
	if { [catch {
		exec "${rc_dir}/${addon_id}" restart
	} errormsg] } {
		write_log 2 "Addon restart failed: ${errormsg}"
	}

	write_log 3 "Addon ${addon_id} successfully installed"

	set_running_installation ""

	return [format [i18n "Addon %s successfully installed."] $addon_id]
}

proc ::rmupdate::wlan_get_blocked {{device "wlan0"}} {
	set data [exec /usr/sbin/rfkill]
	foreach d [split $data "\n"] {
		if { [regexp {^\s*(\d+)\s+(\S+)\s+\S+(\d+)\s+(\S+)\s+(\S+)\s*$} $d match id type num soft hard] } {
			if {"${type}${num}" == $device} {
				if {$soft == "blocked"} {
					return 1
				} else {
					return 0
				}
			}
		}
	}
}

proc ::rmupdate::wlan_set_blocked {block {device "wlan0"}} {
	set data [exec /usr/sbin/rfkill]
	foreach d [split $data "\n"] {
		if { [regexp {^\s*(\d+)\s+(\S+)\s+\S+(\d+)\s+(\S+)\s+(\S+)\s*$} $d match id type num soft hard] } {
			if {"${type}${num}" == $device} {
				if {$soft == "blocked" && $block == 0} {
					write_log 4 "Unblock ${device} (${id})"
					catch { exec /usr/sbin/rfkill unblock $id }
				} elseif {$soft == "unblocked" && $block == 1} {
					write_log 4 "Block ${device} (${id})"
					catch { exec /usr/sbin/rfkill block $id }
				}
			}
		}
	}
}

proc ::rmupdate::wlan_scan {{as_json 0} {device "wlan0"}} {
	array set ssids {}
	set blocked [wlan_get_blocked $device]
	if {$blocked == 1} {
		wlan_set_blocked 0 $device
	}
	catch { exec /sbin/ip link set $device up }
	set data [exec /usr/sbin/iw $device scan]
	if {$blocked == 1} {
		wlan_set_blocked 1 $device
	}
	set cur_ssid ""
	set cur_signal ""
	set cur_connected 0
	foreach d [split $data "\n"] {
		if { [regexp {^\s*SSID:\s*(\S.*)\s*$} $d match ssid] } {
			set cur_ssid $ssid
		}
		if { [regexp {^\s*signal:\s*(\S.*)\s*$} $d match signal] } {
			set cur_signal $signal
		}
		if { [regexp {^BSS\s([a-fA-F0-9\:]+)} $d match bss] } {
			if {$cur_ssid != "" && $cur_signal != ""} {
				set ssids(${cur_ssid}::ssid) $cur_ssid
				set ssids(${cur_ssid}::signal) $cur_signal
				set ssids(${cur_ssid}::connected) $cur_connected
				set cur_ssid ""
				set cur_signal ""
				set cur_connected 0
			}
			if { [regexp {associated} $d match] } {
				set cur_connected 1
			}
		}
	}
	if {$cur_ssid != "" && $cur_signal != ""} {
		set ssids(${cur_ssid}::ssid) $cur_ssid
		set ssids(${cur_ssid}::signal) $cur_signal
	}

	if {$as_json == 1} {
		return [array_to_json [array get ssids]]
	} else {
		return [array get ssids]
	}
}

proc ::rmupdate::wlan_connect {ssid {password ""}} {
	wlan_set_blocked 0
	set psk ""
	if {$password != ""} {
		set data [exec /usr/sbin/wpa_passphrase $ssid $password]
		foreach d [split $data "\n"] {
			if { [regexp {^\s*psk\s*=\s*(\S+)\s*$} $d match p] } {
				set psk $p
			}
		}
	}
	set fd [open /etc/config/wpa_supplicant.conf "w"]
	puts $fd "ctrl_interface=/var/run/wpa_supplicant"
	puts $fd "ap_scan=1"
	puts $fd "network=\{"
	puts $fd "  ssid=\"${ssid}\""
	puts $fd "  scan_ssid=1"
	if {$psk == ""} {
		puts $fd "  key_mgmt=NONE"
	} else {
		puts $fd "  proto=WPA RSN"
		puts $fd "  key_mgmt=WPA-PSK"
		puts $fd "  pairwise=CCMP TKIP"
		puts $fd "  group=CCMP TKIP"
		puts $fd "  psk=${psk}"
	}
	puts $fd "\}"
	close $fd

	catch { exec /sbin/ifdown wlan0 }
	catch { exec /sbin/ifup wlan0 }
}

proc ::rmupdate::wlan_disconnect {} {
	set fd [open /etc/config/wpa_supplicant.conf "w"]
	puts $fd "ctrl_interface=/var/run/wpa_supplicant"
	puts $fd "ap_scan=1"
	close $fd

	catch { exec /sbin/ifdown wlan0 }
	catch { exec /sbin/ifup wlan0 }
}

proc ::rmupdate::set_camera_active {active} {
	variable raspi_fw_url
	
	catch { exec /bin/mount -o remount,rw "/boot" }
	
	set fd [open /boot/config.txt r]
	set data [read $fd]
	close $fd
	
	regsub -all "\[^\n\]*start_x\s*=\[^\n\]*\n" $data "" data
	if {$active == 1} {
		foreach fn [list /boot/start_x.elf /boot/fixup_x.dat] {
			if {![file exists $fn]} {
				exec wget --quiet "${raspi_fw_url}${fn}" -O "${fn}"
			}
		}
		regsub -line "gpu_mem\s*=.*$" $data "gpu_mem=128" data
		set data "${data}start_x=1\n"
	} else {
		regsub -line "gpu_mem\s*=.*$" $data "gpu_mem=32" data
	}
	
	set fd [open /boot/config.txt w]
	puts -nonewline $fd $data
	close $fd
	
	catch { exec /bin/mount -o remount,ro "/boot" }
}

#rmupdate::install_firmware "" "3.49.17.20200131-6867276"
#puts [rmupdate::get_latest_firmware_version]
#puts [rmupdate::get_firmware_info]
#puts [rmupdate::get_available_firmware_images]
#puts [rmupdate::get_available_firmware_downloads]
#rmupdate::download_latest_firmware
#puts [rmupdate::is_firmware_up_to_date]
#puts [rmupdate::get_latest_firmware_download_url]
#rmupdate::check_sizes "/usr/local/addons/raspmatic-update/tmp/RaspberryMatic-2.27.7.20170316.img"
#puts [rmupdate::get_partion_start_end_and_size "/dev/mmcblk0" 1]
#rmupdate::mount_image_partition "/usr/local/addons/raspmatic-update/tmp/RaspberryMatic-2.27.7.20170316.img" 1 $rmupdate::mnt_img
#rmupdate::umount $rmupdate::mnt_img
#rmupdate::mount_system_partition "/boot" $rmupdate::mnt_sys
#rmupdate::umount $rmupdate::mnt_sys
#puts [rmupdate::get_rpi_version]
#puts [rmupdate::get_part_uuid "/dev/mmcblk0p3"]
#puts [rmupdate::get_part_uuid "/dev/mmcblk0" 3]
#puts [rmupdate::get_addon_info 1 1]
#puts [rmupdate::wlan_scan 1]
#rmupdate::wlan_connect xxx yyyyy
#puts [rmupdate::get_system_device]
#puts $rmupdate::sys_dev
#rmupdate::clone_system /dev/sda 1
#puts [rmupdate::get_disk_device /dev/mmcblk0p3]
#puts [rmupdate::get_partitions]
#puts [array_to_json [rmupdate::get_partitions]]
#rmupdate::move_userfs_to_device /dev/sda1 1 0
#puts [rmupdate::get_mounted_device "/usr/local"]
#rmupdate::get_addon_info 1 1 0 "cuxdaemon"
#puts [rmupdate::get_system_device]
#rmupdate::set_camera_active 1
#rmupdate::wlan_block 0



