// Copyright (c) 2026, WSO2 LLC. (https://www.wso2.com) All Rights Reserved.
//
// WSO2 LLC. licenses this file to you under the Apache License,
// Version 2.0 (the "License"); you may not use this file except
// in compliance with the License.
// You may obtain a copy of the License at
//
//    http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing,
// software distributed under the License is distributed on an
// "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
// KIND, either express or implied. See the License for the
// specific language governing permissions and limitations
// under the License.

import ballerina/log;

// ================================================================================
// WORKFLOW INTEGRATION
// ================================================================================
// When the integration uses ballerina/workflow (0.9.0+), this bridge publishes the
// workflow metadata document (definitions, human tasks, activities, agents — with
// JSON schemas) in full heartbeats, and executes WORKFLOW_MGMT commands the ICP
// tunnels back in heartbeat responses (see command_tunnel.bal for the generic
// command plumbing). The wiring is registered by a glue file this package's
// compiler plugin generates into the user's package — importing this bridge is all
// a user does. The glue calls the stable workflow.management Ballerina API, so
// this package keeps zero compile-time dependency on ballerina/workflow.

# Supplies the workflow metadata document to publish in full heartbeats.
# Typically an adapter over `workflow.management:getWorkflowMetadata`.
public type WorkflowMetadataProvider isolated function () returns map<json>|error;

# Supplies the Temporal task queue the integration's workflow worker serves, or nil before
# the worker has registered. Typically an adapter over
# `workflow.management:getWorkflowTaskQueue`. Read each heartbeat round: a queue known only
# after startup promotes the next round to a full heartbeat, which publishes it.
public type WorkflowTaskQueueProvider isolated function () returns string?;

# The capability advertised to the ICP while this runtime accepts tunneled workflow
# management commands. The ICP gates delivery on it.
const string WORKFLOW_COMMANDS_CAPABILITY = "workflowCommands";

isolated WorkflowMetadataProvider? workflowMetadataProvider = ();
isolated TunneledCommandExecutor? workflowCommandExecutor = ();
isolated WorkflowTaskQueueProvider? workflowTaskQueueProvider = ();

# Registers the integration's workflow runtime with this bridge. Called at module
# init by the compiler-plugin-generated glue; may also be called directly by
# advanced integrations that assemble their own metadata.
#
# + metadataProvider - Supplies the metadata document for full heartbeats
# + commandExecutor - Executes WORKFLOW_MGMT commands, typically an adapter over
#                     `workflow.management:executeCommand`
# + taskQueueProvider - Supplies the worker's Temporal task queue, reported beside
#                       capabilities; optional so older glue keeps binding
# + return - `true`, so the generated glue can bind the call at module level
public isolated function registerWorkflowIntegration(WorkflowMetadataProvider metadataProvider,
        TunneledCommandExecutor commandExecutor,
        WorkflowTaskQueueProvider? taskQueueProvider = ()) returns boolean {
    lock {
        workflowMetadataProvider = metadataProvider;
    }
    lock {
        workflowCommandExecutor = commandExecutor;
    }
    lock {
        workflowTaskQueueProvider = taskQueueProvider;
    }
    log:printDebug("Workflow integration registered with the ICP bridge");
    // Management is this integration's entry point, so keep the program running while
    // the bridge offers it — otherwise an integration with no service of its own exits
    // as soon as it has registered. See workflow_hold.bal.
    holdProgramForWorkflowManagement();
    return true;
}

# Returns the registered WORKFLOW_MGMT executor, or `()` when no workflow
# integration is registered.
#
# + return - The executor, or `()`
isolated function workflowExecutor() returns TunneledCommandExecutor? {
    lock {
        return workflowCommandExecutor;
    }
}

# Returns the workflow worker's Temporal task queue, or `()` when no workflow
# integration registered a provider or the worker has not started yet.
#
# + return - The task queue, or `()`
isolated function currentWorkflowTaskQueue() returns string? {
    WorkflowTaskQueueProvider? provider;
    lock {
        provider = workflowTaskQueueProvider;
    }
    if provider is () {
        return ();
    }
    return provider();
}

# Returns the current workflow metadata document, or `()` when no workflow
# integration is registered, the document is empty, or the provider fails
# (failures are logged and never break heartbeating).
#
# + return - The metadata document, or `()`
isolated function currentWorkflowMetadata() returns map<json>? {
    WorkflowMetadataProvider? provider;
    lock {
        provider = workflowMetadataProvider;
    }
    if provider is () {
        return ();
    }
    map<json>|error metadata = provider();
    if metadata is error {
        log:printWarn("Failed to read workflow metadata for the heartbeat", metadata);
        return ();
    }
    return metadata.length() > 0 ? metadata : ();
}

# Returns the capabilities this runtime advertises to the ICP, or `()` when there
# are none. `workflowCommands` is advertised only when a workflow integration is
# registered AND `enableWorkflowManagement` is true (the default) — the
# server only tunnels a capability-gated command to runtimes that advertised it.
#
# + return - The capability names, or `()`
isolated function currentCapabilities() returns string[]? {
    return capabilitiesFor(workflowExecutor() !is (), enableWorkflowManagement);
}

// Advertised only when both hold: a workflow integration registered an executor, and the
// deployment opted in. The ICP tunnels WORKFLOW_MGMT only to runtimes that advertised it, so
// this is where the integration — not the control plane — decides it may be managed remotely.
isolated function capabilitiesFor(boolean hasWorkflowExecutor, boolean managementEnabled)
        returns string[]? {
    if hasWorkflowExecutor && managementEnabled {
        return [WORKFLOW_COMMANDS_CAPABILITY];
    }
    return ();
}
