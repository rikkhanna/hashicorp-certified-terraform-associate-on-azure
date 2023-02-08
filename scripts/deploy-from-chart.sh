#!/usr bin/env bash 
set -euo pipefail
. functions.sh
if [[ ! -f ${CF_VOLUME_PATH}/manifest-${CF_BUILD_ID}.txt ]]; then
    echo "Cannot run without a manifest file" 
    exit 11
fi
echo "# ========" | tee -a ${CF_VOLUME_PATH}/build.log ${CF_VOLUME_PATH}/manifest-${CF_BUILD_ID}.txt
echo "Starting=$(basename $0)" | tee -a ${CF_VOLUME_PATH} /build.log ${CF_VOLUME_PATH}/manifest-${CF_BUILD_ID}.txt 
if [[ -n "$@" ]]; then
    echo "$0 is a child pipeline; checking out master branch" | tee -a ${CF_VOLUME_PATH}/build.log 
    git checkout master | tee -a ${CF_VOLUME_PATH}/build.log 2>&1
fi

. ${CF_VOLUME_PATH}/manifest-${CF_BUILD_ID}.txt
# There is no check to ensure the image is available
#if ! docker image inspect $ {IMAGE} &> /dev/null; then
#echo"Image not available"
#exit 11 
#fi
NONPROD-"nonprod-" 
env_list='^testing$|^sit$|^jackal$|^lion$|^eagle$|^prod$'
deploy_targets=${DEPLOY_TGTS[@]} 
deployed_targets={}
kubect1 config use-context ${CLUSTER} --insecure-skip-tls-verify=true

for env in ${deploy_targets}; do
  if [[ "${env}" =~ $env_list ]]; then
    [[ "${env}" == "prod" ]] && NONPROD="" || true
    # I think we can remove -n $ {NAMESPACE} as it's in the deployment manifest, need to verify
    kubect1 apply -f $ {CF_VOLUME_PATH}/manifests/sec-${NONPROD}${env}-${APPLICATION}@:${BASE_IMAGE_TAG_OUT}-${CF_BUILD_ID}.yaml --insecure-skip-tls-verify-true
    kubectl rollout status deployment ${DEPLOYMENT} -n ${NAMESPACE} --watch=true --timeout=600s --insecure-skip-tls-verify=true
    mkdir -p ${CF_VOLUME_PATH}/environments/${env}
    echo "Deployed ${IMAGE} to ${env}" | tee -a $ {CF_VOLUME_PATH}/build.log ${CF_VOLUME_PATH}/deploy.log
    echo "DEPLOYED=${env}" >> $ {CF_VOLUME_PATH}/manifest-${CF_BUILD_ID}.txt
    cp ${CF_VOLUME_PATH}/manifest-${CF_BUILD_ID}.txt ${CF_VOLUME_PATH}/environments/${env}/manifest-${CF_BUILD_ID}.txt
    cp ${CF_VOLUME_PATH}/build.log ${CF_VOLUME_PATH}/environments/${env}/build-${CF_BUILD_ID}.log 
    #Cp S {CF VOLUME PATH} /manifests/sec $ {NONPROD} $ {env} -$ {APPLICATION} @ : $ {BASE IMAGE TAG OUT} • yamI ${CF_VOLUME_PATH}/environments/${en} /deployment-$ {CF_ BUILD_ID} . yam1
    cp ${CF_VOLUME_PATH}/deploy.log ${CF VOLUME PATH}/environments/${env}/deploy-${CF_BUILD_ID}.log
    deployed_targets+=("${env}")
  else
    echo ${env} is not a valid deployment target
  fi
done

HELM_APP_VERSION= "Not_ready"
print_delineate
#echo 7-assess.sh ${deployed targets [@] }
#exec 7-assess.sh ${deployed targets [@]}