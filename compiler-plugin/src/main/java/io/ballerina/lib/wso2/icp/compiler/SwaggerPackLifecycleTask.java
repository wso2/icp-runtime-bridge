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

import io.ballerina.projects.plugins.CompilerLifecycleEventContext;
import io.ballerina.projects.plugins.CompilerLifecycleTask;
import io.ballerina.tools.diagnostics.Diagnostic;
import io.ballerina.tools.diagnostics.DiagnosticFactory;
import io.ballerina.tools.diagnostics.DiagnosticInfo;
import io.ballerina.tools.diagnostics.DiagnosticSeverity;
import io.ballerina.tools.diagnostics.Location;
import io.ballerina.tools.text.LinePosition;
import io.ballerina.tools.text.LineRange;
import io.ballerina.tools.text.TextRange;

import java.io.IOException;
import java.net.URI;
import java.nio.file.FileSystem;
import java.nio.file.FileSystems;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardOpenOption;
import java.util.Map;
import java.util.Optional;

/**
 * Writes the OpenAPI documents collected by {@link SwaggerPackCollectTask} directly into the
 * already-built JAR as {@code swagger/...} entries. Does not touch the semantic model: by the
 * time code generation has completed, it is no longer safe to query.
 */
public class SwaggerPackLifecycleTask implements CompilerLifecycleTask<CompilerLifecycleEventContext> {

    private final OpenApiDocumentStore openApiDocs;

    public SwaggerPackLifecycleTask(OpenApiDocumentStore openApiDocs) {
        this.openApiDocs = openApiDocs;
    }

    @Override
    public void perform(CompilerLifecycleEventContext ctx) {
        if (openApiDocs.isEmpty()) {
            return;
        }
        Optional<Path> artifactPathOpt = ctx.getGeneratedArtifactPath();
        if (artifactPathOpt.isEmpty()) {
            return;
        }

        Path artifactPath = artifactPathOpt.get();
        URI jarUri = URI.create("jar:" + artifactPath.toUri());
        try (FileSystem jarFs = FileSystems.newFileSystem(jarUri, Map.of("create", "false"))) {
            for (Map.Entry<String, byte[]> entry : openApiDocs.entries()) {
                Path entryPath = jarFs.getPath(entry.getKey());
                Path parent = entryPath.getParent();
                if (parent != null) {
                    Files.createDirectories(parent);
                }
                Files.write(entryPath, entry.getValue(),
                        StandardOpenOption.CREATE, StandardOpenOption.TRUNCATE_EXISTING);
            }
        } catch (IOException e) {
            String detail = e.getMessage() == null ? e.getClass().getSimpleName() : e.getMessage();
            ctx.reportDiagnostic(error(PluginConstants.IO_ERROR_CODE,
                    "swagger-pack: failed to write OpenAPI definitions into "
                            + PluginConstants.escapeForDiagnostic(artifactPath.toString()) + ": "
                            + PluginConstants.escapeForDiagnostic(detail)));
        }
    }

    private Diagnostic error(String code, String message) {
        return DiagnosticFactory.createDiagnostic(
                new DiagnosticInfo(code, message, DiagnosticSeverity.ERROR), new NullLocation());
    }

    private static final class NullLocation implements Location {
        @Override
        public LineRange lineRange() {
            LinePosition from = LinePosition.from(0, 0);
            return LineRange.from("", from, from);
        }

        @Override
        public TextRange textRange() {
            return TextRange.from(0, 0);
        }
    }
}
