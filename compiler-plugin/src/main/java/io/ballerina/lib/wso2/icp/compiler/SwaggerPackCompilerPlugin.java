/*
 * Copyright (c) 2026, WSO2 LLC. (http://www.wso2.com) All Rights Reserved.
 *
 * WSO2 LLC. licenses this file to you under the Apache License,
 * Version 2.0 (the "License"); you may not use this file except
 * in compliance with the License.
 * You may obtain a copy of the License at
 *
 *    http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing,
 * software distributed under the License is distributed on an
 * "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
 * KIND, either express or implied. See the License for the
 * specific language governing permissions and limitations
 * under the License.
 */

package io.ballerina.lib.wso2.icp.compiler;

import io.ballerina.projects.plugins.CompilerPlugin;
import io.ballerina.projects.plugins.CompilerPluginContext;

/**
 * Compiler plugin entry point. When {@code remoteManagement = true} is set under
 * {@code [build-options]} in Ballerina.toml, generates an OpenAPI definition for every HTTP
 * service in the package and embeds it as a resource in the generated JAR.
 * <p>
 * OpenAPI generation needs a live semantic model, which is only safely queryable during the
 * analysis phase, while the JAR is only available once code generation has fully completed.
 * A {@code CodeAnalyzer} generates the OpenAPI documents up front and hands the bytes to a
 * {@code CompilerLifecycleListener} (via an {@link OpenApiDocumentStore} shared between the two,
 * created fresh per compilation) which writes them into the already-built JAR.
 */
public class SwaggerPackCompilerPlugin extends CompilerPlugin {

    @Override
    public void init(CompilerPluginContext pluginContext) {
        OpenApiDocumentStore openApiDocs = new OpenApiDocumentStore();
        pluginContext.addCodeAnalyzer(new SwaggerPackCodeAnalyzer(openApiDocs));
        pluginContext.addCompilerLifecycleListener(new SwaggerPackLifecycleListener(openApiDocs));
    }
}
