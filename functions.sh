#!/bin/bash
# -*- coding: utf-8 -*-
# Copyright 2021 Red Hat, Inc.
# All Rights Reserved.
#
#    Licensed under the Apache License, Version 2.0 (the "License"); you may
#    not use this file except in compliance with the License. You may obtain
#    a copy of the License at
#
#         http://www.apache.org/licenses/LICENSE-2.0
#
#    Unless required by applicable law or agreed to in writing, software
#    distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
#    WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
#    License for the specific language governing permissions and limitations
#    under the License.
#
# functions - shiftstack-ci specific functions
#

# ensure we don't re-source this in the same environment
[[ -n "${_SHIFTSTACK_CI_FUNCTIONS_SOURCED}" ]] && return 0
declare -r _SHIFTSTACK_CI_FUNCTIONS_SOURCED=1

# Save trace setting
_XTRACE_SHIFTSTACK_CI=$(set +o | grep xtrace)
set +o xtrace

# check_mcp_updating - check if a MachineConfig pool is updating
function check_mcp_updating() {
    # Time to wait between checks
    local interval=$1
    # Number of times to check if the MCP is updated
    local count=$2
    # e.g. "worker" or "master"
    local role=$3

    while [ $((count)) -gt 0 ]; do
        UPDATING=false
        while read -r i
        do
            name=$(echo "${i}" | awk '{print $1}')
            updating=$(echo "${i}" | awk '{print $4}')
            if [[ "${updating}" == "True" ]]; then
                UPDATING=true
            else
                echo "Waiting for MachineConfig pool ${name} to start rolling out"
                UPDATING=false
            fi
        done <<< "$(oc get mcp "${role}" --no-headers)"

        if [[ "${UPDATING}" == "true" ]]; then
            echo "MachineConfig pool for ${role} has successfully started to roll out"
            return 0
        else
            sleep "${interval}"
            count=$((count))-1
        fi

        if [[ $((count)) -eq 0 ]]; then
            echo "MachineConfig pool for ${role} has not started to roll out:"
            oc get mcp "${name}"
            return 1
        fi
    done
}

# check_mcp_updated - check if a MachineConfig pool is updated
function check_mcp_updated() {
    # Time to wait between checks
    local interval=$1
    # Number of times to check if the MCP is updated
    local count=$2
    # e.g. "worker" or "master"
    local role=$3

    while [ $((count)) -gt 0 ]; do
        READY=false
        while read -r i
        do
            name=$(echo "${i}" | awk '{print $1}')
            updated=$(echo "${i}" | awk '{print $3}')
            updating=$(echo "${i}" | awk '{print $4}')
            degraded=$(echo "${i}" | awk '{print $5}')
            degraded_machine_cnt=$(echo "${i}" | awk '{print $9}')

            if [[ "${updated}" == "True" && "${updating}" == "False" && "${degraded}" == "False" && $((degraded_machine_cnt)) -eq 0 ]]; then
                READY=true
            else
                echo "Waiting for MachineConfig pool ${name} to rollout"
                READY=false
            fi
        done <<< "$(oc get mcp "${role}" --no-headers)"

        if [[ "${READY}" == "true" ]]; then
            echo "MachineConfig pool for ${role} has successfully rolled out"
            return 0
        else
            sleep "${interval}"
            count=$((count))-1
        fi

        if [[ $((count)) -eq 0 ]]; then
            echo "MachineConfig pool for ${role} did not rolled out:"
            oc get mcp "${name}"
            return 1
        fi
    done
}

# wait_for_no_node - Wait for nodes with a specific role to be removed from the cluster
function wait_for_no_node() {
    # Time to wait between checks
    local interval=$1
    # Number of times to check if the MCP is updated
    local count=$2
    # e.g. "worker"
    local role=$3

    while [ $((count)) -gt 0 ]; do
        GONE=false
        NODES=$(oc get node --no-headers)
        if [[ ${NODES} != *"${role}"* ]]; then
            echo "All nodes are gone for ${role}"
            GONE=true
            break
        fi
        echo "Waiting for all nodes to be gone for ${role}"
        sleep "$interval"
        count=$((count - 1))
    done

    if [[ ${GONE} == "false" ]]; then
        echo "Timed out waiting for all nodes for ${role} to be gone"
        echo "${NODES}"
        exit 1
    fi
}

# wait for nodes - Wait for nodes with a specific role to be added to the cluster
function wait_for_nodes() {
    # Time to wait between checks
    local interval=$1
    # Number of times to check if the MCP is updated
    local count=$2
    # e.g. "worker"
    local role=$3

    while [ $((count)) -gt 0 ]; do
        READY=false
        while read -r i
        do
            name=$(echo "${i}" | awk '{print $1}')
            status=$(echo "${i}" | awk '{print $2}')
            if [[ "${status}" == "Ready" ]]; then
                echo "Node for ${name} is ready"
                READY=true
            else
                echo "Waiting for ${role} nodes to be ready"
            fi
        done <<< "$(oc get node --no-headers -l node-role.kubernetes.io/"${role}" 2>&1)"

        if [[ ${READY} == "true" ]]; then
            echo "Nodes for ${role} are ready"
            return 0
        else
            sleep "${interval}"
            count=$((count))-1
        fi

        if [[ $((count)) -eq 0 ]]; then
            echo "Timed out waiting for ${role} nodes to be ready"
            oc get node
            return 1
        fi
    done
}

# check_pod_ready - Check that a pod is ready within a namespace
function check_pod_ready() {
    local interval=$1
    local count=$2
    local namespace=$3
    local pod=$4

    while [ $((count)) -gt 0 ]; do
        READY=false
        while read -r i
        do
            pod_name=$(echo "${i}" | awk '{print $1}')
            pod_phase=$(echo "${i}" | awk '{print $3}')
            if [[ "${pod_phase}" == "Running" ]]; then
                READY=true
            else
                echo "Waiting for Pod ${pod_name} to be ready"
                READY=false
            fi
        done <<< "$(oc -n "${namespace}" get pods "${pod}" --no-headers)"

        if [[ "${READY}" == "true" ]]; then
            echo "Pod ${pod} has successfully been deployed"
            return 0
        else
            sleep "${interval}"
            count=$((count))-1
        fi

        if [[ $((count)) -eq 0 ]]; then
            echo "Pod ${pod} did not successfully deploy"
            oc -n "${namespace}" get pods "${pod}"
            return 1
        fi
    done
}

# Restore xtrace
$_XTRACE_SHIFTSTACK_CI
