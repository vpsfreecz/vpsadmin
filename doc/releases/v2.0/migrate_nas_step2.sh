#!/bin/bash
# Usage: $0 <pool>
# Rename directory 'vpsAdminPrivate' to 'private' in all NAS datasets under
# <pool>.

ZFS=/sbin/zfs

function zfs {
    $ZFS $*

    if [ "$?" != 0 ]; then
        >&2 echo -e "\e[31mZFS-ERROR\e[0m";
        exit 1
    fi
}

TARGET="$1"

DATASET=`zfs list -r -Ho name $TARGET`
if [ "$?" != 0 ]
then
    exit 1
fi

for ds in $DATASET
do
    if [ "$ds" == "$TARGET" ]
    then
        continue
    fi

    echo -e "\e[34m[$ds] --->\e[0m"

    if [ -d "/$ds/vpsAdminPrivate" ]
    then
        mv "/$ds/vpsAdminPrivate" "/$ds/private"
        if [ ! -d "/$ds/private" ]
        then
            echo -e "\e[34m[$ds]\e[0m \e[31mRename private folder -> FAIL\e[0m"
            exit 1
        fi

        echo -e "\e[34m[$ds]\e[0m \e[32mRename private folder -> OK\e[0m"
    else
        echo -e "\e[34m[$ds]\e[0m \e[32mRename private folder -> ALREADY\e[0m"
    fi

    echo -e "\e[34m[$ds] <---\n\e[0m"
done
