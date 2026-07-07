// Copyright (c) 2026, WSO2 LLC. (http://wso2.com).
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import ballerina/jballerina.java;
import ballerina/test;
import ballerina/workflow.management;

configurable int testPort = ?;

// ---------------------------------------------------------------------------
// Type definitions
//
// These names MUST match the Java Constants.* strings used in
// ValueCreator.createReadonlyRecordValue(currentModule, "<name>", map).
// The record is open (no '|' rest-field restriction) so extra fields placed
// by the Java layer are accepted without error.
// ---------------------------------------------------------------------------

type Artifact record {
    string name;
};

type RequestLimit record {
    int maxUriLength?;
    int maxHeaderSize?;
    int maxEntityBodySize?;
};

type Resource record {
    string[] methods;
    string url;
};

type ListenerDetail record {
    string name;
    string package;
    string state?;
    string protocol?;
    int port?;
    RequestLimit requestLimits?;
};

type ServiceDetail record {
    string name;
    string package;
    string basePath?;
    Artifact[] listeners;
    Resource[] resources;
};

type MainDetail record {
    string packageOrg;
    string packageName;
    string packageVersion;
};

// ---------------------------------------------------------------------------
// External function declarations — call the bridge's Java layer directly.
//
// Because these functions live in *this* module (wso2/artifacts_tests), the
// Java sees env.getCurrentModule() = "wso2/artifacts_tests" when they are
// invoked.  The isicpService() filter in Utils.java now uses a hard-coded
// org/name check (wso2/icp.runtime.bridge) so test services are no longer
// incorrectly filtered out.
// ---------------------------------------------------------------------------

isolated function getArtifacts(string resourceType, typedesc<anydata> t) returns Artifact[]|error =
@java:Method {
    'class: "io.ballerina.lib.wso2.icp.Artifacts"
} external;

isolated function getDetailedArtifact(string resourceType, string name) returns anydata|error =
@java:Method {
    'class: "io.ballerina.lib.wso2.icp.Artifacts"
} external;

// Returns the running program's main artifact, or () for a service-only
// program (no `main` function). Underpins the optional `main` field in the
// heartbeat.
isolated function getMainArtifact() returns MainDetail?|error =
@java:Method {
    'class: "io.ballerina.lib.wso2.icp.Artifacts"
} external;

// Returns the host of the first enabled HTTP listener, or () when there is
// none. Underpins the heartbeat's `workflowCallbackUrl`.
isolated function getCallbackHost() returns string? =
@java:Method {
    'class: "io.ballerina.lib.wso2.icp.Artifacts"
} external;

// ---------------------------------------------------------------------------
// Test helpers — encapsulate the fetch-assert-cast pattern used by multiple
// tests so the precondition and type cast live in exactly one place.
// ---------------------------------------------------------------------------

function getSingleListenerDetail() returns ListenerDetail|error {
    Artifact[] listeners = check getArtifacts("listeners", Artifact);
    test:assertEquals(listeners.length(), 1, "Pre-condition: expected one listener");
    return <ListenerDetail> check getDetailedArtifact("listeners", listeners[0].name);
}

function getSingleServiceDetail() returns ServiceDetail|error {
    Artifact[] services = check getArtifacts("services", Artifact);
    test:assertEquals(services.length(), 1, "Pre-condition: expected one service");
    return <ServiceDetail> check getDetailedArtifact("services", services[0].name);
}

// ---------------------------------------------------------------------------
// Tests — standard HTTP listener / service scenarios
// ---------------------------------------------------------------------------

// Verifies that exactly one user-defined listener is reported.
// A regression of the graphql:Listener wrapping bug would cause the internal
// http:Listener to appear as a second entry here.
@test:Config {}
function testExactlyOneListenerRegistered() returns error? {
    Artifact[] listeners = check getArtifacts("listeners", Artifact);
    test:assertEquals(listeners.length(), 1,
        "Expected exactly 1 listener; more likely means an internal wrapped listener leaked through");
}

// Verifies that exactly one user-defined service is reported.
// A regression of the graphql internal adapter bug would add a second service.
@test:Config {}
function testExactlyOneServiceRegistered() returns error? {
    Artifact[] services = check getArtifacts("services", Artifact);
    test:assertEquals(services.length(), 1,
        "Expected exactly 1 service; more likely means an internal adapter service leaked through");
}

