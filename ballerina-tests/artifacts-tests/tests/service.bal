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

import ballerina/http;

type Album readonly & record {|
    string title;
    string artist;
|};

table<Album> key(title) albums = table [
    {title: "Blue Train", artist: "John Coltrane"},
    {title: "Jeru", artist: "Gerry Mulligan"}
];

service /hello on new http:Listener(testPort) {
    resource function get greeting() returns string {
        return "Hello, World!";
    }

    resource function get albums/[string title]/[string artist]/[string... tags]() returns Album[]|http:NotFound {
        Album[] filtered = from Album album in albums
            where album.title == title && album.artist == artist
            select album;

        if filtered.length() == 0 {
            return http:NOT_FOUND;
        }
        return filtered;
    }
}
