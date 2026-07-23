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

import io.ballerina.compiler.api.SemanticModel;
import io.ballerina.compiler.syntax.tree.ModuleMemberDeclarationNode;
import io.ballerina.compiler.syntax.tree.ModulePartNode;
import io.ballerina.compiler.syntax.tree.ServiceDeclarationNode;
import io.ballerina.compiler.syntax.tree.SyntaxKind;
import io.ballerina.compiler.syntax.tree.SyntaxTree;
import io.ballerina.openapi.service.mapper.model.OASGenerationMetaInfo;
import io.ballerina.openapi.service.mapper.model.OASResult;
import io.ballerina.projects.Document;
import io.ballerina.projects.DocumentId;
import io.ballerina.projects.Module;
import io.ballerina.projects.Package;
import io.ballerina.projects.Project;
import io.ballerina.projects.plugins.AnalysisTask;
import io.ballerina.projects.plugins.CompilationAnalysisContext;
import io.ballerina.tools.diagnostics.Diagnostic;
import io.ballerina.tools.diagnostics.DiagnosticFactory;
import io.ballerina.tools.diagnostics.DiagnosticInfo;
import io.ballerina.tools.diagnostics.DiagnosticSeverity;
import io.ballerina.tools.diagnostics.Location;
import io.ballerina.tools.text.LinePosition;
import io.ballerina.tools.text.LineRange;
import io.ballerina.tools.text.TextRange;
import io.swagger.v3.core.util.Json;
import io.swagger.v3.oas.models.OpenAPI;

import java.nio.charset.StandardCharsets;
import java.nio.file.Path;
import java.util.HashSet;
import java.util.Optional;
import java.util.Set;

import static io.ballerina.openapi.service.mapper.ServersMapper.getServiceBasePath;
import static io.ballerina.openapi.service.mapper.ServiceToOpenAPIMapper.generateOAS;
import static io.ballerina.openapi.service.mapper.utils.MapperCommonUtils.isHttpService;
import static io.ballerina.openapi.service.mapper.utils.MapperCommonUtils.normalizeTitle;

/**
 * Generates an OpenAPI definition for every HTTP service in the package and stores the resulting
 * bytes in {@code openApiDocs}, keyed by the resource path they should be written to inside the
 * JAR. Runs only when {@code remoteManagement = true} is set under {@code [build-options]}.
 */
public class SwaggerPackCollectTask implements AnalysisTask<CompilationAnalysisContext> {

    private final OpenApiDocumentStore openApiDocs;

    public SwaggerPackCollectTask(OpenApiDocumentStore openApiDocs) {
        this.openApiDocs = openApiDocs;
    }

    @Override
    public void perform(CompilationAnalysisContext ctx) {
        Package currentPackage = ctx.currentPackage();
        Project project = currentPackage.project();

        if (!project.buildOptions().remoteManagement()) {
            return;
        }
        if (containsErrors(ctx)) {
            return;
        }

        Set<String> usedFileNames = new HashSet<>();
        for (Module module : currentPackage.modules()) {
            SemanticModel semanticModel = ctx.compilation().getSemanticModel(module.moduleId());
            for (DocumentId documentId : module.documentIds()) {
                collectDocumentServices(ctx, project, module, module.document(documentId), semanticModel,
                        usedFileNames);
            }
        }
    }

    private void collectDocumentServices(CompilationAnalysisContext ctx, Project project, Module module,
                                          Document document, SemanticModel semanticModel,
                                          Set<String> usedFileNames) {
        SyntaxTree syntaxTree = document.syntaxTree();
        ModulePartNode modulePartNode = syntaxTree.rootNode();
        Path filePath = project.documentPath(document.documentId()).orElse(null);

        for (ModuleMemberDeclarationNode member : modulePartNode.members()) {
            if (member.kind() != SyntaxKind.SERVICE_DECLARATION) {
                continue;
            }
            ServiceDeclarationNode serviceNode = (ServiceDeclarationNode) member;
            if (!isHttpService(serviceNode, semanticModel)) {
                continue;
            }
            collectService(ctx, project, module, serviceNode, semanticModel, filePath, usedFileNames);
        }
    }

    private void collectService(CompilationAnalysisContext ctx, Project project, Module module,
                                 ServiceDeclarationNode serviceNode, SemanticModel semanticModel, Path filePath,
                                 Set<String> usedFileNames) {
        String basePath = getServiceBasePath(serviceNode);

        OASGenerationMetaInfo.OASGenerationMetaInfoBuilder builder =
                new OASGenerationMetaInfo.OASGenerationMetaInfoBuilder();
        builder.setServiceDeclarationNode(serviceNode)
                .setSemanticModel(semanticModel)
                .setOpenApiFileName(basePath)
                .setBallerinaFilePath(filePath);
        builder.setProject(project);
        OASResult oasResult = generateOAS(builder.build());

        boolean hasErrors = oasResult.getDiagnostics().stream()
                .anyMatch(d -> DiagnosticSeverity.ERROR.equals(d.getDiagnosticSeverity()));
        Optional<OpenAPI> openApiOpt = oasResult.getOpenAPI();
        if (hasErrors || openApiOpt.isEmpty()) {
            ctx.reportDiagnostic(warning(PluginConstants.SKIPPED_SERVICE_CODE,
                    "swagger-pack: unable to generate an OpenAPI definition for service "
                            + PluginConstants.escapeForDiagnostic(basePath) + ", skipping"));
            return;
        }

        OpenAPI openApi = openApiOpt.get();
        if (openApi.getInfo().getTitle() == null || "/".equals(openApi.getInfo().getTitle())) {
            openApi.getInfo().setTitle(normalizeTitle(basePath));
        }

        String fileName = uniqueFileName(module.moduleName().toString(), basePath, usedFileNames);
        String openApiJson = Json.pretty(openApi);
        openApiDocs.put(PluginConstants.SWAGGER_SUBDIR + "/" + fileName,
                openApiJson.getBytes(StandardCharsets.UTF_8));
    }

    private String uniqueFileName(String moduleName, String basePath, Set<String> usedFileNames) {
        String normalizedBasePath = basePath.isBlank() || "/".equals(basePath)
                ? "root" : basePath.replaceAll("^/+", "").replaceAll("[/{}]+", "_");
        String prefix = moduleName.isBlank() ? "" : moduleName + "_";
        String candidate = prefix + normalizedBasePath + PluginConstants.OPENAPI_FILE_SUFFIX;
        int suffix = 1;
        while (!usedFileNames.add(candidate)) {
            candidate = prefix + normalizedBasePath + "_" + suffix + PluginConstants.OPENAPI_FILE_SUFFIX;
            suffix++;
        }
        return candidate;
    }

    private boolean containsErrors(CompilationAnalysisContext ctx) {
        return ctx.compilation().diagnosticResult().diagnostics().stream()
                .anyMatch(d -> DiagnosticSeverity.ERROR.equals(d.diagnosticInfo().severity()));
    }

    private Diagnostic warning(String code, String message) {
        return DiagnosticFactory.createDiagnostic(
                new DiagnosticInfo(code, message, DiagnosticSeverity.WARNING), new NullLocation());
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
