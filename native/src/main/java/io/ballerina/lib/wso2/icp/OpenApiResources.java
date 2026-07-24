/*
 * Copyright (c) 2026, WSO2 LLC. (http://wso2.com).
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

package io.ballerina.lib.wso2.icp;

import io.ballerina.runtime.api.creators.TypeCreator;
import io.ballerina.runtime.api.creators.ValueCreator;
import io.ballerina.runtime.api.types.MapType;
import io.ballerina.runtime.api.types.PredefinedTypes;
import io.ballerina.runtime.api.utils.JsonUtils;
import io.ballerina.runtime.api.utils.StringUtils;
import io.ballerina.runtime.api.values.BArray;
import io.ballerina.runtime.api.values.BError;
import io.ballerina.runtime.api.values.BMap;
import io.ballerina.runtime.api.values.BString;

import java.io.IOException;
import java.io.InputStream;
import java.util.ArrayList;
import java.util.List;

/**
 * Reads the OpenAPI definitions packed into the running JAR by the swagger-pack compiler plugin
 * (see the {@code compiler-plugin} module). Only ever looks up fixed resource names — the index
 * file, then each name it lists — rather than scanning the JAR, so this stays compatible with
 * GraalVM native-image builds where resource access must be to known, registered names.
 */
public final class OpenApiResources {

    private static final String SWAGGER_DIR = "swagger/";
    private static final String INDEX_FILE = SWAGGER_DIR + "index.json";
    private static final MapType JSON_MAP_TYPE = TypeCreator.createMapType(PredefinedTypes.TYPE_JSON);

    private OpenApiResources() {
    }

    public static BMap<BString, Object> getPackedOpenApiDefinitions() {
        BMap<BString, Object> result = ValueCreator.createMapValue(JSON_MAP_TYPE);
        ClassLoader classLoader = OpenApiResources.class.getClassLoader();
        for (String fileName : readIndex(classLoader)) {
            Object definition = readJsonResource(classLoader, SWAGGER_DIR + fileName);
            if (definition != null) {
                result.put(StringUtils.fromString(fileName), definition);
            }
        }
        return result;
    }

    private static List<String> readIndex(ClassLoader classLoader) {
        Object parsed = readJsonResource(classLoader, INDEX_FILE);
        List<String> fileNames = new ArrayList<>();
        if (!(parsed instanceof BArray bArray)) {
            return fileNames;
        }
        for (long i = 0; i < bArray.getLength(); i++) {
            BString fileName = bArray.getBString(i);
            if (fileName != null) {
                fileNames.add(fileName.getValue());
            }
        }
        return fileNames;
    }

    private static Object readJsonResource(ClassLoader classLoader, String resourcePath) {
        try (InputStream inputStream = classLoader.getResourceAsStream(resourcePath)) {
            if (inputStream == null) {
                return null;
            }
            return JsonUtils.parse(inputStream);
        } catch (IOException | BError e) {
            return null;
        }
    }
}
