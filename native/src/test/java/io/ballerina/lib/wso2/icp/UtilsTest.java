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

import org.testng.Assert;
import org.testng.annotations.DataProvider;
import org.testng.annotations.Test;

/**
 * Tests for the platform version string reported to ICP.
 */
public class UtilsTest {

    @DataProvider(name = "ballerinaVersions")
    public Object[][] ballerinaVersions() {
        return new Object[][]{
                {"2201.14.0", "Ballerina 2201.14.0 (Swan Lake Update 14)"},
                {"2201.13.4", "Ballerina 2201.13.4 (Swan Lake Update 13)"},
                {"2201.0.4", "Ballerina 2201.0.4 (Swan Lake)"},
                {"2201.14.0-20260928-172300-09cbe60d", "Ballerina 2201.14.0 (Swan Lake Update 14)"},
                {"2201.13.0-alpha", "Ballerina 2201.13.0 (Swan Lake Update 13)"}
        };
    }

    @Test(dataProvider = "ballerinaVersions")
    public void testGetBallerinaVersionString(String balVersion, String expected) {
        Assert.assertEquals(Utils.getBallerinaVersionString(balVersion), expected);
    }
}
