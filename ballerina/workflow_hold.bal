// Copyright (c) 2026, WSO2 LLC. (http://www.wso2.com) All Rights Reserved.
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

import ballerina/lang.runtime;
import ballerina/log;

// ================================================================================
// KEEPING A WORKFLOW INTEGRATION RUNNING
// ================================================================================
// An integration whose only inbound surface is workflow management has no listener
// of its own: the workflow worker polls a task queue but cannot trigger itself, and
// the heartbeat scheduler does not hold the program. Such an integration registers
// its workflows and exits immediately, leaving nothing to serve the commands the ICP
// tunnels to it.
//
// Management IS the entry point, so this bridge holds the program open for exactly
// as long as it offers one. Nothing else about program lifetime changes: an
// integration with a `main` or a service of its own behaves as Ballerina defines,
// and an integration with no workflows is untouched.

# Holds the program open while this bridge accepts workflow management commands.
# Opens no port and serves no requests — the commands arrive in heartbeat responses;
# this exists so the runtime has something to wait on.
isolated class WorkflowManagementHold {

    public isolated function 'start() returns error? {
        log:printInfo("Workflow management enabled: this integration accepts management " +
                "commands tunneled by the ICP, and will keep running to serve them");
        return;
    }

    public isolated function gracefulStop() returns error? {
        // The tunnel is request/response inside a heartbeat, so a command in flight
        // completes on its own thread; there is nothing to drain here yet. When the
        // tunnel grows longer-running operations, this is where they settle. The workflow
        // worker drains separately, through the workflow module's own stop handler.
        log:printInfo("Shutting down: no longer accepting tunneled workflow commands");
        return;
    }

    public isolated function immediateStop() returns error? => ();
}

// Typed as the class, not as `runtime:DynamicListener`: the wider type is not isolated,
// so a reference held at that type could not be read from an isolated function.
final WorkflowManagementHold workflowManagementHold = new;

// Whether the hold has been taken. Taking it twice would be harmless, but the hold
// cannot be released, so it is taken deliberately and once.
isolated boolean programHeld = false;

// Takes the hold when this bridge offers workflow management as an entry point: a
// workflow integration has registered, which is what makes the runtime manageable — there
// is no separate flag to opt in. Called from `registerWorkflowIntegration`, the moment the
// integration is known; the bridge's own init runs before the integration registers.
isolated function holdProgramForWorkflowManagement() {
    lock {
        if programHeld {
            return;
        }
        programHeld = true;
    }
    // A dynamic listener keeps the program running. The runtime offers no way to give a
    // hold back — deregistering does not let the program exit — so it is taken only once
    // the conditions above are known to hold.
    runtime:registerListener(workflowManagementHold);
}
