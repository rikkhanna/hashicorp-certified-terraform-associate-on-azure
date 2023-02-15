#/usr/bin/env bash 
set -euo pipefail

DEBUG="${DEBUG:-FALSE}"

ACTION=${1:-"standard"}
BLUE_GREEN_DEPLOYMENT="FALSE"

if [[ "${MANIFEST_VERSION}" == "NULL" || -z "${MANIFEST_VERSION}" ]]; then 
    echo "Illegal value of VERSION detected '"${MANIFEST_VERSION}"'" 
    echo "Something has gone wrong in the gateway script" 
    exit 1
fi
if [[ "${PLATFORM}" =~ ^gke.*$ ]]; then
    ENV="gke"
    DOCKER_URL="https://artifactory.gcp.anz/artifactory/digital-cat-docker/${HELM_TEMPLATE_NAME}/${TYPE}/${APPLICATION}/${VERSION}/" 
elif [[ "${PLATFORM}" =~ ^ose.*$ ]]; then
    ENV="openshift"
    DOCKER_URL="https://artifactory.gcp.anz/artifactory/digital-cat-docker/cat-codefresh-app-images/openshift/${APP_NAME}/${VERSION}/" 
fi

echo "* Confirming availability of docker image: ${DOCKER_URL}"

HTTP_CODE=$(curl -sI -k ${DOCKER_URL} -w %{http_code}\\n -o /dev/null)
if [[ "${HTTP_CODE}" != "200" ]]; then 
    echo "Docker image not found on Artifactory server" 
    exit 1
else
    echo "Docker image found"
fi

# process default cluster override
readarray -d, -t ENV_CTX_ARRAY <<< "${NS_LIST}"

