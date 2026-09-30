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

import ballerina/crypto;
import ballerina/jwt;
import ballerina/lang.array;

final [string, string] [keyId, keyMaterial] = check parseSecretWithKeyId(secret);

final readonly & jwt:IssuerSignatureConfig jwtSignatureConfig = {
    algorithm: jwt:HS256,
    config: keyMaterial
};

isolated function parseSecretWithKeyId(string secret) returns [string, string]|error {
    int? periodIndex = secret.indexOf(".");
    string keyId;
    string keyMaterial;

    if periodIndex is int && periodIndex > 0 {
        keyId = secret.substring(0, periodIndex);
        keyMaterial = secret.substring(periodIndex + 1);
    } else {
        keyId = "";
        keyMaterial = secret;
    }
    if keyMaterial.toBytes().length() < 32 {
        return error(string `Key material insufficient for HS256: ${keyMaterial.toBytes().length()} bytes (requires 32 bytes)`);
    }
    return [keyId, keyMaterial];
}

isolated function generateJwtToken() returns string|error {
    jwt:IssuerConfig issuerConfig = {
        issuer: jwtIssuer,
        audience: jwtAudience,
        customClaims: {"scope": "runtime_agent"},
        expTime: jwtExpiryTimeSeconds,
        signatureConfig: jwtSignatureConfig,
        keyId: keyId
    };
    string token = check jwt:issue(issuerConfig);
    return token;
}

// Names the field list below; the ICP signs the same version.
const string COMMAND_SIGNATURE_VERSION = "v1";

# The bytes a command's signature covers, exactly as the ICP computes them: version, runtime
# id, command id, action, target artifact name and package, and payload, each written as
# `<UTF-8 byte length>:<value>` so no field can run into the next. The payload is the JSON
# string as delivered, so neither side depends on how the other writes JSON; the runtime id
# is this runtime's own, which is what binds a command to the replica it was issued for.
isolated function commandSigningInput(string runtimeId, ControlCommand command) returns byte[] {
    anydata artifactPackage = command.targetArtifact["package"];
    string[] fields = [
        COMMAND_SIGNATURE_VERSION,
        runtimeId,
        command.commandId,
        command.action,
        command.targetArtifact.name,
        artifactPackage is string ? artifactPackage : "",
        command.payload ?: ""
    ];
    string input = "";
    foreach string 'field in fields {
        input += 'field.toBytes().length().toString() + ":" + 'field;
    }
    return input.toBytes();
}

# Why a control command must not run, or `()` when it may.
#
# Checked before anything in the command is acted on, including its command id: a command
# that fails here is dropped and not reported, so a forged one cannot fail a genuine command
# that shares its id.
#
# + required - Refuse an unsigned command too, rather than only a badly signed one
isolated function commandSignatureRefusal(ControlCommand command, string runtimeId, string key,
        boolean required) returns string? {
    string? signature = command.signature;
    if signature is () {
        return required ? "it is unsigned and requireSignedCommands is on" : ();
    }
    byte[]|error given = array:fromBase64(signature);
    if given is error {
        return "its signature is not Base64";
    }
    byte[]|error expected = crypto:hmacSha256(commandSigningInput(runtimeId, command), key.toBytes());
    if expected is error {
        return "its signature could not be computed: " + expected.message();
    }
    return constantTimeEquals(expected, given) ? () : "its signature does not match";
}

// Compares every byte whatever the first difference, so the time taken says nothing about
// how much of a forged signature was right.
isolated function constantTimeEquals(byte[] a, byte[] b) returns boolean {
    if a.length() != b.length() {
        return false;
    }
    int difference = 0;
    foreach int i in 0 ..< a.length() {
        difference |= a[i] ^ b[i];
    }
    return difference == 0;
}
