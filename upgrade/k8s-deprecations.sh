#!/bin/bash
##########################################################################
# This script finds all deprecations in k8s version.                     #
# Author: Mukund                                                         #
# Date: 26th April 2020                                                  #
# Version: 1.0                                                           #
##########################################################################

START_TIME=$(date +%s)
VERSION="$1"
FLAG="$2"
RED='\033[1;31m'
GREEN='\033[0;32m'
BOLD='\033[1;30m'
END='\033[0m'
TICK='\xE2\x9C\x94'

verbose () {
    [ "$FLAG" == "-v" ] && true
}

separator () {
    printf '\n'
}

indent () {
    x="$1"
    awk '{printf "%"'"$x"'"s%s\n", "", $0}'
}

usage () {
    [[ -z "$KUBECONFIG" ]] && echo "[WARNING]: Export KUBECONFIG before running the script."
    echo "Usage: "
    echo "./k8s-deprecations.sh -h/-help/--h           help"
    echo "./k8s-deprecations.sh                        gets all deprecations in k8s version"
    echo "./k8s-deprecations.sh <-v>                   debug mode, all deprecations in k8s version alongwith objects using it"
    exit
}

get_swagger () {
    separator
    echo "Fetching all objects from kubenetes repo..."
    swagger_json="$(curl -s swagger-v"$VERSION".json https://raw.githubusercontent.com/kubernetes/kubernetes/v"$VERSION"/api/openapi-spec/swagger.json)"
    deprecated_apiversion="$(echo "$swagger_json" | jq -r '.definitions | keys[] as $k | "\($k): \(.[$k] | .description)"' | grep -w DEPRECATED)"
}

fetch_deprecated_objects () {
    deprecated_object_kind="$1"
    deprecated_object_json="$(kubectl get $deprecated_object_kind -A -o json)"
    deprecated_apiversion_list="$(echo "$DEPRECATED_LIST" | grep "$deprecated_object_kind" | awk -F ':' '{print $2}' | uniq)"

    while read -r line;
    do
        deprecated_object_list="$(echo "$deprecated_object_json" | jq -rj '.items[] | select(.apiVersion | contains("'$line'")) | .metadata.namespace, ": ",.metadata.name,"\n"')"
        if [[ -z "$deprecated_object_list" ]];
        then
            echo -e "${GREEN}${TICK} 0 $deprecated_object_kind using deprecated apirVersion: $line${END}" | indent 10
        else
            echo -e "${RED}Deprecated $deprecated_object_kind found using deprecated apiVersion: $line${END}" | indent 10
            echo -e "$deprecated_object_list" | indent 10
        fi
    done <<< "$deprecated_apiversion_list"
}

main () {
    get_swagger
    separator
    echo -e "${RED}Below is the list of deprecated apiVersion: ${END}"
    separator
    DEPRECATED_LIST="$(echo  "$deprecated_apiversion" | awk -F ':' '{print $1}' | grep -v DEPRECATED | awk -F '.' '{print $NF":",$(NF-2)"/"$(NF-1)}')"
    deprecated_kind="$(echo "$DEPRECATED_LIST" | awk -F ':' '{print $1}')"
    echo  "$DEPRECATED_LIST"
    separator
    CURRENT_API_RESOURCES="$(kubectl api-resources --no-headers)"
    checked_object_kind_list=""

    while read -r line;
    do
        separator
        checked_object_kind="$line"
        echo -e "Checking if ${BOLD}$line${END} kind objects exists in the cluster... "
        local apiversion="$(echo "$DEPRECATED_LIST" | grep "$line" | awk -F ':' '{print $2}' | uniq)"
        if [[ "$CURRENT_API_RESOURCES" == *"$line"* && ! "$checked_object_kind_list" == *"$checked_object_kind"* ]];
        then
            echo -e "${RED}$line kind objects found${END} which may be using deprecated apiVersion:"$apiversion""
            verbose && fetch_deprecated_objects "$checked_object_kind"
            checked_object_kind_list="$checked_object_kind_list,$checked_object_kind"
        else
            echo -e "${GREEN}${TICK} $line: no objects found!${END}"
        fi
    done <<< "$deprecated_kind"
}


[[ "$1" == "-h" || "$1" == "--h" || "$1" == "-help" ]] && usage
main

END_TIME=$(date +%s)
EXECUTION_TIME=$((END_TIME-START_TIME))
separator
echo "Total time taken:" "$EXECUTION_TIME"s