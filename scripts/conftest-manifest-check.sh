#!/usr/bin/env bash 
set -eu
#Count of manifest files that got created 
count_1= `ls /codefresh/volume/manifests/*.yaml | wc-l`

#Count of Prod namespaces set in variable - PROD_NS 

c1_prod=`echo $PROD_NS | tr ',' ' ' | wc -w`


declare -a conftestresults 

function runconftest {
   "$@"
    local status=$?
    if (( status != 0 )); then 
        echo "error with $2 for $3"
        conftestresults+=("problems found in $3")
    else
        conftestresults[0]="NULL" 
    fi 
return $status
}

function managetesting {
    if [ -n "${2}" ]; then 
        echo "Result for Manifest - ${2}.yaml"
        # Disable errexit while conftest is run, otherwise a yaml error stops the script
        set +e
        runconftest conftest test /codefresh/volume/manifests/${2}.yaml -p ../cat-conftest/policy/gke/common -p ../cat-conftest/policy/gke/${1}
        set -e
        echo "----------------------"
    else
        echo "Contest namespace variable is empty."
        exit 1
        echo "----------------------"
    fi
}

if [[ ${PROD_BUILD} == "FALSE" ]]; then 
    overlays="${NS_LIST}"
elif [[ ${PROD_BUILD} == "TRUE" ]]; then
    overlays="$(sed -n 's|^PROD[[:digit:]]_NS=\(.*/\)|\1|p' ${CHANNEL}/${APPLICATION}/app-variables)"
fi

#Execute conftest check for non-prod or prod depending on the value set for variable - PROD_BUILD 
for overlay in "${overlays}"; do
    readarray -d/ -t NS_CTX_ARRAY <<< "${overlay}" 
    namespace= "${NS_CTX_ARRAY[0]}"
    
    if [[ "${PROD_BUILD}" == "FALSE" ]]; then
        
        if [[ "${DEV_NS}" =~ ${namespace} ]]; then
            managetesting dev "${namespace}" 
        elif [[ "${QA_NS}" =~ ${namespace} ]]; then
            managetesting qa "${namespace}" 
        else
            echo "No namespace matches for conftest"
            exit 1 
        fi

    elif [[ "${PROD_BUILD}" == "TRUE" ]]; then
        
        count_2=$(($c1_prod))  
        
        if [ $count_1 -eq $count_2 ]; then 
            managetesting prod "${PROD_NS}"
        else
            echo "Count of namespaces mentioned in variable - PROD_NS doesn't match with the count of Prod namespaced folders in config directory"
            exit 1
        fi
    fi
done

if [[ "${conftestresults[0]}" != "NULL" ]]; then 
    printf '%s\n' "${conftestresults[@]}"
    exit 1 
fi