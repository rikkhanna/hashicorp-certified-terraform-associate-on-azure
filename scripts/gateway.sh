#!/usr/bin/env bash
set -euo pipefail
DEBUG="${DEBUG:-FALSE}"
# This script, like it's peers runs in the ${APP} directory.
# Check git version
GIT_VERSION=$(git version)

if [[ "${GIT_VERSIONS}" != "git version 2.31.1" ]]; then 
    echo "ERROR: This script is only qualified against git version 2.31.1" 
    exit 1
elif [[ "${GIT _VERSIONS}" == "git version 2.31.1" ]]; then 
    echo "NOTE: git version 2.31.1 satisfies requirements" 
fi

# Set some variables
PLATFORM=${PLATFORM:-"NULL"}
echo "PLATFORM=${PLATFORM}"

if [[ "${PLATFORM}" =~ ^gke.* && ! "${PLATFORM}" =~ "ose" ]]; then
    echo "This script requires a PLATFORM variable set to either 'gke' or 'ose'; exiting."
    exit 1
fi

export BLUE='\033[0;36m' 
export GREEN='\033[0;32m'
export YELLOW-'\033[0;33m' 
export RED='\033[0;31m'
export NOCOL='\033[om'

echo -e "${BLUE}==> STAGE: Setting up ${NOCOL}"

. VERSION
. app-variables

alias git="git --no-pager"

# Initialise desion making variables
# Todo: remove MAIN_APP_CHANGE_VAR
MAIN_APP_CHANGED="FALSE"
KUSTOMIZE_BASE_CHANGED="FALSE"
GRADLE_APP_CHANGED="FALSE"
REBUILD_GRADLE_JAR="FALSE"
APP_VARS_NS_CHANGED="FALSE"
KUSTOMIZE_OVERLAY_NS_CONFIG_CHANGED="FALSE"
BASE_IN_VER_CHANGED="FALSE"
REBUILD_IMAGE="FALSE"
REDEPLOY_IMAGE="FALSE"
USE_PROMOTE_IMAGE_TAG="FALSE"
IMAGE_TAG_WAS_DERIVED="FALSE"
VERSION_CHANGED="FALSE"
DEFAULT_NS_USED="FALSE"
NS_LIST="NULL"
APP_VARS_NS_MOD="NULL"
VERSION="NULL"

GIT_BRANCH=$(git branch --show-current)
GIT_SHA=${CF_SHORT_REVISION:-$(git rev-list --abbrev-commit --abbrev=7 -1 HEAD)}
CHANGE_SHA="NULL"

MANIFEST_VERSION_DOTTED="${BASE_IMAGE_TAG_OUT}.${GIT_SHA}"
MANIFEST_VERSION="${MANIFEST_VERSION_DOTTED//./-}"

# Identify is the HEAD we are on is a merge commit
# Due to the nature of rev-list we will get the current SHA + parent count
COMMIT_COUNT=$(git rev-list -n1 HEAD --parents | wc -w)
PARENT1_SHA=$(git rev-list -n1 HEAD --parents | cut -f2 -d " ")

echo_status () {
    echo
    echo "REBUILD_IMAGE = ${REBUILD IMAGE}"
    echo "REBUILD_GRADLE_JAR = ${REBUILD_GRADLE_JAR}"
    echo "REDEPLOY_IMAGE = ${REDEPLOY_IMAGE}"
    echo "USE_PROMOTE_IMAGE_TAG = ${USE_PROMOTE_IMAGE_TAG}"
    echo "APP_VARS_NS_MOD = ${APP_VARS_NS_MOD[@]}"
    echo "NS LIST = ${NS_LIST[@]}"
    echo "VERSION = ${VERSION}"
}
echo_decisions () {
    echo
    echo -e "${GREEN}PROCESSING END. ${NOCOL}" 
    echo "MAIN_APP_CHANGED = ${MAIN _APP. CHANGED}"
    echo "KUSTOMIZE_BASE_CHANGED = ${KUSTOMIZE_BASE_CHANGED}"
    echo "KUSTOMIZE_OVERLAYS_CHANGED = ${KUSTOMIZE_OVERLAY_NS_CONFIG_CHANGED}"
    echo "APP_VARS_NS_CHANGED = ${APP_VARS_NS_CHANGED}"
    echo "VERSION_FILE_CHANGED = ${VERSION_CHANGED}"
    echo
    echo REBUILD_IMAGE_REASON ="${REBUILD_IMAGE_REASON[@]:-"N/A"}" 
    echo IMAGE_TAG_WAS_DERIVED_FROM ="${IMAGE_TAG_WAS_DERIVED_FROM[@]:-"N/A"}"
    echo
    echo -e "${GREEN}DECISION DATA: ${NOCOL}" 
    echo -e "BRANCH=${GIT BRANCH}" 
    echo "BASE_IMAGE_IN=${BASE_IMAGE_IN}" | tee -a /codefresh/volume/env_vars_to_export 
    echo "BASE_IMAGE_TAG_IN=${BASE_IMAGE_TAG_IN}" | tee -a / codefresh/volume/env_vars_to_export 
    echo "REBUILD_IMAGE=${REBUILD_IMAGE}" | tee -a /codefresh/volume/env_vars_to_export 
    echo "REDEPLOY_IMAGE=${REDEPLOY_IMAGE}" | tee -a / codefresh/volume/env_vars_to_export 
    echo "REBUILD_GRADLE_JAR=${REBUILD_GRADLE_JAR}" | tee -a /codefresh/volume/env_vars_to_export 
    echo "IMAGE_TAG_WAS_DERIVED=${IMAGE_TAG_WAS_DERIVED}" 
    echo "USE_PROMOTE_IMAGE_TAG=${USE_PROMOTE_IMAGE_TAG}" 
    echo "PROMOTE_IMAGE_TAG=${PROMOTE_IMAGE_TAG}" 
    echo "APP_VARS_NS_MOD=${APP_VARS_NS_MOD[@]}" 
    echo "NS_LIST=${NS_LIST[@]}" | tee -a /codefresh/volume/env_vars_to_export 
    echo "VERSION=${VERSION}" | tee -a /codefresh/volume/env_vars_to_export 
    echo "MANIFEST_VERSION=${MANIFEST_VERSION}" | tee -a / codefresh/volume/env_vars_to_export 
    echo "GIT_SHA=${GIT_SHA}"
    echo "CHANGE_SHA=${CHANGE_SHA}" | tee -a / codefresh/volume/env_vars_to_export 
    echo -e "${GREEN}SCRIPT END.${NOCOL}"
}

