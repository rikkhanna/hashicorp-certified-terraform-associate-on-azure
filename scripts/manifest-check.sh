#!/usr/bin/env bash
set -eu

ls /codefresh/volume/manifests/*.yaml | grep -v 01 > manifests

for i in `cat manifests`; do
    echo "--------------------"
    echo "Result for Manifest - `echo $i | cut -f 5 -d "/"` "
    kubeval $i --schema-location file://../cat-kubeval/kubernetes-json-schema
done

