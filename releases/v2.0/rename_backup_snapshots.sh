#!/bin/bash
# Usage: $0 <POOL>
# Removes prefix 'backup-' from snapshot names under <pool>.

ZFS=/sbin/zfs

function zfs {
    $ZFS $*

    if [ "$?" != 0 ]; then
        >&2 echo -e "\e[31mZFS-ERROR\e[0m";
        exit 1
    fi
}

TARGET="$1"

OLD_REGEX="\@backup\-[0-9]{4}\-[0-9]{2}\-[0-9]{2}T[0-9]{2}\:[0-9]{2}\:[0-9]{2}"
NEW_REGEX="\@[0-9]{4}\-[0-9]{2}\-[0-9]{2}T[0-9]{2}\:[0-9]{2}\:[0-9]{2}"

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

    LIST_DATASET_SNAPSHOTS=`zfs list -r -t snapshot -Ho name $ds`
    if [ "$?" != 0 ]
    then
        exit 1
    fi

    if [ "$LIST_DATASET_SNAPSHOTS" == "" ]
    then
        echo -e "\e[34m[$ds]\e[0m \e[33mnot found snapshots\e[0m"
        echo -e "\e[34m[$ds] <---\n\e[0m"

        continue
    fi

    for snap in $LIST_DATASET_SNAPSHOTS
    do
        if ! [ "$snap" =~ $NEW_REGEX ]
        then
            if ! [ "$snap" =~ $OLD_REGEX ]
            then
                echo -e "\e[34m[$ds]\e[0m \e[31mbad snapshot name\e[0m"
                echo -e "\e[34m[$ds]\e[0m \e[31m$snap\e[0m"
                exit 1
            fi

            echo -e "\e[34m[$ds]\e[0m \e[36mRENAME SNAPSHOT -> $snap\e[0m"
            NEW=$(echo $snap | sed "s/backup-//g")
            zfs rename "$snap" "$NEW"
            echo -e "\e[34m[$ds]\e[0m \e[32mRENAME SNAPSHOT -> OK\e[0m"
        fi
    done

    echo -e "\e[34m[$ds]\e[0m \e[32mall snapshot's name are OK\e[0m"
    echo -e "\e[34m[$ds] <---\n\e[0m"
done
