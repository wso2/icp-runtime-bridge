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

import io.ballerina.projects.plugins.CompilerLifecycleContext;
import io.ballerina.projects.plugins.CompilerLifecycleListener;

/**
 * Registers the lifecycle task that embeds the OpenAPI documents collected by
 * {@link SwaggerPackCollectTask} into the generated JAR once code generation has completed.
 */
public class SwaggerPackLifecycleListener extends CompilerLifecycleListener {

    private final OpenApiDocumentStore openApiDocs;

    public SwaggerPackLifecycleListener(OpenApiDocumentStore openApiDocs) {
        this.openApiDocs = openApiDocs;
    }

    @Override
    public void init(CompilerLifecycleContext lifecycleContext) {
        lifecycleContext.addCodeGenerationCompletedTask(new SwaggerPackLifecycleTask(openApiDocs));
    }
}
