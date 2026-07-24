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

# Reads the OpenAPI definitions packed into the running JAR by the swagger-pack compiler plugin,
# for inclusion in the full heartbeat sent to the ICP server. Returns an empty map when
# `remoteManagement` was not enabled at build time, or the package has no HTTP services.
#
# + return - a map of packed file name to its parsed OpenAPI document
isolated function getPackedOpenApiDefinitions() returns map<json> = @java:Method {
    'class: "io.ballerina.lib.wso2.icp.OpenApiResources"
} external;
