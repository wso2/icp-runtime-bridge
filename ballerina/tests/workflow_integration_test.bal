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

// What the bridge publishes about a workflow integration, and what it refuses to publish:
// the capability that gates command delivery, and the metadata document that must never
// break heartbeating, however badly the provider behaves.

import ballerina/test;

// The captured document must be immutable: an isolated function may not close over mutable
// storage, which is the same constraint the real providers work under.
isolated function metadataOf(map<json> & readonly doc) returns WorkflowMetadataProvider =>
    isolated function() returns map<json>|error => doc;

isolated function failingMetadata() returns map<json>|error =>
    error("workflow runtime is not ready");

@test:Config {}
function testCapabilityFollowsTheWorkflowExecutor() {
    // The ICP delivers WORKFLOW_MGMT only to runtimes that advertise this, and hosting
    // workflows is what makes a runtime manageable: a registered workflow integration
    // advertises the capability, and one that registered no workflows has nothing to
    // execute commands against. There is no separate opt-in.
    test:assertEquals(capabilitiesFor(true), ["workflowCommands"]);
    test:assertTrue(capabilitiesFor(false) is (),
            "No workflow integration: there is nothing to execute commands against");
}

@test:Config {}
function testRegisteredMetadataIsPublished() {
    map<json> & readonly document = {"workflows": [{"name": "expenseApproval"}]};
    _ = registerWorkflowIntegration(metadataOf(document), okExecutor);

    test:assertTrue(workflowExecutor() !is (), "The registered executor must be resolvable");
    test:assertEquals(currentWorkflowMetadata(), document);

    // Registering a workflow integration is what makes the runtime manageable: the capability
    // is advertised from that moment, with no separate flag to opt in.
    test:assertEquals(currentCapabilities(), ["workflowCommands"],
            "A registered workflow integration must advertise the capability");
}

@test:Config {dependsOn: [testRegisteredMetadataIsPublished]}
function testUnusableMetadataNeverBreaksHeartbeating() {
    // A heartbeat carrying no workflow metadata is fine; a heartbeat that fails to be built
    // is not. So a provider that errors, or hands back nothing, degrades to "no document".
    _ = registerWorkflowIntegration(failingMetadata, okExecutor);
    test:assertTrue(currentWorkflowMetadata() is (),
            "A failing provider must yield no document rather than propagate its error");

    _ = registerWorkflowIntegration(metadataOf({}), okExecutor);
    test:assertTrue(currentWorkflowMetadata() is (),
            "An empty document is nothing to publish");
}
