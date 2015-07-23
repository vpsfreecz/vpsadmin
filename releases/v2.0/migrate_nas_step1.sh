#!/bin/bash
# Usage: $0 <pool>
# Move data on all NAS datasets under <pool> to subdirectory vpsAdminPrivate/.

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

    PRIV_EXISTS=0
    PRIV_FOLDER="/$ds/vpsAdminPrivate"

    if [ ! -d "$PRIV_FOLDER" ]
    then
        mkdir "$PRIV_FOLDER"
        if [ ! -d "$PRIV_FOLDER" ]
        then
            echo -e "\e[34m[$ds]\e[0m \e[31mCreate new private folder -> FAIL\e[0m"
            exit 1
        fi

        echo -e "\e[34m[$ds]\e[0m \e[32mCreate new private folder -> OK\e[0m"
        PRIV_EXISTS=1
    else
        echo -e "\e[34m[$ds]\e[0m \e[32mCreate new private folder -> ALREADY\e[0m"
        PRIV_EXISTS=1
    fi

    if [ "$PRIV_EXISTS" == 1 ]
    then
        echo -e "\e[34m[$ds]\e[0m \e[32m-----\e[0m"
        echo -e "\e[34m[$ds]\e[0m \e[32mMove data to private folder -> START\e[0m"

        NOMOVE="vpsAdminPrivate|"
        _NOMOVE=`zfs list -r -Ho mountpoint "$ds"`
        if [[ "$?" != 0 ]]
        then
            exit 1
        fi
        
        for m in `echo $_NOMOVE`
        do
            if [ "$m" != "/$ds" ]
            then
                NOMOVE+="$m|"
            fi
        done

        NOMOVE="${NOMOVE::-1}"

        LS=`ls -d /$ds/* | grep -vE "$NOMOVE"`
        if [ "$LS" != "" ]
        then
            mv `ls -d /$ds/* | grep -vE "$NOMOVE"` "$PRIV_FOLDER"
        fi

        echo -e "\e[34m[$ds]\e[0m \e[32mMove data to private folder -> END\e[0m"
    fi

    echo -e "\e[34m[$ds] <---\n\e[0m"
done
