# put all disaster recovery related functions here

# on some systems the udev binaries are hidden in special directories, check for
# some commonly used ones and include them in the path
#
# Debian 3.1 uses /lib/udev
#

for d in /lib/udev ; do
	test -d "$d" && PATH=$PATH:$d
done

export PATH

if $(type -p vol_id >/dev/null) ; then
      # nothing
	:
elif $(type -p udev_volume_id >/dev/null) ; then
	# vol_id does not exist, but the older udev_volume_id is available
	# we write a little wrapper to map udev_volume_id to vol_id
	
	# output of udev_volume_id looks like this:
        # F:filesystem
        # T:ext3
        # V:
        # L:boot
        # N:boot
        # U:eddf2e10-0adb-40a8-af88-027ef9710953

	# output of vol_id (and this function) looks like this:
        # ID_FS_USAGE='filesystem'
        # ID_FS_TYPE='ext3'
        # ID_FS_VERSION=''
        # ID_FS_LABEL='boot'
        # ID_FS_LABEL_SAFE='boot'
        # ID_FS_UUID='eddf2e10-0adb-40a8-af88-027ef9710953'
	
	# NOTE: vol_id returns different exit codes depending on the error (file not found, unknown volume, ...)
	#       But udev_volume_id returns 0 even on unknown volume.
	#	To better mimic the vol_id behaviour we return 0 only if there is some real information
	#	which we detect by searching for the = sign in the KEY=VAL result produced by sed
	#	Furthermore, the grep = prevents non-KEY=VAL lines to be returned, which would confuse
	#	the calling eval $(vol_id <device>) statement.
	
	function vol_id {
		udev_volume_id "$1" | sed \
			-e "s/^F:\(.*\)$/ID_FS_USAGE='\1'/" \
			-e "s/^T:\(.*\)$/ID_FS_TYPE='\1'/" \
			-e "s/^V:\(.*\)$/ID_FS_VERSION='\1'/" \
			-e "s/^L:\(.*\)$/ID_FS_LABEL='\1'/" \
			-e "s/^N:\(.*\)/ID_FS_LABEL_SAFE='\1'/" \
			-e "s/^U:\(.*\)/ID_FS_UUID='\1'/" | grep =
	}
elif $(type -p blkid >/dev/null) ; then
	# since udev 142 vol_id was removed and udev depends on blkid
	# blkid -o udev returns the same output as vol_id used to
	#
	# NOTE: The vol_id compatible output was added to blkid at version 
	function vol_id {
		blkid -o udev -p "$1"
	}
	
	# BIG WARNING! I added this to support openSUSE 11.2 which removed vol_id between m2 and m6 (!!) by updating udev
	#
	# SADLY blkid on Fedora 10 (for example) behaves totally different. Additionally I found out that on Fedora 10 blkid comes
	# from e2fsprogs and on openSUSE 11.2m6 blkid comes from util-linux (which is util-linux-ng !)
	#
	# Just in case we do a sanity check here to make sure that *this* system sports a suitable blkid
	blkid -o udev 2>/dev/null >/dev/null || BugError "Incompatible 'blkid' on this system"
else
	test "$WARN_MISSING_VOL_ID" && \
	LogPrint "Required udev program 'udev_volume_id' or 'vol_id' could not be found !
Activating a very primitive builtin replacement that supports 
ext2/3:   LABEL and UUID
reiserfs: LABEL
xfs:      LABEL and UUID
swap:     LABEL

WARNING ! This replacement has been tested ONLY ON i386 !!
"
	function vol_id {
		case "$(file -sbL "$1")" in
		*ext*filesystem*)
			echo "ID_FS_USAGE='filesystem'"
			while IFS=: read key val junk ; do
				val="${val#* }"
				case "$key" in
				*features*)
					if expr match "$val" has_journal >/dev/null ; then
						echo "ID_FS_TYPE='ext3'"
					else
						echo "ID_FS_TYPE='ext2'"
					fi
					;;
				*name*)
					echo "ID_FS_LABEL='$val'"
					;;
				*UUID*)
					echo "ID_FS_UUID='$val'"
					;;
				esac
			done < <(tune2fs -l "$1")
			;;
		*ReiserFS*)
			echo "ID_FS_USAGE='filesystem'"
			echo "ID_FS_TYPE='reiserfs'"
			echo "ID_FS_LABEL='$(dd if="$1" bs=1 skip=$((0x10064)) count=64 2>/dev/null)'"
			;;
		*XFS*)
			echo "ID_FS_USAGE='filesystem'"
			echo "ID_FS_TYPE='xfs'"
			echo "ID_FS_LABEL='$(xfs_admin -l "$1" | cut -d \" -f 2)'"
			echo "ID_FS_UUID='$(xfs_admin -u "$1" | cut -d " " -f 3)'"
			;;
		*swap*file*)
			echo "ID_FS_USAGE='other'"
			echo "ID_FS_TYPE='swap'"
			echo "ID_FS_VERSION='2'"
			echo "ID_FS_LABEL='$(dd if="$1" bs=1 skip=$((0x41c)) count=64 2>/dev/null)'"
			;;
		*)
			Error "Unsupported filesystem found on '$1'
file says: $(file -sbL "$1")
You might try to install the proper vol_id from the udev package to support
this filesystem."
		esac
	}
fi	