for overlay in ${ENV_CTX_ARRAY[@]}; do
    readarray -d/ -t NS_CTX_ARRAY <<< "$overlay"
    NS="${NS_CTX_ARRAY[0]}"
    
    if [[ -n "${NS_CTX_ARRAY[1]}" ]]; then
        CLUSTER="${NS_CTX_ARRAY[1]}" 
    else
        echo "/CLUSTER component of target specification of ${NS} not present"
        exit 1 
    fi

    # Manifest checks
    if [[ "${PLATFORM}" =~ ^gke.*$ ]]; then 
        if [[ "${PROD_BUILD}" == FALSE ]]; then
            MANIFEST_URL='https://artifactory.gcp.anz/artifactory/digital-cat-binaries/manifests/'${ENV}/${APPLICATION}/${APPLICATION}'%40'${MANIFEST_VERSION}'.tar.gz!/manifests/'${NS}'.yaml'
        elif [[ "${PROD_BUILD}" == TRUE ]]; then
            MANIFEST_URL='https://artifactory.gcp.anz/artifactory/digital-cat-binaries/manifests/'${ENV}/${APPLICATION}/${APPLICATION}'%40'${MANIFEST_VERSION}'.tar.gz!/manifests/'${NS}'.yaml'
            #MANIFEST_VERSION="${VERSION} 
        fi
    elif [[ "${PLATFORM}" =~ ^ose.*$ ]]; then

        if [[ "${PROD_BUILD}" == FALSE ]]; then
            MANIFEST_URL='https://artifactory.gcp.anz/artifactory/digital-cat-binaries/manifests/'${ENV}/${APP_NAME}/${APP_NAME}'%40'${VERSION}'_'${CF_BUILD_ID}'.tar.gz!/manifests/'${NS}'.yaml'
        elif [[ "${PROD_BUILD}" == TRUE ]]; then
            MANIFEST_URL='https://artifactory.gcp.anz/artifactory/digital-cat-binaries/manifests/'${ENV}/${APP_NAME}/${APP_NAME}'%40'${VERSION}'_'${CF_BUILD_ID}'.tar.gzl/manifests/'${NS}'.yaml' 
        fi
    fi
    
    echo "* Confirming availability of manifest: ${MANIFEST_URL}"

    HTTP_CODE=$(curl -sI -k -O ${MANIFEST_URL} -w %{http_code}\\n -o /dev/null) 
    if [[ "${HTTP_CODE}" != "200" ]]; then 
        echo "Manifest document not found on Artifactory server" 
        exit 1
    else
        echo "Manifest yaml found" 
    fi
    
    if [[ "${PLATFORM}" =~ ^gke.*$ ]]; then 
        if [[ "${PLATFORM}" == "gke-mks" ]]; then 
            if [[ "${CLUSTER}" =~ -PR- ]]; then
                ISTIO_CLUSTER="ECP-OPS-GKE-PR-APPDEPLOY" 
            elif [[ "${CLUSTER}" =~ -NP- ]]; then
                ISTIO_CLUSTER="ECP-OPS-GKE-NP-APPDEPLOY"
            elif [[ "${CLUSTER}" =~ -PP- ]]; then
                ISTIO_CLUSTER="ECP-OPS-GKE-PP-APPDEPLOY" 
            fi
            
            if [[ "${DEBUG}" == "FALSE" ]]; then
                
                #deploy to GKE 
                echo "Pulling manifest from Artifactory"
                curl -s -H X-Frog-Art-Api:"${ARTIFACTORY_TOKEN}" -O ${MANIFEST_URL} 
                echo "Testing for action=${ACTION}" 
                if [[ "${ACTION}" == "deploy" ]]; then
                    echo "Testing to see if we are doing a B/G deployment into namespace - ${NS}"
                    echo "The test is whether there is a bvt virtual service to apply" 
                    echo "---" > ${NS}.deploy.yaml
                    echo "---" > ${NS}.istio.yaml
                    # The sourced manifest kustomize cluster contains the application yaml and the Istio yaml. 
                    # When working on K8s cluster managed cluster the application yaml and Istio yaml need to be separated as
                    # the components are deployed separately into the workload and management cluster.

                    # Slice out the Istio rules from the combined manifest, leaving only the deployment yaml.
                    # This slicing is done because the application is deployed to the workload cluster while
                    # the Istio policies are deployed to the Istio management cluster.

                    # Looking at this now, using the exclude-kind rather the include-kind seems backwards
                    # Todo: consider changing to --include-kind
                    # Create ${Ns}.deploy.yaml

                    kubectl-slice -f ${NS}.yaml --exclude-kind DestinationRule, Gateway, ServiceEntry, virtualservice --stdout > ${NS}.deploy.yaml
                    # The presence or not of the bvt virtual service in the combined manifest is the determinate for whether we are using B/G or not.
                    # We capture the output to see if it was contained.

                    # Todo: Create a bvt gateway too.
                    bvt_present=$(kubectl-slice -f ${NS}.yaml --include-name bvt-* --stdout 2>&1 >> ${NS}.istio.yaml)
                    echo "---" >> ${NS}.istio.yaml
                    echo "BvT present test string result = ${bvt_present}"

                    if [[ "${bvt_present}" == "0 files parsed to stdout." ]]; then
                        kubecti-slice -f ${NS}.yaml --include-kind DestinationRule, Gateway, ServiceEntry, Virtualservice --stdout >> ${NS}.istio.yaml
                    else
                        kubectl-slice -f ${NS}.yaml --include-kind Gateway,serviceEntry --stdout >> ${NS}.istio.yaml
                        kubectl-slice -f ${NS}.yaml --include-kind DestinationRule --stdout >> ${NS}.istio.dr.initial.yaml
                        BLUE_GREEN_DEPLOYMENT="TRUE" 
                    fi
                    
                    echo "Triggering deployment into namespace - ${NS}" 
                    cat ${NS}.deploy.yaml
                    kubect1 config use-context ${CLUSTER} --insecure-ski-tls-verify=true
                    kubectl apply -f ${Ns}.deploy.yaml -n ${NS} --insecure-ski-tls-verify=true
                    echo "Watching status for deployment - ${NS}/${APPLICATION}-${MANIFEST_VERSION}"
                    kubectl rollout status deployment ${APPLICATION}-${MANIFEST_VERSION} -n ${NS} --watch-true --timeout=1200s --insecure-skip-tls-verify=true
                    echo "Deploying pre-requisite Istio files into namespace on managment cluster - ${NS}" 
                    cat ${Ns}.istio.yaml
                    kubectl config use-context ${ISTIO_CLUSTER} --insecure-skip-tls-verify=true 
                    kubectl apply -f ${NS}.istio.yaml -n ${NS} --insecure-skip-tls-verify=true 
                
                elif [[ "${ACTION}" == "istio" ]]; then
                    
                    echo "Deploying Istio files into namespace on managment cluster ${NS}"
                    kubectl config use-context ${ISTIO_CLUSTER} --insecure-skip-tls-verify=true 
                    echo "---" >> ${NS}.istio.yaml
                    kubectl-slice -f ${NS}.yaml --include-kind DestinationRule,virtualservice --exclude-name bvt-* --stdout > ${NS}.istio.yaml
                    if [[ -s ${NS}.istio.yaml ]]; then
                        echo "Istio yaml file called ${NS}.istio.yaml located" 
                        kubectl apply -f ${NS}.istio.yaml -n ${NS} --insecure-skip-tls-verify=true 
                        cat ${NS}.istio.yaml
                    else
                        echo "No Istio yaml file called ${NS}.istio.yaml located; likely to be blue/green enabled" 
                    fi
                elif [[ "${ACTION}" == "standard" ]]; then
                    
                    # deploy to GKE
                    echo "Deploying Istio files into namespace on managment cluster - ${NS}" 
                    kubectl config use-context ${ISTIO_CLUSTER} --insecure-skip-tIs-verify=true 
                    kubectl-slice -f ${NS}.yaml --include-kind DestinationRule, VirtualService, Gateway, serviceEntry --stdout > ${NS}.istio.yaml 
                    kubectl apply -f ${NS}.istio.yaml -n ${NS} --insecure-skip-tis-verify=true 
                    echo "Triggering deployment into namespace - ${NS}" 
                    kubectl config use-context ${CLUSTER} --insecure-skip-tls-verify=true
                    kubectl-slice -f ${NS}.yaml --exclude-kind DestinationRule, virtualservice, Gateway, ServiceEntry --stdout > ${NS}.deploy.yaml 
                    kubectI apply -f ${NS}.deploy.yaml -n ${NS} --insecure-skip-tIs-verify=true 
                    echo "Watching status for deployment - ${NS}/${APPLICATION}"
                    kubectl rollout status deployment ${APPLICATION} -n ${NS} --watch=true --timeout=1200s --insecure-skip-tls-verify-true 
                fi 
            else
                echo "DEBUG: Echoing Shared cluster GKE command set"
                echo "Deploying Istio files into namespace on managment cluster - ${NS}" 
                echo "curl -S -H X-JFrog-Art-Api:ARTIFACTORY_TOKEN -O ${MANIFEST_URL}" 
                echo "kubectl config use-context ${ISTIO_CLUSTER} --insecure-skip-tIs-verify-true"
                echo "kubectl-slice -f ${NS}.yaml --include-kind DestinationRule, Gateway, ServiceEntry, virtualService --stdout > ${NS}.istio.yaml" 
                echo "kubectl apply -f ${NS}.istio.yaml -n ${NS} --insecure-skip-tls-verify=true"
                echo "Triggering deployment into namespace - ${NS}"
                echo "kubectl config use-context ${CLUSTER} --insecure-skip-tIs-verify=true"
                echo "kubectl-slice -f ${NS}.yaml --exclude-kind Virtualservice, Gateway, ServiceEntry --stdout > ${NS}.deploy.yaml" 
                echo "kubectl apply -f ${NS}.deploy.yaml -n ${NS} --insecure-skip-tls-verify=true" 
                echo "Watching status for deployment - ${NS}/${APPLICATION}-${MANIFEST_VERSION}"
                echo "kubectl rollout status deployment ${APPLICATION}-${MANIFEST_VERSION} -n ${NS} --watch=true --timeout=1200s --insecure-skip-tls-verify=true"
            fi
        elif [[ "${PLATFORM}" == "gke-sec" ]]; then
            
            ISTIO_CLUSTER="${CLUSTER}"
            if [[ "${DEBUG}" == "FALSE" ]]; then
                # deploy to GKE
                echo "Pulling manifest from Artifactory"
                curl -s -H X-JFrog-Art-Api:"${ARTIFACTORY_TOKEN}" -o ${MANIFEST_URL}
                echo "Testing for action=${ACTION}" 
                
                if [[ "${ACTION}" == "deploy" ]]; then
                    echo "Testing to see if we are doing a B/G deployment into namespace - ${NS}" 
                    echo "The test is whether there is a bvt virtual service to apply" 
                    echo "---" > ${NS}.deploy.yaml
                    echo "---" > ${NS}.istio.yaml
                    kubectl-slice -f ${NS}.yaml --exclude-kind DestinationRule, virtualservice --stdout >> ${NS}.deploy.yaml 
                    echo "---" >> ${NS}.deploy.yaml
                    bvt_present=$(kubectl-slice -f ${NS}.yaml --include-name bvt-* --stdout 2>&1 >> ${NS}.deploy.yaml)
                    echo "${bvt_present}"
                    
                    if [[ "${bvt_present}" == "0 files parsed to stdout." ]]; then
                        kubectl-slice -f ${NS}.yaml --include-kind DestinationRule, Virtualservice --stdout >> ${NS}.istio.yaml 
                    else
                        BLUE_GREEN_DEPLOYMENT="TRUE" 
                    fi

                    echo "Triggering deployment into namespace - ${NS}" 
                    cat ${NS}.deploy.yaml
                    kubectl config use-context ${CLUSTER} --insecure-skip-tls-verify=true 
                    kubectl apply -f ${NS}.deploy.yaml -n ${NS} --insecure-skip-tls-verify=true 
                    echo "Watching status for deployment - ${NS}/${APPLICATION}-${MANIFEST_VERSION}"
                    kubectl rollout status deployment ${APPLICATION}-${MANIFEST_VERSION} -n ${NS} --watch=true --timeout=1200s --insecure-skip-tis-verifystrue

                    if [[ ${BLUE_GREEN_DEPLOYMENT} == "FALSE" ]]; then
                        
                        echo "Deploying Istio files into namespace - ${NS}" 
                        cat ${Ns}.deploy.yaml
                        kubectl apply -f ${NS}.istio.yaml -n ${NS} --insecure-skip-tls-verify=true 
                    fi
                    elif [[ "${ACTION}" == "istio" ]]; then 
                        echo "Deploying Istio files into namespace - ${NS}" 
                        kubectl config use-context ${CLUSTER} --insecure-skip-tls-verify=true
                        echo "---" > S{NS}.istio.yaml
                        kubectl-slice -f ${NS}.yaml --include-kind DestinationRule, virtualService --stdout >> ${NS}-istio.yaml 
                        echo "---" >> ${NS}.istio.yami
                        kubectl-slice -f ${NS}.yaml --exclude-name bvt-* --stout >> ${NS}.istio.yaml 
                    
                        if [[ -s ${NS}.istio.yaml ]]; then
                            echo "Istio yaml file called ${NS}.istio.yaml located" 
                            kubectl apply -f ${NS}.istio.yaml -n ${NS} --insecure-skip-tls-verify=true
                        else
                            echo "No Istio yaml file called ${NS}.istio.yaml located; likely to be blue/green enabled" 
                        fi
                    elif [[ "${ACTION}" == "standard" ]]; then
                        curl -s -H X-JFrog-Art-Api:"${ARTIFACTORY_TOKEN}" -O ${MANIFEST_URL} 
                        kubectl config use-context ${CLUSTER} --insecure-skip-tls-verify=true 
                        echo "Triggering deployment into namespace - ${NS}" 
                        kubectl apply -f ${NS}.yaml -n ${NS} --insecure-skip-tls-verify=true 
                        echo "Watching status for deployment - ${NS}/${APPLICATION}"
                        kubectl rollout status deployment ${APPLICATION} -n ${NS} --watch=true --timeout=1200s -- insecure-skip-tls-verify=true 
                    fi 
                else

                    echo "DEBUG: Echoing GKE command set"
                    echo "curl -s -H X-JFrog-Art-Api:ARTIFACTORY_TOKEN -O ${MANIFEST_URL}" 
                    echo "kubectl config use-context ${CLUSTER} --insecure-skip-tls-verify=true"
                    echo "Triggering deployment into namespace ${NS}"
                    echo "kubectl apply -f ${NS}.yaml -n ${NS} --insecure-skip-tis-verify-true" 
                    echo "Watching status for deployment - ${NS}/${APPLICATION}-${MANIFEST_VERSION}" 
                    echo "kubectl rollout status deplovment ${APPLICATION}-${MANIFEST_VERSION} -n ${NS} --watch=true --timeout=1200s --insecure-skip-tls-verify=true"
                fi 
            fi
        fi
    elif [[ "${PLATFORM}" =~ ^ose.*$ ]]; then
        echo "Pulling manifest from Artifactory"
        curl -s -H X-JFrog-Art-Api: "${ARTIFACTORY_TOKEN}" -O ${MANIFEST_URL} 
        if grep -q "kind: Job" ${NS}.yaml; then
            echo "Its a job kind" 
            export YELLOW='\033[0;33m' 
            export NOCOL='\033[Om'
            oc config use-context ${CLUSTER} --insecure-skip-tls-verify=true
            if oc get job ${APP_NAME} -n ${NS} --insecure-skip-tls-verify=true 1> /dev/null 2> /dev/null; then 
                echo " "
                echo -e "${YELLOW}Deleting existing job - ${APP_NAME}${NOCOL}"
                oc delete job ${APP_NAME} -n ${NS} --insecure-skip-tls-verify=true
                echo " "
            else
                echo
                echo -e "${YELLOW}This seems to be a non-existent job${NOCOL}"
                echo
            fi
            
            if [["${DEBUG}" == "FALSE" ]]; then
                # deploy to Openshift
                oc config use-context ${CLUSTER} --insecure-skip-tls-verify=true 
                echo "Triggering deployment into namespace - ${NS}"
                oc apply -f ${NS}.yaml -n ${NS} --insecure-skip-tls-verify=true | tee dclog 
                echo "Watching status for job - ${NS}/${APP_NAME}" 
                oc get job ${APP_NAME} -n ${NS} --insecure-skip-tls-verify=true
            else
                echo "DEBUG: Echoing OSE command set"
                echo "curl -s -H X-JFrog-Art-Api: ARTIFACTORY TOKEN -O ${MANIFEST_URL}" 
                echo "oc config use-context ${CLUSTER} --insecure-skip-tls-verify=true"
                echo "Triggering deployment into namespace - ${NS}"
                echo "oc apply -f ${NS}.yaml -n ${NS} --insecure-skip-tIs-verify=true | tee dclog" 
                echo "Watching status for job - ${NS}/${APP_NAME}"
                echo "oc get job ${APP_NAME} -n ${NS} --insecure-skip-tIs-verify=true" 
            fi
        else 
            echo "Its a deployment kind"
            if [["${DEBUG}" == "FALSE" ]]; then
                # deploy to Openshift
                # echo "Pulling manifest from Artifactory"
                # curl -s -H X-JFrog-Art-Api: "${ARTIFACTORY_TOKEN}" -O ${MANIFEST_URL} 
                oc config use-context ${CLUSTER} --insecure-skip-tls-verify=true 
                echo "Triggering deployment into namespace - ${NS}"
                oc apply -f ${NS}.yaml -n ${NS} --insecure-skip-tls-verify=true | tee dclog 
                export APP_EN=$(cat dclog | grep "service" | grep ${APP_ NAME} | cut -f2 -d "/" | cut - f1 -d " ")
                echo "Watching status for deployment - ${NS}/${APP_ENV}"
                oc rollout status deployment ${APP_ENV} -n ${NS} --watch --insecure-skip-tls-verify=true
            else
                echo "DEBUG: Echoing OSE command set"
                echo "curl -s -H X-JFrog-Art-Api:ARTIFACTORY_TOKEN -O ${MANIFEST_URL}" 
                echo "oc config use-context ${CLUSTER} --insecure-skip-tIs-verify=true" 
                echo "Triggering deployment into namespace - ${NS}"
                echo "oc apply -f ${NS}.yam] -n ${NS} --insecure-skip-tls-verify-true | tee dclog" 
                echo "export APP_ENV=$(cat dclog | grep "service" | grep ${APP_NAME} | cut -f2 -d "/" | cut -f1 -d " ")" 
                echo "Watching status for deployment - ${NS}/${APP_ENV}"
                echo "oc rollout status deployment ${APP_ENV} -n ${NS} --watch --insecure-skip-tls-verify=true"
            fi 
        fi
    else 
        echo "S(EN} not set to GKE nor OSE, forcing terminate"
        exit 1
    fi
done
echo "Exporting target namespace and cluster context" 
echo "NAME_SPACE=${NS}" >> ${CF_VOLUME_PATH} /env_vars_to_export 
echo "CLUSTER=${CLUSTER}" >> ${CF_VOLUME_PATH}/env_vars_to_export 
if [[ "${PLATFORM}" =~ ^gke.*$ ]]; then
    echo "ISTIO_CLUSTER=${ISTIO_CLUSTER}" >> ${CF_VOLUME_PATH}/env_vars_to_export 
    echo "ISTIO_YAML_DIR=${pwd}" >> ${CF_VOLUME_PATH}/env_vars_to_export
    echo "BLUE_GREEN_DEPLOYMENT=${BLUE_GREEN_DEPLOYMENT}" >> ${CF_VOLUME_PATH}/env_vars_to_export
fi


