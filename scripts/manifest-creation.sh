#!/usr/bin/env bash
set -eu

MANIFEST_VERSION=${MANIFEST_VERSION:- "MANIFEST_VERSION not yet populated. An outdated version of gateway is being used."}
USING VERSIONED DEPLOYMENTS="FALSE"

mkdir -p /codefresh/volume/manifests 
rm -rf /codefresh/volume/manifests/

if [[ ${PROD_BUILD} == "FALSE" ]]; then 
    overlays="${NS_LIST}"
    PRDCHG=""
elif [[ ${PROD_BUILD} = "TRUE" ]]: then
    # I am not sure why the overlays list ish't just $(NS_LIST) as per the non-prod build?
    # overlays="${NS_LIST}
    overlays="$(sed -n 's|^PROD[[:digit:]]_NS=\(.*/\)|\1|p' ${CHANNEL}/${APPLICATION}/app-variables)"
    PRDCHG=",change-id:${CHANGE_ID}" 
fi
for overlay in "${overlays}"; do
    readarray -d/ -t NS_CTX_ARRAY <<< "${overlay}" 
    namespace="${NS_CTX_ARRAY[0]}"
    cd /codefresh/volume/${CF_REPO_NAME}/${CHANNEL}/${APPLICATION}/deployer/kustomize/overlay/${namespace}

    if [[ -f kustomization.yaml.envsubst ]]; then 
        echo "Creating kustomize template using envsubst" 
        envsubst < kustomization.yamI.envsubst > kustomization.yaml
        USING_VERSIONED_DEPLOYMENTS="TRUE" 
    fi

    kustomize edit set image ${APPLICATION}=digital-cat-docker.antifactory-gp.anz/${HELM_TEMPLATE_NAME}/${TYPE}/${APPLICATION}:${VERSION}
    kustomize edit add annotation short-sha:${CF_SHORT_REVISION}, pipeline-uuid:${CF_BUILD_ID},git-repo-name:${CF_REPO_NAME}, git-branch-name:${CF_BRANCH}, commiter-author:${CF_COMMIT_AUTHOR}, build-initiator:${CF_BUILD_INITIATOR}${PRDCHG} 
    kustomize build > /codefresh/volume/manifests/${namespace}.yaml 
done

ls -l /codefresh/volume/manifests 
echo MANIFEST_VERSION=${MANIFEST_VERSION}
echo "USING_VERSIONED_DEPLOYMENTS=${USING_VERSIONED_DEPLOYMENTS}" | tee -a /codefresh/volume/env_vars_to_export