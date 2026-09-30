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

import ballerina/log;
import ballerina/time;

final string HEARTBEAT_VERSION = "v1.0";

// === Enums ===

public enum RuntimeType {
    BI
};

public enum RuntimeStatus {
    RUNNING,
    OFFLINE
};

public enum ArtifactState {
    ENABLED = "enabled",
    DISABLED = "disabled"
};

public enum ArtifactType {
    SERVICE = "services",
    LISTENER = "listeners"
};

// === Core Domain Types ===

public type Artifact record {
    string name;
};

public type Resource record {
    string[] methods;
    string url;
};

public type ListenerDetail record {
    *Artifact;
    string protocol?;
    string package;
    ArtifactState state = "enabled";
};

public type ServiceDetail record {
    *Artifact;
    string? basePath;
    string package;
    Artifact[] listeners;
    Resource[] resources;
    ArtifactState state = "enabled";
};

public type ArtifactDetail ServiceDetail|ListenerDetail|MainDetail;

public type MainDetail record {
    string packageOrg;
    string packageName;
    string packageVersion;
};

public type Artifacts record {
    ListenerDetail[] listeners?;
    ServiceDetail[] services?;
    MainDetail main?;
};

public type Node record {
    string platformName = "ballerina";
    string platformVersion?;
    string platformHome?;
    string ballerinaHome?;
    string osName?;
    string osVersion?;
};

// === Runtime Communication Types ===

public type Heartbeat record {|
    string runtimeId;
    string runtime?;
    RuntimeType runtimeType;
    string heartbeatVersion = HEARTBEAT_VERSION;
    RuntimeStatus status;
    string environment = environment;
    string project;
    string component;
    string version?;
    Node nodeInfo;
    Artifacts artifacts;
    string runtimeHash;
    time:Utc timestamp;
    map<log:Level> logLevels?;
    string tryItHost?;
    map<json> openApiDefinitions?;
    // The workflow metadata document (definitions, human tasks, activities, agents, with
    // JSON schemas) provided by the integration's workflow runtime via the compiler-plugin
    // glue. Sent only on full heartbeats and only when the server advertised
    // "workflowMetadata" in supportedHeartbeatFields. Like openApiDefinitions it is
    // startup-constant, so it is deliberately NOT part of HeartbeatForHash.
    map<json> workflowMetadata?;
    // Optional capabilities this runtime advertises to the server — e.g. "workflowCommands"
    // when the integration accepts tunneled workflow management commands. The server must
    // never send a capability-gated command to a runtime that did not advertise it.
    string[] capabilities?;
    // The Temporal task queue the integration's workflow worker serves. Runtime state like
    // capabilities — chosen at program startup, so it can differ between two runtimes of one
    // program — which is why it travels here rather than inside the workflow metadata
    // document. A project's integrations share one Temporal namespace, and the queue is what
    // separates one integration's executions from its neighbours' there. Short, so like
    // capabilities it is sent unconditionally and stays out of the hash: it cannot change
    // without a restart, and a restart re-registers with a full heartbeat anyway.
    string workflowTaskQueue?;
|};

public type HeartbeatForHash record {|
    string runtimeId;
    string runtime?;
    RuntimeType runtimeType;
    string heartbeatVersion = HEARTBEAT_VERSION;
    RuntimeStatus status;
    string environment;
    string project;
    string component;
    string version?;
    Node nodeInfo;
    Artifacts artifacts;
    map<log:Level> logLevels?;
    string tryItHost?;
|};

public type DeltaHeartbeat record {|
    string runtimeId;
    string heartbeatVersion = HEARTBEAT_VERSION;
    string runtimeHash;
    time:Utc timestamp;
|};

// === ICP Control Types ===

public enum ControlCommandStatus {
    PENDING,
    SENT,
    ACKNOWLEDGED,
    FAILED,
    COMPLETED
};

