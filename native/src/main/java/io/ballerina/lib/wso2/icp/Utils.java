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

import io.ballerina.runtime.api.Environment;
import io.ballerina.runtime.api.Module;
import io.ballerina.runtime.api.creators.ValueCreator;
import io.ballerina.runtime.api.repository.Node;
import io.ballerina.runtime.api.types.ObjectType;
import io.ballerina.runtime.api.types.Type;
import io.ballerina.runtime.api.utils.StringUtils;
import io.ballerina.runtime.api.utils.TypeUtils;
import io.ballerina.runtime.api.values.BMap;
import io.ballerina.runtime.api.values.BObject;
import io.ballerina.runtime.api.values.BString;

import java.util.Set;

import static io.ballerina.lib.wso2.icp.Constants.ARTIFACT;
import static io.ballerina.lib.wso2.icp.Constants.BALLERINA_HOME;
import static io.ballerina.lib.wso2.icp.Constants.BAL_HOME;
import static io.ballerina.lib.wso2.icp.Constants.BAL_VERSION;
import static io.ballerina.lib.wso2.icp.Constants.NAME;
import static io.ballerina.lib.wso2.icp.Constants.NODE;
import static io.ballerina.lib.wso2.icp.Constants.OS_NAME;
import static io.ballerina.lib.wso2.icp.Constants.OS_VERSION;
import static io.ballerina.lib.wso2.icp.Constants.PLATFORM_VERSION;

/**
 * Native function implementations of the wso2 control plane module.
 *
 * @since 1.0.0
 */
public class Utils {

    public static Object getBallerinaNode(Environment env) {
        Module currentModule = env.getCurrentModule();
        Node node = env.getRepository().getNode();
        BMap<BString, Object> nodeEntries = ValueCreator.createMapValue();
        nodeEntries.put(StringUtils.fromString(PLATFORM_VERSION),
                StringUtils.fromString(getBallerinaVersionString((String) node.getDetail(BAL_VERSION))));
        nodeEntries.put(StringUtils.fromString(BALLERINA_HOME),
                StringUtils.fromString((String) node.getDetail(BAL_HOME)));
        nodeEntries.put(StringUtils.fromString(Constants.OS_NAME),
                StringUtils.fromString((String) node.getDetail(OS_NAME)));
        nodeEntries.put(StringUtils.fromString(OS_VERSION),
                StringUtils.fromString((String) node.getDetail(OS_VERSION)));
        return ValueCreator.createReadonlyRecordValue(currentModule, NODE, nodeEntries);
    }

    private static String getBallerinaVersionString(String detail) {
        String version = detail.split("-")[0];
        int minorVersion = Integer.parseInt(version.split("\\.")[1]);
        String updateVersionText = minorVersion > 0 ? " Update " + minorVersion : "";
        return "Ballerina " + version + " (Swan Lake Update " + updateVersionText + ")";
    }

    public static boolean isicpService(BObject serviceObj, Module currentModule) {
        Type originalType = serviceObj.getOriginalType();
        Module module = originalType.getPackage();
        return module != null && module.equals(currentModule);
    }

    /**
     * Returns true when a service object is an internal adapter created by a stdlib listener
     * (e.g. the HTTP service wrapper that graphql:Listener registers internally).
     * Such services come from ballerina/* or ballerinax/* packages and are not user-defined.
     */
    public static boolean isInternalAdapterService(BObject serviceObj) {
        Type originalType = serviceObj.getOriginalType();
        Module module = originalType.getPackage();
        if (module == null) {
            return false;
        }
        String org = module.getOrg();
        return Constants.BALLERINA.equals(org) || "ballerinax".equals(org);
    }

    /**
     * Returns true when {@code candidate} is stored as a direct object field of
     * {@code container}. This is the primitive used to detect wrapper relationships
     * between listeners (e.g. the http:Listener field inside a graphql:Listener).
     */
    public static boolean isFieldOf(BObject candidate, BObject container) {
        Type containerType = TypeUtils.getImpliedType(container.getOriginalType());
        if (!(containerType instanceof ObjectType objectType)) {
            return false;
        }
        for (String fieldName : objectType.getFields().keySet()) {
            try {
                if (candidate == container.get(StringUtils.fromString(fieldName))) {
                    return true;
                }
            } catch (RuntimeException ignored) {
                // Field not accessible or not a matching type — continue.
            }
        }
        return false;
    }

    /**
     * Returns true when {@code candidate} is stored as an object field of any other
     * listener in {@code allListeners}. This identifies listeners that are internal
     * implementations of a higher-level listener (e.g. the http:Listener inside a
     * graphql:Listener) so they can be excluded from the user-visible list.
     */
    public static boolean isWrappedByAnotherListener(BObject candidate, Set<BObject> allListeners) {
        for (BObject other : allListeners) {
            if (other != candidate && isFieldOf(candidate, other)) {
                return true;
            }
        }
        return false;
    }

    public static BMap<BString, Object> getArtifact(String name, Module module) {
        BMap<BString, Object> artifact = ValueCreator.createMapValue();
        artifact.put(StringUtils.fromString(NAME), StringUtils.fromString(name));
        return ValueCreator.createReadonlyRecordValue(module, ARTIFACT, artifact);
    }

}