create_ns_list() {
    DEBUG="FALSE"
    echo -e "${BLUE}STEP: Building NS_LIST from overlay changes${NOCOL}" 
    local -A namespace_array app_vars_s_mod_array 
    unset APP_VARS_NS_MOD 
    unset NS_LIST
    #local -n app_variables_ns_local=$1
    #local -n OVERLAY_FOLDERS_LIST_local-$2
    [[ "${DEBUG}" == "TRUE" ]] && echo -e "DEBUG: Incoming data to 'create_ns_list' function - app_variables_ns:\n${app_variables_ns[@]}"
    [[ "${DEBUG}"== "TRUE" ]] && echo -e "DEBUG: Function data to 'create_ns_list' function - OVERLAY_FOLDERS_LIST:\n${OVERLAY_FOLDERS_LIST}"

    for ns _data in "${app_variables_ns [@]}"; do
        # create an array from the data like OA1 NS=sit-cat-auth/CAT-SEC-GE-N-APPDEPLOY/2021-]]-1717:12toendup
        # namespace_array [sit-cat-auth]="sit-cat-auth/CAT-SEC-GKE-NP-APPDEPLOY/2021-]]-17_17:12"
        # we need to check against the existence of that key coming from the changes kustomize overlay.
        #key=${ns_data%%=*} 
        value=${ns_data#*=} 
        ns_key=${value%%/*} 
        app_vars_ns_mod_array[$ns_key]=$ns_data 
        namespace_array[$ns_key]=$value
        [[ "${DEBUG}" == "TRUE" ]] && echo -e "DEBUG: value=${value}, ns_key=${ns_key}, app_vars_ns_mod_array=${app_vars_ns_mod_array[@]}, namespace_array=${namespace_array[@]}"
    done

    for namespace in ${OVERLAY_FOLDERS_LIST}; do
        [[ "${DEBUG}" == "TRUE" ]] && echo -e "DEBUG: Testing against namespace = ${namespace}"
        # Require here the parameter expansion syntax ="$(VAR: - 'value'}" because unless the value exists we get an unbound variable error.
        [[ "${DEBUG}" == "TRUE" && -n "${namespace_array [${namespace}]:-}" ]] && echo "DEBUG: Adding to NS_LIST arrary => ${namespace_array[${namespace}]

        :-}"
        if [[ -n "${namespace_array[${namespace}]:-}" ]]; then
            APP_VARS_NS_MOD+=("${app_vars_ns_mod_array [${namespace}]}")
            NS_LIST+=("${namespace_array [${namespace}]}")
        fi done

        if [[ -n ${NS_LIST[@]} ]]; then
            [[ "${DEBUG}" == "TRUE" ]] && echo -e "DEBUG: NS_LIST array size = ${#NS_LIST[@]}"
            echo -e "${GREEN}Determined list of target namespaces:\n${NS_LIST[@]}${NOCOL}"
        else
            echo -e "${RED}WARN: No matching namespace selectors for this branch found in app-variables${NOCOL}" 
            echo -e "${RED}WARN: NS_LIST reset to NULL.${NOCOL}"
            NS_LIST="NULL"
            APP_VARS_NS_MOD="NULL" 
        fi
}

derive_version () {
    echo "Using derive_version to determine image tag"
    IMAGE_TAG_WAS_DERIVED="TRUE"
    REBUILT_VIA_VERSION_CHANGE="FALSE" # The REBUILT_VIA_ VERSION_ CHANGE variable is used to signal the
    # Need to test if VERSION has changed in the set of commits too.
    # First, has there been a change to app or base between this commit and the last merge commit on the graph?
    # Get the most recent merge commit
    # Get the commit, if exists containing app changes
    APP_COMMIT=$(git rev-list --first-parent --abbrev-commit --abbrev=7 -1 HEAD -- app/)
    
    if [[ -z ${APP_COMMIT} ]]; then 
        echo "App commit is empty"
        APP TS=-1 
    else
        echo "The most recent commit to change app/ is ${APP_COMMIT}"
        APP_TS=$(git show -s --format=%cd --date=unix ${APP_COMMIT})
        echo "App commit UNIX timestamp ${APP_TS} == $(date -d @${APP_TS})" 
    fi

    VALID_VER_COMMIT_FOUND="FALSE"
    SINGLE_VERSION_CHANGE_ITERATION="FALSE"
    VER_SEARCH_SHA="${GIT _SHA}"
    VER_COMMIT=$(git rev-list --first-parent--abbrev-commit--abbrev=7-1 ${VER_SEARCH_SHA} --VERSION)

    if [[ -z ${VER_COMMIT} ]]; then 
        echo "App commit is empty"
        VER_TS=-1 
    else
        echo "The most recent commit to change VERSION is ${VER_COMMIT}"
        VER_TS=$(git show -s --format=%cd --date-unix ${VER_COMMIT})
        echo "VERSION commit UNIX timestamp ${VER_TS} == $(date -d @${VER_TS})" 
    fi

    if [[ ${APP_TS} -ne -1 && ${VER_TS} -ne -1 ]]; then
        echo "Valid app folder and VERSION file changes identified for comparison." 
        if [[ ${APP_TS} -gt ${VER_TS} ]]; then 
            echo "===========) Check A1"
            echo "The app timestamp ${APP_TS} more recent than the VERSION change timestamp ${VER_TS}" 
            echo "Using the most recent app change commit: ${APP_COMMIT} made at: $(date -d @${APP_TS})" 
            echo "No further checks are needed."
            COMMIT_TRIGGER= "APP"
            CHANGE_TS=${APP_TS}
            CHANGE_SHA=${APP_COMMIT}
            VALID_VER_COMMIT_FOUND="TRUE"
        elif [[ ${APP_TS} -eq ${VER_TS} ]]; then
            echo "============> Check A2"
            echo "The app timestamp ${APP_TS} is equal to the VERSION change timestamp ${VER_TS}" 
            echo "We will use the most recent app change commit: ${APP_COMMIT}."
            echo "However further checks are needed to observe the changes to the VERSION file."
            COMMIT_TRIGGER="APP"
            CHANGE_TS=${APP_TS}
            CHANGE_SHA=${APP_COMMIT}
            SINGLE_VERSION_CHANGE_ITERATION="TRUE" 
        elif [[ ${VER_TS} -gt ${APP_TS} ]]; then 
            echo "============) Check A3"
            echo "The VERSION commit ${VER_COMMIT} is more recent that app commit ${APP_COMMIT}" 
            echo "Thus checking content of the most recent VERSION file changes starting at commit: ${VER_COMMIT}"
        fi
    elif [[ ${APP_TS} -eq -1 && ${VER_TS} -eq -1 ]]; then 
        if [ [${PROMOTE_IMAGE_TAG} != ""]]; then 
            echo "============> Check A4"
            echo "Neither a commit with an app change nor a VERSION change can be located, but PROMOTE_IMAGE_TAG is valid" 
            echo "Condition unreachable for correctly configured repo" 
            exit 1
        elif [[${PROMOTE_IMAGE_TAG} != ""]]; then 
            echo "============> Check AS"
            echo "Neither a commit with an app change nor a VERSION change can be located and PROMOTE_IMAGE_TAG is not valid" 
            echo "No version can be derived" 
            echo "Condition unreachable for correctly configured repo" 
            exit 1
        fi
    elif [[ ${APP_TS} -eq -1 && ${VER_TS} -ne -1 ]]; then
        echo "========> Check A6"
        echo "Only an version change timestamp exists ${VER_TS}"
        echo "Using the most recent app change commit: ${VER_COMMIT} made at: $(date -d. @${VER_TS})"
        echo "Condition unreachable for correctly configured repo" 
        exit 1
    elif [[ ${APP_TS} -ne -1 && ${VER_TS} -eq -1 ]]; then
        echo "=============>Check A7"
        echo "Only an app change timestamp exists ${APP_TS}"
        echo "Using the most recent app change commit: ${APP_COMMIT} made at: $(date -d @${APP_TS})." 
        echo "Condition unreachable for correctly configured repo" 
        exit 1
        COMMIT_TRIGGER="APP"
        CHANGE_TS=${APP_TS}
        CHANGE_SHA=${APP_COMMIT}
        VALID_VER_COMMIT_FOUND="TRUE" # Set to true to prevent unncessary scanning for VERSION changes 
    fi

    while [[ "${VALID_VER_COMMIT_FOUND}" == "FALSE" && ${VER_TS} -ge ${APP_TS} ]]; do 
        
        echo -e "${GREEN}ACTION: Checking commit ${VER_COMMIT} for VERSION file change detail.${NOCOL}"
        
        PROMOTE_IMAGE_TAG_CHANGE=$(git log ${VER_COMMIT} -n1 -p -- VERSION | grep "+PROMOTE_IMAGE_TAG" || echo "NULL")

        if [[ "${PROMOTE_IMAGE_TAG_CHANGE}" == "+PROMOTE_IMAGE_TAG=" ]]; then
            echo "===========> Check B1"
            echo "PROMOTE_IMAGE_TAG is the empty string, VERSION commit not useable"
            #VER_SEARCH_SHA-"$ (VER_COMMIT}~1"
            PROMOTE_IMAGE_TAG="NULL"
        elif [[ "${PROMOTE_IMAGE_TAG_CHANGE}" =~ \+PROMOTE_IMAGE_TAG=.+ ]]; then
            echo "============> Check B2"
            echo "PROMOTE_IMAGE_TAG changed in VERSION commit = ${VER_COMMIT}"
            USE_PROMOTE_IMAGE_TAG="POSSIBLE"
            VALID_VER_COMMIT_FOUND="TRUE"
            echo "VERSION commit UNIX timestamp ${VER_TS}"
        fi
        
        if [[ $(git log ${VER_COMMIT} -n1 -p -- VERSION | grep "+BASE_IMAGE_IN") ]]; then
            echo "============> Check B3"
            echo "BASE_IMAGE_IN changed in VERSION commit = ${VER_COMMIT}"
            VER_TS=$(git show -s --format=%cd --date=unix ${VER_COMMIT})
            echo "A rebuild would have been triggered from ${VER_COMMIT} at ${VER_TS}"
            REBUILT_VIA_VERSION_CHANGE=TRUE
            VALID_VER_COMMIT_FOUND="TRUE"
        fi
        if [[ $(git log ${VER_COMMIT} -n1 -p -- VERSION | grep "+BASE_IMAGE_TAG_IN") ]]; then 
            echo "============> Check B4"
            echo "BASE_IMAGE _TAG_IN changed in VERSION commit = ${VER_COMMIT}"
            VER_TS=$(git show -s --format=%cd --date=unix ${VER_COMMIT})
            echo "A rebuild would have been triggered from ${VER_COMMIT} at ${VER_TS}"
            REBUILT_VIA_VERSION_CHANGE=TRUE
            VALID_VER_COMMIT_FOUND="TRUE"
        fi
        if [[ $(git log ${VER_COMMIT} -n1 -p -- VERSION | grep "+BASE_IMAGE_TAG_OUT") ]]; then
            echo "============> Check BS"
            echo "BASE_IMAGE_TAG_OUT changed in VERSION commit = ${VER_COMMIT}"
            echo "On it's own this would make VERSION commat ${VER COMMIT} not useable for version details"
            #VER_SEARCH_SHA- "$ (VER_COMMIT}~1"
        fi
        # If we are only here looking at the addition VERSION details contained in the same commit as an app/ commit, check once and break
        if [[ ${SINGLE_VERSION_CHANGE_ITERATION} == "TRUE" ]]; then
            echo "============> Check B6"
            VALID_VER_COMMIT_FOUND="TRUE" break
        fi

        # Get the next commit, if exists containing VERSION changes
        if [[ "${VALID_VER_COMMIT_FOUND}" == "FALSE" ]]; then
            echo "============> Check B7 - No valid VERSION file change found; next iteration"
            # Create a new VER_SEARCH_SHA variable pointing to the commit prior to where we are currently looking so we don't search the current commit again.
            VER_SEARCH_SHA="${VER_COMMIT}~1"
            VER_COMMIT=$(git rev-list --first-parent --abbrev-commit --abbrev=7 -1 ${VER_SEARCH_SHA} -- VERSION)
            VER_TS=$(git show -s --format=%ed --date=unix ${VER_COMMIT})
            echo "Next VERSION change commit to check = ${VER_COMMIT}"
        fi 
        echo "=============> ${VER_TS}, ${APP_TS}"
    done

    # Compare and select most recent commit as new VERSION for use
    # If both commit timestamps are non-null then compare them and use the younger timestamp.
    # The younger timestamp is a larger number.
    #if [[ StVER_TS) - gt $(APP_TS) && "${VALID_VER_COMMIT_FOUND}."
    if [[ ${VER_TS} -ge ${APP_TS} && "${VALID_VER_COMMIT_FOUND}" == "TRUE" ]]; then
        
        CHANGE_TS=${VER_TS}
        CHANGE_SHA=${VER_COMMIT}
        
        if [[ ${VER_TS} -eq ${APP_TS} ]]; then 
            if [[ "${USE_PROMOTE_IMAGE_TAG}" == "POSSIBLE" && "${REBUILT_VIA_VERSION_CHANGE}" == "FALSE" ]]; then
                echo "============> Check C1"
                echo "There was PROMOTE_IMAGE_TAG change in the VERSION file and app folder change in the same commit." 
                echo "When this occurrs, the change SHA takes precedence over the PROMOTE_IMAGE_TAG." 
                echo "This happened for commit: ${VER_COMMIT}."
                echo "VERSION commit UNIX timestamp ${VER_TS} == $(date -d @${VER_TS})."
                COMMIT_TRIGGER="APP"
                USE_PROMOTE_IMAGE_TAG="FALSE"
            elif [[ "${REBUILT_VIA_VERSION_CHANGE}" == "TRUE" ]]; then 
                echo "============) Check C2"
                echo "There was BASE IN change in the VERSION file in the same commit as an app/ change." 
                echo "When this occurs, it's an automatic rebuild for all outcomes." 
                echo "This happened for commit: ${VER_COMMIT}."
                echo "VERSION commit UNIX timestamp ${VER_TS} == $(date -d @${VER_TS})."
                COMMIT_TRIGGER="REBUILT_VIA_VERSION_CHANGE"
                USE_PROMOTE_IMAGE_TAG="FALSE"
            fi
        elif [[ ${VER_TS} -gt ${APP_TS} ]]; then
            if [[ "${USE_PROMOTE_IMAGE_TAG}" == "POSSIBLE" && "${REBUILT_VIA_VERSION_CHANGE}" == "FALSE" ]]; then
                echo "============> Check C3"
                echo "There was PROMOTE_IMAGE_TAG change in the VERSION file." 
                echo "This happened for commit: ${VER_COMMIT}."
                echo "VERSION commit UNIX timestamp ${VER_TS} == $(date -d @${VER_S})."
                COMMIT_TRIGGER="VERSION_PROMOTE"
                USE_PROMOTE_IMAGE_TAG="TRUE"
            elif [[ "${REBUILT_VIA_VERSION_CHANGE}" == "TRUE" ]]; then
                echo "=========> Check C4"
                echo "There was BASE_*_IN change in the VERSION file." 
                echo "When this occurs, it's an automatic rebuild for all outcomes." 
                echo "This happened in commit: ${VER_COMMIT}."
                echo "VERSION commit UNIX timestamp ${VER_TS} == $(date -d @${VER_TS})."
                COMMIT_TRIGGER="REBUILT_VIA_VERSION_CHANGE"
                USE_PROMOTE_IMAGE_TAG="FALSE" 
            fi 
            else
                # This shouldn't ever be reached
                echo "No valid versioning details found" 
                exit 1
            fi
        elif [[ ${VER_TS} -lt ${APP_TS} && "${VALID_VER_COMMIT_FOUND}" == "FALSE" ]]; then
            echo "============> Check C6"
            echo "No valid VERSION change found in commits more recent than the latest app/ change. Using app/ commit for versioning"
            COMMIT_TRIGGER="APP"
            CHANGE_TS=${APP_TS}
            CHANGE_SHA=${APP_COMMIT}
        else
            echo"============>Check c6"
            echo "VERSION checks bypassed" 
        fi
    
        if [[ "${COMMIT_TRIGGER}" == "APP" ]]; then
            IMAGE_TAG_WAS_DERIVED_FROM+=("# Used commit SHA of latest app change: ${CHANGE_SHA}")
            # Locate the VERSION file from the commit used to build the image.
            git checkout ${CHANGE_SHA} -- VERSION 
            BASE_IMAGE_TAG_OUT_CURRENT=${BASE_IMAGE_TAG_OUT}
            export "$(grep BASE_IMAGE_TAG_OUT VERSION)"
            VERSION="${BASE_IMAGE_TAG_OUT}.${CHANGE_SHA}"
            echo -e "${GREEN}ACTION: USing BASE_IMAGE_TAG_OUT from APP_SHA=${CHANGE_SHA}.${NOCOL}." 
            if [[ "${BASE_IMAGE_TAG_OUT_CURRENT}" != "${BASE_IMAGE_TAG_OUT}" ]]; then
                echo "The values of BASE_IMAGE_TAG_OUT differed between HEAD and ${CHANGE_SHA} as: ${BASE_IMAGE_TAG_OUT_CURRENT} != ${BASE_IMAGE_TAG_OUT}" 
            fi
            USE_PROMOTE_IMAGE_TAG= "FALSE" 
            echo "OPT 1. VERSION=${VERSION}"
        elif [[ "${COMMIT_TRIGGER}" == "REBUILT_VIA_VERSION_CHANGE" ]]; then
            IMAGE_TAG_WAS_DERIVED_FROM+=("# Used commit SHA of relevant VERSION file change: ${CHANGE _SHA}")
            # Locate the VERSION file from the commit used to build the image.
            git checkout ${CHANGE_SHA} -- VERSION
            BASE_IMAGE_TAG_OUT_CURRENT=${BASE_IMAGE_TAG_OUT}
            export "$(grep BASE_IMAGE_TAG_OUT VERSION)" 
            VERSION="${BASE_IMAGE_TAG_OUT}=${CHANGE_SHA}"
            echo -e "${GREEN}ACTION: Using BASE_IMAGE_TAG_ OUT from APP_SHA=${CHANGE_SHA}.${NOCOL}" 
            if [["${BASE_IMAGE_TAG_OUT_CURRENT}" != "${BASE_IMAGE_TAG_OUT}" ]]; then
                echo "The values of BASE_IMAGE_TAG_OUT differed between HEAD and ${CHANGE_SHA} as: ${BASE_IMAGE_TAG_OUT_CURRENT} != ${BASE_IMAGE_TAG_OUT}" 
            fi
                echo "OPT 2. VERSION=${VERSION}"
        
        elif [[ "${COMMIT_TRIGGER}" == "VERSION_PROMOTE" ]]; then
            IMAGE_TAG_WAS_DERIVED_FROM+=("# Used commit SHA of relevant VERSION file change: ${CHANGE_SHA}")
            USE_PROMOTE_IMAGE_TAG="TRUE"
            VERSION=${PROMOTE_IMAGE_TAG} 
            echo "OPT 3. VERSION=${VERSION}"
        elif [[ "${COMMIT_TRIGGER}" == "FATAL" ]]; then
            echo "OPT 4 FATAL" 
            exit 1
        fi
}

echo -e "${BLUE}STEP: Git repo status${NOCOL}." 
echo -en "${GREEN}"
echo GIT_BRANCH=$(git branch --show-current)
echo GIT_SHA=${GIT_SHA} 
echo COMMIT_COUNT=${COMMIT_COUNT} 
echo PARENT1_SHA=${PARENT1_SHA} 
echo -en "${NOCOL}"

echo -e "${BLUE}TEST: Test commit status${NOCOL}" 
if (( ${COMMIT_COUNT} >= 3 )); then

    MERGE="TRUE"
    echo -e "${YELLOW}RESULT: On a merge commit at ${GIT_BRANCH}${NOCOL}"
else
    MERGE="FALSE"
    echo -e "${YELLOW}RESULT: On a branch commit at ${GIT_BRANCH}${NOCOL}" 
    if [[ "${GIT_BRANCH}" =~ ^develop$ || "${GIT_BRANCH}" =~ ^master$ ]]; then
        echo -e "${RED}WARN: Only merges into develop and master accepted, no direct commits.${NOCOL}" 
    fi 
fi

echo -e "${BLUE}PROCESS: Generating outcome${NOCOL}"

##
##
## App-variables changes
# If a namespace selector in the app_vars file is updated with a new timestamp, the intent is interpreted as:
# redeploy the current develop HEAD image into the namespace. This will create a new manifest incorporating any
# changes in the commit and set the image to the SIT SHA.
# For this to be true there must not have been a rebuild directive from an app or kustomise base change.
# QA1_NS=sit-cat-auth/CAT-SEC-GKE-NP-APPDEPLOY/DATETIME-›NEWDATETIME
##
##
## VERSION file change details
##

echo -e "${BLUE}==> STAGE 1: Testing VERSION file changes: ${NOCOL}"
VERSION_FILE_MOD-$(git diff ${PARENT1_SHA} ${GIT_SHA} --name-only -- ./VERSION)

if [[ -n "${VERSION_FILE_MOD}" ]]; then
    echo -e "${YELLOW}RESULT: VERSION file has changed - ${VERSION_FILE_MOD}.${NOCOL}"
    VERSION_CHANGED="TRUE"

    BASE_IMAGE_IN_CHANGED=$(git diff HEAD~1 VERSION | grep "+BASE_IMAGE_IN" || echo "")
    BASE_IMAGE_TAG_IN_CHANGED-$(git diff HEAD~1 VERSION | grep "+BASE_IMAGE_TAG_IN" || echo "")
    BASE_IMAGE_TAG_OUT_CHANGED=$(git diff HEAD~1 VERSION | grep "+BASE_IMAGE_TAG_OUT" || echo "")
    PROMOTE_IMAGE_TAG_CHANGED=$(git diff HEAD~1 VERSION | grep "+PROMOTE_IMAGE_TAG" || echo "")
    if [[ -n ${BASE_IMAGE_IN_CHANGED} || -n ${BASE_IMAGE_TAG_IN_CHANGED} ]]; then
        echo -e "${YELLOW}RESULT: Base image in spec in VERSION file on ${GIT_BRANCH} has changed.${NOCOL}"
        
        if [[ "${GIT_BRANCH}" =~ ^feature/.* || "${GIT_BRANCH}" =~ ^dev/.* || "${GIT_BRANCH}" =~ ^bugfix/.* || "${GIT_BRANCH}" =~ ^hotfix/.* || "${GIT_BRANCH}" =~ ^release/.* ]]; then
            echo -e "${YELLOW}RESULT: On branch ${GIT_BRANCH}, this can trigger a rebuild if a namespace target is selected.${NOCOL}"
            BASE_IN_VER_CHANGED="TRUE"

        elif [["${GIT_BRANCH}" =~ ^release/.* ]]; then
            echo -e "${YELLOW}RESULT: Base image in spec in VERSION file on ${GIT_BRANCH} has changed.${NOCOL}" 
            echo -e "${YELLOW}RESULT: This does not trigger a rebuild in ${GIT_BRANCH}.${NOCOL}"
        
        elif [[ "${GIT_BRANCH}" =~ ^master/.* ]]; then
            # To do - this regex used for local testing is incorrect.
            # This script is never run by for master branch
            # The condition doesn't make sense anyway as merges to master will see this change.
            echo -e "${RED}RESULT: Tested true that the VERSION file has changed but this action on ${GIT_BRANCH} is invalid. Exiting${NOCOL}" 
            exit 1
        fi

    elif [[ -n ${BASE_IMAGE_TAG_OUT_CHANGED} ]]; then 
        echo -e "${YELLOW}RESULT: BASE_IMAGE_TAG_OUT changed.${NOCOL}" 
        if [[ "${GIT_BRANCH}" =~ ^drh/.* || "${GIT_BRANCH}" =~ ^develop$ ]]; then 
            echo -e "${GREEN}RESULT: BASE_IMAGE_TAG_OUT changed on ${GIT_BRANCH} branch, ignoring.${NOCOL}" 
        elif [[ "${GIT_BRANCH}" =~ ^release/.* ]]; then
            echo -e "${RED}WARN: BASE_IMAGE_TAG_OUT changed outside of a release branch. Merge into release to trigger prod manifest build.${NOCOL}"
            VERSION="NULL" 
            echo_decisions
            exit o
        elif [[ "${GIT_BRANCH}" =~ ^release/.* ]]; then
            echo -e "${GREEN}RESULT: BASE_IMAGE_TAG_OUT on release branch, setting VERSION.${NOCOL}" 
            VERSION="${BASE_IMAGE _TAG_OUT}" 
            echo_decisions
            exit 0 
        fi
        
        elif [[ -n ${PROMOTE_IMAGE_TAG_CHANGED} ]]; then
            echo -e "${YELLOW}NOTIFICATION: PROMOTE_IMAGE_TAG changed - set REDEPLOY to TRUE as most likley outcome.${NOCOL}"
            REDEPLOY_IMAGE="TRUE"
            USE_PROMOTE_IMAGE_TAG="TRUE" 
        fi 
        echo_status
    else
        echo -e "${YELLOW}RESULT I VERSION file unchanged.${NOCOL}"
    fi
##    
## NS selection

# Reset the NS_LIST variables.
# If we don't unset the variables, then when we use the += operator, the first array value is NULL.

if [[ "${NS_LIST[0]}" == "NULL" ]]; then
    echo "Unset APP_VARS_NS _MOD & NS_LIST arrays" 
    unset APP_VARS_NS_MOD 
    unset NS_LIST
fi

echo -e "${BLUE}==> STAGE 2: Testing for namespace selector changes in app-variables:${NOCOL}"
APP_VARS_FILE_MOD=$(git diff ${PARENTI_SHA} ${GIT_SHA} --name-only -- ./app-variables)

if [[ "${GIT_BRANCH}" =~ ^drh/.* ]]; then
    echo -e "${YELLOW}NOTE: we are on the drh branch; ignore bundled namespace selection.${NOCOL}"
    APP_VARS_FILE_MOD="" 
fi

if [[ -n "${APP_VARS_FILE_MOD}" ]]; then 
    echo -e "${YELLOW}RESULT: The app-variables file has modifications${NOCOL}."
    # Now test for actual namespace selector changes
    # Create an array of the modified namespace from app-variable change list.
    # We need an array to remove the testing and prod namespaces later on in the easiest way
    # ${APP_VARS_NS_MOD[0]} takes the format of = "QA1_NS=cat-prv-unauth-qa1-prvauthcat/CPAAS-GLOBALTEST-DEV-CLUSTER3/2021-12-02_22:15" from the app-variables file
    APP_VARS_CHANGES=($(git diff ${PARENT1_SHA} ${GIT_SHA} - U0 -- ./app-variables | sed -n 's|^+\([^#].*[[:digit:]]\+_NS=.*/\)\([[:digit:]]\{4\}-[[:digit:]]\{2\}-[[:digit:]]\{2\}_[[:digit:]]\{2\}:[[:digit:]]\{2\}\)\{1,\}\(:[[:digit:]]\{2\}\)\?|\1|p'))

    if [[ -n "${APP_VARS_CHANGES[*]}" ]]; then
        echo -e "${YELLOW}RESULT: The app-variables file contains namespace selector changes:\n${NOCOL}${APP_VARS_CHANGES[@]}"
        APP_VARS_NS_CHANGED="TRUE"
        echo -e "${BLUE}RESULT: Changes to app-variables file exist.${NOCOL}." 
        echo -e "${BLUE}STEP: Processing app-variables file changes.${NOCOL}"
        # echo -@ "${GREEN}NOTE: Changes to the app-variables file merged to develop${NOCOL}"
        echo -e "${BLUE}TEST: Testing various branch conditions.${NOCOL}"
        
        #ToDo Fix indent
    if [[ "${GIT_BRANCH}" =~ ^feature/.* || "${GIT_BRANCH}" =~ ^bugfix/.* || "${GIT_BRANCH}" =~ ^dev/.* ]]; then 
        echo -e "${YELLOW}NOTE: A namespace change was identified on a branch: ${GIT_BRANCH}${NOCOL}"
        APP_VARS_CHANGES=(${APP_VARS_CHANGES[*]//QA*=*}) 
        APP_VARS_CHANGES-(S{APP_VARS_CHANGES[*]//DRH*=*}) 
        APP_VARS_CHANGES=(${APP_VARS_CHANGES[*]//PROD*=*})

    elif [[ "${GIT_BRANCH}" =~ ^release/.* || "${GIT_BRANCH}" =~ ^hotfix/.* ]]; then
        echo -e "${YELLOW}NOTE: A namespace change was identified on a branch: ${GIT_BRANCH}${NOCOL}"
        APP_VARS_CHANGES=(${APP_VARS_CHANGES[*]//DEV* =*})
        APP_VARS_CHANGES-(${APP_VARS_CHANGES[*]//DRH*=*})
        APP_VARS_CHANGES-(${APP_VARS_CHANGES[*]//PROD*=*})
    elif [[ "${GIT_BRANCH}" =~ ^develop$ ]]; then 
        echo -e "${YELLOW}NOTE: A namespace change was identified on a branch: ${GIT_BRANCH}${NOCOL}"
        APP_VARS_CHANGES=(${APP_VARS_CHANGES[*]//DEV*=*})
        APP_VARS_CHANGES=(${APP_VARS_CHANGES[*]//DRH*=*})
        APP_VARS_CHANGES (${APP_VARS_CHANGES[*]//PROD*=*})
    
        if [[ "${PLATFORM}" =~ ^ose.* ]]; then
            APP_VARS_CHANGES=(${APP_VARS_CHANGES[*]//QA*=*})
        elif [["${PLATFORM}" == "gke-mks" ]]; then
            APP_VARS_CHANGES=(${APP_VARS_CHANGES[*]//QA*=*})
        elif [["${PLATFORM}" == "gke-sec" ]]; then
            APP_VARS_CHANGES=(${APP_VARS_CHANGES[*]//QA*=*})
        fi
    fi

    for INCOMING_NS in ${APP_VARS_CHANGES[*]}; do
        if [[ ! "${APP_VARS_NS_MOD[*]}" =~ " ${INCOMING_NS}" ]]; then
            APP_VARS_NS_MOD+=(${INCOMING_NS})
            # strip to the left of the first = sign
            INCOMING_NS=${INCOMING_NS[@]#*=}
            # strip to the right of the second / character
            INCOMING_NS=${INCOMING_NS[@]%/*}
            NS_LIST+=(${INCOMING_NS})
        else
            echo "Found ${INCOMING_NS} but already present in ${APP_VARS_NS_MOD[*]} through overlay selection"
        fi 
    done

    # Remove the ns labels and timestamps. I.e. remove the text in front of the = and after the last /
    # QA1_NS=sit-cat-auth/CAT-SEC-GKE-NP-APPDEPLOY/DATETIME=>sit-cat-auth/CAT-SEC-GKE-NP-APPDEPLOY

    APP_VARS_INS_MOD=(${APP_VARS_NS_MOD[@]:-NULL})
    NS_LIST=(${NS_LIST[@]:-NULL})

    if [[ ! "${NS_LIST[0]}" == "NULL" ]]; then
        REDEPLOY_IMAGE- "TRUE" 
    fi
    
    echo_status 
    else
        echo -e "${YELLOW}RESULT: The app-variables file has changed but there are no namespace selector changes found.${NOCOL}" 
    fi 
else
    echo -e "${YELLOW}RESULT: App-variables file unchanged${NOCOL}" 
fi

APP_VARS_NS_MOD=(${APP_VARS_NS_MOD[@]:-NULL})
NS_LIST=(${NS_LIST[@]:-NULL})

echo -e "${GREEN}ACTION: Set NS_LIST to: ${NS_LIST[@]}.${NOCOL}"

##
##
## Default NS selection

echo -e "${BLUE}==> STAGE 3: Apply any relevant default namespace selectors if none chosen by the operator:${NOCOL}"

if [[ "${NS_LIST[0]}" == "NULL" ]]; then
    DEFAULT_NS_USED="TRUE"
    if [[ "${GIT_BRANCH}" =~ ^feature/.* || "${GIT_BRANCH}" =~ ^bugfix/.* ]]; then 
        echo -e "${BLUE}Set default NS for feature branches.${NOCOL}"

        if [[ "${PLATFORM}" =~ ^ose.* ]]; then 
            echo -e "${BLUE}PLATFORM=ose${NOCOL}"
            APP_VARS_NS_MOD[0]=$(sed -n 's|^\(DEV1_NS=.*/\)\([[:digit:]]\{4\}-[[:digit:]]\{2\}-[[:digit:]]\{2\}_[[:digit:]]\{2\}:[[:digit:]]\{2\}:[[:digit:]]\{2\}\)*|\1|p' ./app-variables)

            NS_LIST[0]=$(sed -n 's|^DEV1_NS=\(.*/\)\([[:digit:]]\{4\}-[[:digit:]]\{2\}-[[:digit:]]\{2\}_[[:digit:]]\{2\}:[[:digit:]]\{2\}\)*|\1|p' ./ app-variables)
        elif [[ "${PLATFORM}" =~ ^gke.* ]]; then 
            echo -e "${BLUE}PLATFORM=gke${NOCOL}"
            APP_VARS_NS_MOD[0]=$(sed -n 's|^\(DEV1_NS=.*/\)\([[:digit:]]\{4\}-[[:digit:]]\{2\}-[[:digit:]]\{2\}_[[:digit:]]\{2\}:[[:digit:]]\{2\}:[[:digit:]]\{2\}\)*|\1|p' ./app-variables)

            NS_LIST[0]=$(sed -n 's|^DEV1_NS=\(.*/\)\([[:digit:]]\{4\}-[[:digit:]]\{2\}-[[:digit:]]\{2\}_[[:digit:]]\{2\}:[[:digit:]]\{2\}\)*|\1|p' ./ app-variables)
        else
            echo "DEBUG: PLATFORM=${PLATFORM} bottomed out"
        fi
    
    elif [[ "${GIT_BRANCH}" =~ ^develop$ ]]; then 
        if [[ "${PLATFORM}" =~ ^ose.* ]]; then
            :
            # OSE has opted for no default CD namespace.
            # APP_VARS_NS_MOD-($(sed -n '|^\(QA1_NS=. */\) \([[: digit: JJ\4\J- [[:digit: 1]\f2\}-[[:digit: 1J\2\)_[C:digit: JJ\(2\): (L:digit: JJ\(2\7\)*|\1|p*(app-variables))
            # NS_LIST= ($(sed -n 's |^QA1_NS=\(. */\) \([[: digit: JJ\{4\J- [[:digit: ]]\(2\) - [C:digit: jJ\2\)_[[:digit: ]J\{2\): [[: digit: JJ\2\)\)*/\1|p' ./app-variables))
        elif [[ "${PLATFORM}" =~ ^gke-sec ]]; then
            :
            # To bring GE into line with OSE the deploy to QA1 on merge to develop was removed too.
            # APP_VARS_NS_MOD[®]=$ (sed -n 's |^\ (QA1_NS-. */\) \([[:digit: ]J\4\3 - [[:digit: 1J\2\J- [:digit: 1]\(2\)_([:digit: ]J\2\): [[:digit: 1]\(2\7\)*|\1| p' ./app-variables)
            # NS_LIST[e]=S (sed -n 's|^QA1_NS=\(. */\)\([E: digit: ]]\4\)- [L:digit: ]]\2\)-[L:digit: ]]\(2\)_[L:digit: ]]\(2\): [L:digit: ]]\(2\7\)*|]]/p*app-variables)
        fi
    elif [[ "${GIT_BRANCH}" =~ ^release/.* ]]; then 
        if [[ "${PLATFORM}" =~ ^ose.* ]]; then
            :
        elif [[ "${PLATFORM}" =~ ^gke.* ]]; then
            :
        fi
    elif [[ "${GIT_BRANCH}" =~ ^hotfix/.* ]]; then 
        if [[ "${PLATFORM}" =~ ^ose.* ]]; then 
            :
        elif [[ "${PLATFORM}" =~ ^gke.* ]]; then
            :
        fi

    elif [["${GIT_BRANCH}" =~ ^drh/.* ]]; then
        echo -e "${BLUE}RESULT: Set NS for DRH branch.${NOCOL}"
        DEFAULT_NS_USED="FALSE" #DRH doesn't use the concept of DEFAULT_NS_USED
        APP_VARS_NS_MOD[0]=$(sed -n 's|^\(DRH1_NS=.*/\)\([[:digit:]]\{4\}-[[:digit:]]\{2\}-[[:digit:]]\{2\}_[[:digit:]]\{2\}:[[:digit:]]\{2\}:[[:digit:]]\{2\}\)*|\1|p' ./app-variables)
        NS_LIST[0]=$(sed -n 's|^DRH1_NS=\(.*/\)\([[:digit:]]\{4\}-[[:digit:]]\{2\}-[[:digit:]]\{2\}_[[:digit:]]\{2\}:[[:digit:]]\{2\}\)*|\1|p' ./ app-variables)
        if [[ "${PLATFORM}" =~ ^ose.* ]]; then
            :
        elif [[ "${PLATFORM}" =~ ^gke.* ]l; then
            :
        fi
    elif [[ "${GIT_BRANCH}" =~ ^master$ ]]; then 
        if [[ "${PLATFORM}" =~ ^ose.* ]]; then
            :
        elif [[ "${PLATFORM}" =~ ^gke.* ]]; then
            :
        fi
    fi
    
    if [[ -z "${NS_LIST[0]}" ]]; then
        REDEPLOY_IMAGE="FALSE"
    elif [[ ! "${NS_LIST[0]}" == "NULL" ]]; then
        REDEPLOY_IMAGE="TRUE" 
    fi 
    echo_status
    if [[ -z "${NS_LIST[@]}" ]]; then
        echo -e "${RED}INFO: No default namespace attributable to this branch in app-variables, build only.${NOCOL}" 
    fi
else
    echo -e "${YELLOW}RESULT: No default namespaces selections applied.${NOCOL}" 
fi

NS_LIST=(${NS_LIST[@]:-NULL})
echo -e "$ {GREEN}ACTION: Set NS_LIST to: ${NS_LIST[@]}.${NOCOL}"
##
##
## Application folder change details
# Test for app file changes

echo -e "${BLUE}==> STAGE 4: Testing for application folder changes:${NOCOL}"
APPS_FILES_MOD=$(git diff ${PARENTI_SHA} ${GIT_SHA} --name-only -- ./app/)
if [[ -n "${APPS_FILES_MOD}" ]]; then
    echo -e "${YELLOW}RESULT: Files in the app/ directory changed.${NOCOL}" 
else
    echo -e "${VELLOW}RESULT: Files in the app/ directory unchanged, no processing to be triggered.${NOCOL}"
fi

if [[ ( -n "${APPS_FILES_MOD}" || "${BASE_IN_VER_CHANGED}" == "TRUE" ) ]]; then 
#if [L ( -n "$ (APPS_FILES_MOD}" I| "S (BASE _IN_VER_CHANGED}" == "TRUE" ) && "S (NS _LIST)" != "NULL" ]]; then
    
    echo -e "APPS_FILES_MOD:\n${APPS_FILES_MOD}"
    MAIN_APP_CHANGED="TRUE"
    REDEPLOY IMAGE="FALSE"
    USE_PROMOTE_IMAGE_TAG="FALSE"
    echo -e "${YELLOW}RESULT: MAIN_APP_CHANGED = ${MAIN_APP_CHANGED}${NOCOL}" 
    echo -e "${BLUE}STEP: Processing application folder changes${NOCOL}"

    if [[ "${GIT_BRANCH}" =~ ^feature/.* || "${GIT_BRANCH}" =~ ^dev/.* || "${GIT_BRANCH}" =~ ^release/. * || "${GIT_BRANCH}" =~ ^bugfix/.* || "${GIT_BRANCH}" =~ ^hotfix/.* ]]; then
        echo -e "${YELLOW}RESULT: On branch ${GIT_BRANCH}${NOCOL}"
        REBUILD_IMAGE="TRUE"
        REBUILD_IMAGE_REASON+=("# Application or kustomize base change on feature, develop, hotfix or bugfix branch triggers a rebuild.")
        VERSION="${BASE_IMAGE_TAG_OUT}.${GIT_SHA}"
        echo -e "${YELLOW}RESULT: New image to be built due to application level change in commit ${GIT_SHA}${NOCOL}"
        echo -e "${GREEN}VERSION: New version = ${VERSION}${NOCOL}"
        ## App folder subset change tests
        ## Gradle App Authnodes folder change details

        echo -e "${BLUE}Testing for gradle app authnodes changes in the app/authnodes/ directory${NOCOL}"
        GRADLE_FILES_MOD-$(git diff ${PARENT1_SHA} ${GIT_SHA} --name-only -- ./app/authnodes/)

        if [[ -n "${GRADLE_FILES_MOD}" ]]; then 
            echo -e "${YELLOW}RESULT: files in the app/authnodes/ directory changed${NOCOL}" 
            echo -e "${YELLOW}RESULT: New jar to be built version=${VERSION}-SNAPSHOT${NOCOL}" 
            GRADLE_APP_CHANGED="TRUE" 
            REBUILD_GRADLE_JAR="TRUE"
            sed -i"" "s/0.0.1-SNAPSHOT/${VERSION}-SNAPSHOT/g" app/authnodes/gradle.properties 
        fi
    elif [[ "${GIT_BRANCH}" =~ ^drh/.* ]]; then
        # DRH branch passes through all changes to VERSION, app-variables, app/ and deployer, deploying from PROMOTE_IMAGE_TAG
        echo -e "${YELLOW}RESULT: On branch ${GIT_BRANCH)${NOCOL}"
        echo -e "{YELLOW}RESULT: DRH deployment does not rebuild, VERSION is set in the special cases section.${NOCOL}"
    elif [[ "${GIT_BRANCH}" =~ ^develop$ ]1; then
        # Develop branch passes through all changes to VERSION, app-variables, app/ and deployer, deploying from PROMOTE_IMAGE_TAG
        echo -e "${YELLOW}RESULT: On branch ${GIT_BRANCH}${NOCOL}" 
        echo -e "${YELLOW}RESULT: Develop merge will rebuild.${NOCOL}"
    else
        echo -e "${RED}WARN: Application base has changes in unexpected branch ${GIT_BRANCH}.${NOCOL}" 
        echo -e "${RED}WARN: Rebuild requests are triggered only from feature, develop or hotfix branches. ${NOCOL}" 
        exit 1
    fi
fi 
echo_status
# Reset NS_LIST or keep if set.
APP_VARS_NS_MOD=${APP_VARS_NS_MOD:- "NULL"}
NS_LIST=${NS_LIST:- "NULL"}
##
##
## Kustomize changes
##
echo -e "${BLUE}==> STAGE 5: Testing for kustomize changes:${NOCOL}" 
if [[ "${MAIN_APP_CHANGED}" == "TRUE" ]]; then
    echo -e "${YELLOW}RESULT: As MAIN_APP_CHANGED = ${MAIN_APP_CHANGED}, there is no requirement to test for kustomize any changes as a rebuild or redeploy is already scheduled into target namedspaces.${NOCOL}" 
elif [[ "${MAIN_APP_CHANGED}" == "FALSE" ]]; then
    echo -e "${BLUE}TEST: Testing for kustomize base configuration changes in the deployer/kustomize/base/ directory${NOCOL}"
    BASE_FILES_MOD=$(git diff ${PARENT1_SHA} ${GIT_SHA} --name-only -- ./deployer/kustomize/base/)

    if [[ -n "${BASE_FILES_MOD}" ]]; then 
        echo -e "BASE_FILES_MOD:\n${BASE_FILES_MOD}" 
        KUSTOMIZE_BASE_CHANGED="TRUE"
        echo -e "${YELLOW}RESULT: Kustomize base files changed${NOCOL}" 
        if [[ "${NS_LIST}" != "NULL" && "${GIT_BRANCH}" != "develop" ]]; then 
            if [[ "${REBUILD_IMAGE}" = "FALSE" ]]; then
                REDEPLOY IMAGE= "TRUE"
                echo -e "${BLUE}Kustomize base changes exist without allied application changes.${NOCOL}" 
                echo -e "${YELLOW}RESULT: KUSTOMIZE_BASE_CHANGED = ${KUSTOMIZE_BASE_CHANGED}.${NOCOL}" 
                echo -e "${BLUE}STEP: Processing kustomize base changes.${NOCOL}" 
                echo -e "${BLUE}TEST: Outcome dependent upon out branch branch.${NOCOL}"

                if [[ "${GIT_BRANCH}" =~ ^feature.* || "${GIT_BRANCH} " =~ ^bugfix/.* || "${GIT_BRANCH}" =~ ^dev/.* || "${GIT_BRANCH}" =~ release/.* || "${GIT_BRANCH} " =~ ^hotfix/.* ]]; then 
                    echo -e "${YELLOW}RESULT: On branch ${GIT_BRANCH}.${NOCOL}" 
                    derive_version
                    echo -e "${GREEN}VERSION: PROMOTE_IMAGE_TAG image to be redeployed using new manifests.${NOCOL}"
                elif [[ "${GIT_BRANCH}" =~ drh/. * ]]; then
                    # DRH branch passes through all changes to VERSION, app-variables, app/ and deployer, deploying from PROMOTE_IMAGE_TAG
                    echo -e "${YELLOW}RESULT: On branch ${GIT_BRANCH}${NOCOL}" 
                    echo -e "${YELLOW}RESULT: DR deployment pass through.${NOCOL}"
                elif [[ "${GIT_BRANCH}" =~ develop ]]; then
                    # Todo - this condition never reached.
                    echo -e "${YELLOW}RESULT: On branch ${GIT_BRANCH}.${NOCOL}"

                elif [[ "${GIT_BRANCH}" =~ develop ]]; then        
                    # Todo - this condition never reached.
                    echo -e "${YELLOW}RESULT: On branch ${GIT_BRANCH}.${NOCOL}" 
                    derive_version
                    echo -e "${GREEN}VERSION: PROMOTE_IMAGE_TAG image to be redeployed using new manifests.${NOCOL}"
                else
                    echo -e "${RED}FATAL: Kustomize base has changes in illegal branch ${GIT_BRANCH}-${NOCOL}"
                    exit 1 
                fi
            elif [[" ${REBUILD_IMAGE}" == "TRUE" ]]; then 
                echo -e "${BLUE}Changes exist but REBUILD_IMAGE is already TRUE so processing bypassed.${NOCOL}"
            fi 
            echo_status
        else
            echo -e "${BLUE}Changes exist but with an empty namespace selection list.${NOCOL}"
        fi
    else
        echo -e "${YELLOW}RESULT: Kustomize base files unchanged${NOCOL}" 
    fi

    if [[ "${KUSTOMIZE_BASE_CHANGED}" == "TRUE" ]]; then
        echo -e "${YELLOW}RESULT: As KUSTOMIZE_BASE_CHANGED = ${KUSTOMIZE_BASE_CHANGED}, there is no requirement to test for kustomize overlay changes as a rebuild or redeploy is  already scheduled into target namedspaces.${NOCOL}" 
    elif [[ "${KUSTOMIZE_BASE_CHANGED}" == "FALSE" ]]; then
        echo -e "${BLUE}TEST: Testing for kustomize overlay namespace changes in the deployer/kustomize/overlay/ directory${NOCOL}"
        OVERLAY_FILES_MOD=$(git diff ${PARENTI_SHA} ${GIT_SHA} --name-only -- ./deployer/kustomize/overlay/)

        if [[ -n "${OVERLAY_FILES_MOD}" ]]; then
            echo -e "${YELLOW}RESULT: Overlay namespace folders changed:\n${OVERLAY_FILES_MOD}${NOCOL}"
            KUSTOMIZE_OVERLAY_NS_CONFIG_CHANGED="TRUE"
            if [[ "${DEFAULT_NS_USED}" == "TRUE" ]]; then
                echo -e "${YELLOW}TASK: Rationalise overlay namespace changes against default NS_LIST value."
                app_variables_ns="${APP_VARS_NS_MOD}" # is DEVI_NS
                OVERLAY_FOLDERS_LIST=$(git diff ${PARENTI_SHA} ${GIT_SHA} --name-only -- ./deployer/kustomize/overlay/ | sed 's|. */overlay/\(.*\)|\1|' | cut -d / -f1 | sort | uniq) # may not contain DEV1_NS
                create_ns_list # returns NULL if overlay change and default don't match 
                if [[ "${NS_LIST}" != "NULL" ]]; then
                    DEFAULT_NS_USED="FALSE" 
                fi 
            fi
        elif [[ -z "${OVERLAY_FILES_ MOD}" ]]; then
            echo -e "${YELLOW}RESULT: Overlay namespace folders unchanged: ${NOCOL}" 
        fi
        # This is the point in the gateway script where nothing has changed inside the main three tests, but where some tentative setting may have been made.
        # They are reconciled here.
        
        if [[ "${USE_PROMOTE_IMAGE_TAG}" == "FALSE" && ( "${DEFAULT_NS_USED}" == "TRUE" || "${NS_LIST}" == "NULL" ) ]]; then 
            echo -e "${YELLOW}RESULT: Overlay namespace folders unchanged${NOCOL}" 
            echo -e "${YELLOW}RESULT: Kustomize base folders unchanged${NOCOL}" 
            echo -e "${YELLOW}RESULT: Main app unchanged${NOCOL}" 
            echo -e "${BLUE}RESULT: Namespace list is now set to NULL. ${NOCOL}" 
            REBUILD_IMAGE="FALSE" 
            REDEPLOY_IMAGE="FALSE" 
            USE_PROMOTE_IMAGE_TAG="FALSE" 
            APP_VARS_NS_MOD="NULL"
            APP_VARS_NS_MOD= "NULL"
            NS_LIST= "NULL"
            REDEPLOY_IMAGE="FALSE"
            VERSION="NULL" 
        fi
        
        if [[ "${USE_PROMOTE_IMAGE_TAG}" == "TRUE" && "${NS_LIST}" == "NULL" ]]; then
            USE_PROMOTE_IMAGE_TAG="FALSE"
            REDEPLOY_IMAGE="FALSE" 
        fi
        if [[ "${USE_PROMOTE_IMAGE_TAG}" == "TRUE" && "${NS_LIST}" |= "NULL" ]]; then
            VERSION="${PROMOTE_IMAGE_TAG}"
        fi
        echo_status 
    fi 
fi

## Version value derivation

echo -e "${BLUE}==› STAGE 6: Finalize VERSION derivations: ${NOCOL}" 
if [[ "${GIT_BRANCH}" =~ ^develop$ ]]; then 
    echo -e "${BLUE}STEP: Applying develop branch overrides.${NOCOL}" 
    echo -e "${GREEN}ACTION: On develop every merge or commit triggers a rebuild.${NOCOL}" 
    echo -e "${GREEN}ACTION Set VERSION using GIT_SHA.${NOCOL}" 
    VERSION="${BASE_IMAGE_TAG_OUT}.${GIT_SHA}" 
    REBUILD_IMAGE="TRUE" 
    REDEPLOY_IMAGE="FALSE" 
    USE_PROMOTE_IMAGE_TAG="FALSE"

elif [[ "${GIT_BRANCH}" =~ ^drh/.* ]]; then
    echo -e "${BLUE}STEP: Applying drh branch overrides.${NOCOL}" 
    echo -e "${GREEN}ACTION: Set VERSION using PROMOTE_IMAGE_TAG. ${NOCOL}" 
    if [[ -z "${PROMOTE_IMAGE_TAG}" ]]; then
        echo "PROMOTE_IMAGE_TAG variable is empty, checking for BASE_IMAGE_TAG_OUT fall back" 
        if [[ -z "${BASE_IMAGE_TAG_OUT}" ]]; then
            echo "Failing DRH build due to empty PROMOTE _IMAGE_TAG and BASE _IMAGE _TAG_OUT variables"
            exit 1 
        else
            echo "PROMOTE_IMAGE_TAG variable was empty, but BASE_IMAGE_TAG_OUT exists"
            USE_PROMOTE_IMAGE_TAG- "BASE_IMAGE _TAG_OUT _OVERIDE"
            VERSION= "${BASE_IMAGE_TAG_OUT}" 
        fi 
    else
        echo "VERSION set using from PROMOTE_IMAGE_TAG"
        USE_PROMOTE_IMAGE_TAG="TRUE"
        VERSION="${PROMOTE_IMAGE_TAG}" 
    fi
    REBUILD_IMAGE=FALSE
    REDEPLOY_IMAGE=TRUE
elif [[ "${NS_LIST}" != "NULL" && ${VERSION} == "NULL" && ( "${APP_VARS_NS_CHANGED}" == "TRUE" || "${REDEPLOY_IMAGE}" == "TRUE" || ${VERSION_CHANGED} == "TRUE" ) ]]; then 
    
    echo -e "${BLUE}STEP: Applying VERSION overrides.${NOCOL}"
    if [[ "${GIT_BRANCH}" =~ ^release/.* || "${GIT_BRANCH}" =~ ^hotfix/.* || "${GIT_BRANCH}" =~ feature/.* || "${GIT_BRANCH}" =~ ^bugfix/.* || "${GIT_BRANCH}" =~ ^dev/.* ]]; then
        
        echo -e "${GREEN}ACTION: Deriving version.${NOCOL}" 
        derive_version
        if [[ "${GIT_BRANCH}" =~ ^release/.* ]]; then
            :
        # Fail safe for unit testing where legacy tests still exist doing direct commits into release.
        #REBUILD_IMAGE=TRUE
        #REDEPLOY_IMAGE=FALSE
        fi
    fi
else
    echo -e "${YELLOW}RESULT: Nothing to process.${NOCOL}"
fi

echo_status
echo_decisions