public enum ControlAction {
    START,
    STOP,
    SET_LOGGER_LEVEL,
    // A tunneled workflow management operation (list/start workflows, complete human
    // tasks, ...), executed in-process via the command tunnel (command_tunnel.bal).
    // The ICP only sends this to runtimes that advertised the "workflowCommands"
    // capability. The command's `payload` is a TunneledCommandPayload JSON string;
    // the result is posted back on POST /icp/commandResult.
    WORKFLOW_MGMT
};

# The JSON carried in a tunneled control command's `payload`.
#
# + commandId - Correlation ID; the result is posted back under this ID
# + operation - Dot-qualified operation name (e.g. `humanTasks.complete`)
# + params - Operation parameters, keyed like the management API's query/path/body
# + identity - The end user the ICP executes this on behalf of
# + deadline - ISO-8601 instant after which the command is dropped unexecuted
public type TunneledCommandPayload record {|
    string commandId;
    string operation;
    map<json> params = {};
    CommandIdentity identity = {};
    string deadline?;
|};

# The caller identity a tunneled command executes on behalf of. Same semantics as
# the management API's `x-user-id` / `x-user-roles` headers.
#
# + userId - The user ID, or `()` when unknown
# + roles - The caller's roles; empty means "no roles"
public type CommandIdentity record {|
    string? userId = ();
    string[] roles = [];
|};

# The outcome of a tunneled command, posted to `POST /icp/commandResult`.
#
# + runtimeId - This runtime's ID
# + commandId - The command's correlation ID
# + status - `COMPLETED` when the operation executed (regardless of its HTTP-level
#            outcome), `FAILED` when it could not be executed at all
# + httpStatus - The status code the corresponding management API would have returned
# + body - The response body, byte-identical to the management API's
public type TunneledCommandResult record {|
    string runtimeId;
    string commandId;
    string status;
    int httpStatus;
    json body;
|};

public type ControlCommand record {
    string commandId;
    string runtimeId;
    Artifact targetArtifact;
    ControlAction action;
    time:Utc issuedAt;
    ControlCommandStatus status; // pending, sent, acknowledged, failed
    string payload?;
    // HMAC-SHA256 the ICP puts on every command, over the fields this runtime acts on and
    // keyed with the secret it heartbeats with; see `commandSignatureRefusal`.
    string signature?;
};

public type LoggerLevelPayload record {|
    string componentName;
    string componentPackage?;
    log:Level logLevel;
|};

public type HeartbeatResponse record {
    boolean acknowledged;
    boolean fullHeartbeatRequired?;
    ControlCommand[] commands = [];
    // Names of optional Heartbeat fields the connected ICP server understands (e.g.
    // "tryItHost", "openApiDefinitions", "workflowMetadata"). Absent on servers that
    // predate this negotiation, so the bridge treats a missing value as "no optional
    // fields supported" rather than an error.
    //
    // Negotiation is about not sending payload-heavy documents a server cannot use — it
    // is not a compatibility requirement for every new field: the server parses Heartbeat
    // as an open record, so a field it does not know is ignored rather than rejected.
    // That is why `capabilities`, a short string array, is sent unconditionally while
    // `workflowMetadata` and `openApiDefinitions` are gated.
    string[] supportedHeartbeatFields?;
    // Boost hint: when set (seconds, typically 1), the server wants the next heartbeat
    // sooner than the configured interval — e.g. while a user is actively working with
    // workflow views and management commands are being tunneled. The bridge follows up
    // within the same job tick, bounded by the regular interval, so a stale hint can
    // never turn the bridge into a tight loop the server didn't ask for.
    int nextHeartbeatInSeconds?;
};

// === Configuration ===

public type IcpConfig record {|
    string serverUrl;
    string cert;
    boolean enableSSL;
    int heartbeatInterval;
|};

public type RequestLimit record {
    int maxUriLength;
    int maxHeaderSize;
    int maxEntityBodySize;
};
