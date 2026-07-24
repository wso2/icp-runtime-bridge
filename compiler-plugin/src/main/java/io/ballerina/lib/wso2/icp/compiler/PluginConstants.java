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

/**
 * Constants used by the swagger-pack compiler plugin.
 */
public final class PluginConstants {

    public static final String SWAGGER_SUBDIR = "swagger";
    public static final String OPENAPI_FILE_SUFFIX = "_openapi.json";

    /**
     * Fixed-name resource listing every OpenAPI file packed alongside it, so runtime code (and
     * native-image resource registration, which needs concrete names rather than a directory
     * scan) only ever needs to look up known resource names, never enumerate the JAR.
     */
    public static final String INDEX_FILE_NAME = "index.json";

    public static final String SKIPPED_SERVICE_CODE = "SWAGGERPACK_101";
    public static final String IO_ERROR_CODE = "SWAGGERPACK_102";

    private PluginConstants() {
    }

    /**
     * Diagnostic messages are rendered through {@link java.text.MessageFormat}, which treats
     * unescaped {@code '}, {@code {} and {@code }} as syntax. Any interpolated, non-literal text
     * (base paths, exception messages, file paths, toString() output, ...) must be passed through
     * this before it goes into a diagnostic message, or a value containing e.g. {@code {id=...}}
     * (as many toString() implementations produce) will crash the build.
     */
    public static String escapeForDiagnostic(String raw) {
        return raw.replace("'", "''").replace("{", "'{'").replace("}", "'}'");
    }
}
