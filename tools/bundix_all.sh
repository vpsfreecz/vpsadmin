#!/usr/bin/env bash

for file in ./tools/bundix_*.sh ; do
	[ "$file" == "./tools/bundix_all.sh" ] && continue
	echo $file
	$file
done
