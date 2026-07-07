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

import io.ballerina.runtime.api.Module;
import io.ballerina.runtime.api.creators.ValueCreator;
import io.ballerina.runtime.api.repository.Artifact;
import io.ballerina.runtime.api.types.ObjectType;
import io.ballerina.runtime.api.types.Type;
import io.ballerina.runtime.api.utils.StringUtils;
import io.ballerina.runtime.api.utils.TypeUtils;
import io.ballerina.runtime.api.values.BListInitialValueEntry;
import io.ballerina.runtime.api.values.BMap;
import io.ballerina.runtime.api.values.BObject;
import io.ballerina.runtime.api.values.BString;

import java.util.ArrayList;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Set;

import static io.ballerina.lib.wso2.icp.Artifacts.LISTENER_NAMES_MAP;
import static io.ballerina.lib.wso2.icp.Artifacts.LISTENER_STATES_MAP;
import static io.ballerina.lib.wso2.icp.Constants.BALLERINA;
import static io.ballerina.lib.wso2.icp.Constants.DISABLED;
import static io.ballerina.lib.wso2.icp.Constants.ENABLED;
import static io.ballerina.lib.wso2.icp.Constants.HOST;
import static io.ballerina.lib.wso2.icp.Constants.HTTP;
import static io.ballerina.lib.wso2.icp.Constants.HTTPS;
import static io.ballerina.lib.wso2.icp.Constants.HTTP_VERSION;
import static io.ballerina.lib.wso2.icp.Constants.INFERRED_CONFIG;
import static io.ballerina.lib.wso2.icp.Constants.LISTENER_DETAIL;
import static io.ballerina.lib.wso2.icp.Constants.NAME;
import static io.ballerina.lib.wso2.icp.Constants.PACKAGE;
import static io.ballerina.lib.wso2.icp.Constants.PORT;
import static io.ballerina.lib.wso2.icp.Constants.PROTOCOL;
import static io.ballerina.lib.wso2.icp.Constants.REQUEST_LIMIT;
import static io.ballerina.lib.wso2.icp.Constants.REQUEST_LIMITS;
import static io.ballerina.lib.wso2.icp.Constants.SECURE_SOCKET;
import static io.ballerina.lib.wso2.icp.Constants.STATE;
import static io.ballerina.lib.wso2.icp.Constants.TIMEOUT;
import static io.ballerina.lib.wso2.icp.Utils.getArtifact;

/**
 * Native function implementations of the wso2 control plane module.
 *
 * @since 1.0.0
 */
public class Listeners {
    public List<BListInitialValueEntry> getListenerList(Module currentModule) {
        List<BListInitialValueEntry> artifactEntries = new ArrayList<>();
        Set<BObject> listeners = getNonDuplicatedListeners(Artifacts.artifacts, currentModule);
        for (BObject listener : listeners) {
            artifactEntries.add(ValueCreator.createListInitialValueEntry(
                    getArtifact(LISTENER_NAMES_MAP.get(listener), currentModule)));
        }
        return artifactEntries;
    }

    private Set<BObject> getNonDuplicatedListeners(List<Artifact> artifacts, Module currentModule) {
        // LISTENER_NAMES_MAP is already populated by populateArtifactNamesMap() with only
        // user-facing listeners (internal wrapped listeners are excluded there). Derive
        // the list from the map so the two are always consistent.
        Set<BObject> listeners = new LinkedHashSet<>();
        for (Object key : LISTENER_NAMES_MAP.keySet()) {
            listeners.add((BObject) key);
        }
        return listeners;
    }