// Verifies that the listener reports the port it was started on.
// A regression of the port-extraction bug would leave port absent.
@test:Config {}
function testListenerReportsCorrectPort() returns error? {
    ListenerDetail detail = check getSingleListenerDetail();
    test:assertEquals(detail.port, testPort,
        "Listener port should match the configured testPort value");
}

// Verifies that a plain HTTP listener reports "HTTP" as its protocol.
@test:Config {}
function testHttpListenerProtocol() returns error? {
    ListenerDetail detail = check getSingleListenerDetail();
    test:assertEquals(detail.protocol, "HTTP",
        "Plain HTTP listener should report protocol as 'HTTP'");
}

// Verifies that a freshly registered listener reports 'enabled' state.
@test:Config {}
function testListenerInitialStateIsEnabled() returns error? {
    ListenerDetail detail = check getSingleListenerDetail();
    test:assertEquals(detail.state, "enabled",
        "A newly registered listener should start in enabled state");
}

// Verifies the service's declared base path is preserved.
@test:Config {}
function testServiceBasePath() returns error? {
    ServiceDetail detail = check getSingleServiceDetail();
    test:assertEquals(detail.basePath, "/hello",
        "Service base path should match the declared '/hello' path");
}

// Verifies the service is linked to the registered listener.
@test:Config {}
function testServiceLinkedToListener() returns error? {
    Artifact[] listeners = check getArtifacts("listeners", Artifact);
    ServiceDetail detail = check getSingleServiceDetail();
    test:assertEquals(detail.listeners.length(), 1,
        "Service should be linked to exactly one listener");
    test:assertEquals(detail.listeners[0].name, listeners[0].name,
        "Service's listener reference should name the registered listener");
}

// Verifies the service exposes at least one resource method.
@test:Config {}
function testServiceHasResources() returns error? {
    ServiceDetail detail = check getSingleServiceDetail();
    test:assertTrue(detail.resources.length() > 0,
        "Service should expose at least one resource");
}

// Verifies idempotency: calling getArtifacts twice returns the same listener count,
// confirming that stale-entry pruning works and re-queries do not inflate the list.
@test:Config {}
function testRepeatedQueryDoesNotInflateListenerCount() returns error? {
    Artifact[] first = check getArtifacts("listeners", Artifact);
    Artifact[] second = check getArtifacts("listeners", Artifact);
    test:assertEquals(first.length(), second.length(),
        "Repeated getArtifacts calls should return a stable listener count");
    test:assertEquals(second.length(), 1,
        "Re-queried listener count should still be exactly 1");
}

// ---------------------------------------------------------------------------
// Tests — main artifact and workflow callback host
// ---------------------------------------------------------------------------

// Verifies that getMainArtifact resolves the main artifact without raising an
// error and returns a well-formed MainDetail. This guards the heartbeat's
// optional `main` field: the previous implementation raised
// "No main artifacts found" (and a malformed artifact raises a missing-field
// error), both of which the `check` below would surface as a test failure.
//
// Note: the complementary "service-only program -> nil" path cannot be
// exercised here because the `bal test` executor is itself a program with a
// generated main, so a main artifact is always present in the test repository.
@test:Config {}
function testMainArtifactResolvedWithoutError() returns error? {
    MainDetail? main = check getMainArtifact();
    test:assertTrue(main is MainDetail,
        "getMainArtifact should resolve a main artifact for the test executable");
    MainDetail detail = <MainDetail>main;
    test:assertTrue(detail.packageOrg.length() > 0,
        "Main artifact packageOrg should be populated");
    test:assertTrue(detail.packageName.length() > 0,
        "Main artifact packageName should be populated");
    test:assertTrue(detail.packageVersion.length() > 0,
        "Main artifact packageVersion should be populated");
}

// Verifies that the workflow callback host is derived from the running HTTP
// listener. A listener created as `new http:Listener(port)` binds to the
// default host 0.0.0.0.
@test:Config {}
function testCallbackHostFromHttpListener() returns error? {
    string? host = getCallbackHost();
    test:assertEquals(host, "0.0.0.0",
        "Callback host should be the default HTTP listener host");
}
