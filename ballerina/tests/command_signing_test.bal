// Copyright (c) 2026, WSO2 LLC. (https://www.wso2.com).
//
// WSO2 LLC. licenses this file to you under the Apache License,
// Version 2.0 (the "License"); you may not use this file except
// in compliance with the License.
// You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing,
// software distributed under the License is distributed on an
// "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
// KIND, either express or implied.  See the License for the
// specific language governing permissions and limitations
// under the License.

import ballerina/test;

// The same vectors are asserted by the ICP's and the MI agent's tests, computed
// independently; the three sides interoperate only if all three produce these.
const string SIGNING_KEY = "key-material-that-is-at-least-32-bytes-long";
const string STOP_SIGNATURE = "W3lXJP/dtlfHIFCgTbMeQlTBF2tOpKIUmLUlKBWq210=";

function stopCommand() returns ControlCommand => {
    commandId: "cmd-1",
    runtimeId: "runtime-1",
    targetArtifact: {name: "greetingService", "package": "hello/icp"},
    action: STOP,
    issuedAt: [0, 0],
    status: PENDING,
    signature: STOP_SIGNATURE
};

@test:Config {}
function testTheIcpsSignatureVerifies() {
    test:assertEquals(commandSignatureRefusal(stopCommand(), "runtime-1", SIGNING_KEY, true), ());

    string payload = "{\"commandId\":\"mio-1.runtime-1\",\"operation\":\"management\",\"params\":" +
        "{\"method\":\"POST\",\"path\":\"/management/sequences\",\"body\":{\"name\":\"fault\",\"statistics\":\"enable\"}}," +
        "\"deadline\":\"2026-09-30T10:00:00Z\"}";
    ControlCommand withPayload = {commandId: "mio-1.runtime-1", runtimeId: "runtime-1",
        targetArtifact: {name: "management"}, action: WORKFLOW_MGMT, issuedAt: [0, 0], status: PENDING,
        payload: payload, signature: "3zoKUUS0CVRD/4ccF6nqssTJfGQgx7sPyj8nG980VRA="};
    // The MI vector was signed with action MI_MGMT; the same fields under another action must not verify.
    test:assertTrue(commandSignatureRefusal(withPayload, "runtime-1", SIGNING_KEY, false) is string);
}

@test:Config {}
function testATamperedOrMisdirectedCommandIsRefused() {
    ControlCommand started = stopCommand();
    started.action = START;
    test:assertTrue(commandSignatureRefusal(started, "runtime-1", SIGNING_KEY, false) is string,
            "Turning a STOP into a START must break the signature");

    ControlCommand other = stopCommand();
    other.targetArtifact = {name: "adminService", "package": "hello/icp"};
    test:assertTrue(commandSignatureRefusal(other, "runtime-1", SIGNING_KEY, false) is string,
            "Retargeting the command must break the signature");

    test:assertTrue(commandSignatureRefusal(stopCommand(), "runtime-2", SIGNING_KEY, false) is string,
            "A command signed for another replica must not verify");

    ControlCommand garbled = stopCommand();
    garbled.signature = "%%%";
    test:assertTrue(commandSignatureRefusal(garbled, "runtime-1", SIGNING_KEY, false) is string);
}

@test:Config {}
function testUnsignedIsRefusedOnlyWhenRequired() {
    ControlCommand unsigned = stopCommand();
    unsigned.signature = ();
    test:assertEquals(commandSignatureRefusal(unsigned, "runtime-1", SIGNING_KEY, false), ());
    test:assertTrue(commandSignatureRefusal(unsigned, "runtime-1", SIGNING_KEY, true) is string);
}
