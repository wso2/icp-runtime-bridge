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

configurable string serverUrl = "https://localhost:9445";
configurable int heartbeatInterval = 10;
configurable string cert = "";
configurable boolean enableSSL = false;

// jwt configuration
configurable string jwtIssuer = "icp-runtime-jwt-issuer";
configurable string|string[] jwtAudience = "icp-server";
configurable decimal jwtExpiryTimeSeconds = 3600;

configurable string? runtime = ();
configurable string environment = "Dev";
configurable string integration = "default_integration";
configurable string project = "default_project";
configurable string secret = ?;

# Allow the ICP to tunnel workflow management commands to this runtime over the heartbeat
# channel, executed in-process by the workflow runtime — no management port, no API key.
# Set to false to stop this runtime's workflows being managed from the ICP.
configurable boolean enableWorkflowManagement = true;
configurable string runtimeHostUrl = "http://localhost";

public function loadConfig() returns IcpConfig|error {
    IcpConfig config = {
        serverUrl: serverUrl,
        heartbeatInterval: heartbeatInterval,
        cert: cert,
        enableSSL: enableSSL

    };
    return config;
}

// How many tunneled commands this runtime executes at once. A heartbeat batch is capped by
// the ICP at ten reads plus ten mutations, so a handful in flight covers a full batch in two
// or three rounds while keeping a bound on concurrent Temporal calls and worker threads: the
// answers arrive slightly later rather than the process being saturated.
configurable int tunneledCommandConcurrency = 4;