    public BMap<BString, Object> getDetailedListener(BObject listener, Module currentModule) {
        Type listenerType = TypeUtils.getImpliedType(listener.getOriginalType());
        io.ballerina.runtime.api.Module typePackage = listenerType.getPackage();

        BMap<BString, Object> listenerRecord = ValueCreator.createMapValue();
        listenerRecord.put(StringUtils.fromString(NAME), StringUtils.fromString(LISTENER_NAMES_MAP.get(listener)));
        listenerRecord.put(StringUtils.fromString(PACKAGE),
                StringUtils.fromString(listener.getOriginalType().getPackage().toString()));
        listenerRecord.put(StringUtils.fromString(STATE),
                StringUtils.fromString(LISTENER_STATES_MAP.getOrDefault(listener, true) ? ENABLED : DISABLED));

        if (BALLERINA.equals(typePackage.getOrg()) && "http".equals(typePackage.getName())) {
            listenerRecord.put(StringUtils.fromString(PROTOCOL), getListenerProtocol(listener));
            listenerRecord.put(StringUtils.fromString(PORT), listener.get(StringUtils.fromString(PORT)));
            BMap<BString, Object> config =
                    (BMap<BString, Object>) listener.get(StringUtils.fromString(INFERRED_CONFIG));
            listenerRecord.put(StringUtils.fromString(HTTP_VERSION),
                    StringUtils.fromString(config.get(StringUtils.fromString(HTTP_VERSION)).toString()));
            listenerRecord.put(StringUtils.fromString(HOST),
                    StringUtils.fromString(config.get(StringUtils.fromString(HOST)).toString()));
            listenerRecord.put(StringUtils.fromString(TIMEOUT), config.get(StringUtils.fromString(TIMEOUT)));
            listenerRecord.put(StringUtils.fromString(REQUEST_LIMITS), getRequestLimit(config, currentModule));
        } else {
            listenerRecord.put(StringUtils.fromString(PROTOCOL),
                    StringUtils.fromString(typePackage.getName()));
            // Non-HTTP listeners (e.g. graphql:Listener) typically do not declare a 'port'
            // field directly; the port is stored inside an inner http:Listener field.
            // Try direct field first, then fall back to scanning for a nested http:Listener.
            if (listenerType instanceof ObjectType objectType) {
                extractPort(listener, objectType, listenerRecord);
            }
        }

        return ValueCreator.createReadonlyRecordValue(currentModule, LISTENER_DETAIL, listenerRecord);
    }

    private static BMap<BString, Object> getRequestLimit(BMap<BString, Object> config, Module module) {
        return ValueCreator.createReadonlyRecordValue(module, REQUEST_LIMIT,
                (BMap<BString, Object>) config.getMapValue(StringUtils.fromString(REQUEST_LIMITS)));
    }

    private static BString getListenerProtocol(BObject listener) {
        BMap<BString, Object> config = (BMap<BString, Object>) listener.get(StringUtils.fromString(INFERRED_CONFIG));
        Object secureSocket = config.get(StringUtils.fromString(SECURE_SOCKET));
        return StringUtils.fromString(secureSocket == null ? HTTP : HTTPS);
    }

    // Returns the configured host of the first enabled HTTP listener in the runtime.
    // The Ballerina layer combines this with the workflow management port to build the
    // callback URL. Returns null when no HTTP listener is available.
    public BString getCallbackHost(Module currentModule) {
        Set<BObject> listeners = getNonDuplicatedListeners(Artifacts.artifacts, currentModule);
        for (BObject listener : listeners) {
            if (!Artifacts.LISTENER_STATES_MAP.getOrDefault(listener, true)) {
                continue;
            }
            Type listenerType = TypeUtils.getImpliedType(listener.getOriginalType());
            Module typePackage = listenerType.getPackage();
            if (!(BALLERINA.equals(typePackage.getOrg()) && "http".equals(typePackage.getName()))) {
                continue;
            }
            BMap<BString, Object> config =
                    (BMap<BString, Object>) listener.get(StringUtils.fromString(INFERRED_CONFIG));
            return StringUtils.fromString(config.get(StringUtils.fromString(HOST)).toString());
        }
        return null;
    }

    /**
     * Attempts to populate the PORT entry in {@code record} for a non-HTTP listener.
     * Checks for a direct 'port' field first; if absent, scans object fields for a nested
     * http:Listener and reads its port (covers graphql:Listener which stores the port in
     * an internal httpListener field).
     */
    private static void extractPort(BObject listener, ObjectType objectType,
                                    BMap<BString, Object> record) {
        if (objectType.getFields().containsKey(PORT)) {
            Object port = listener.get(StringUtils.fromString(PORT));
            if (port != null) {
                record.put(StringUtils.fromString(PORT), port);
            }
            return;
        }
        for (String fieldName : objectType.getFields().keySet()) {
            try {
                Object fv = listener.get(StringUtils.fromString(fieldName));
                if (!(fv instanceof BObject nested)) {
                    continue;
                }
                io.ballerina.runtime.api.Module nestedPkg =
                        TypeUtils.getImpliedType(nested.getOriginalType()).getPackage();
                if (nestedPkg == null || !BALLERINA.equals(nestedPkg.getOrg())
                        || !"http".equals(nestedPkg.getName())) {
                    continue;
                }
                Object port = nested.get(StringUtils.fromString(PORT));
                if (port != null) {
                    record.put(StringUtils.fromString(PORT), port);
                    return;
                }
            } catch (RuntimeException ignored) {
                // Field not accessible or not a BObject — skip.
            }
        }
    }

}
