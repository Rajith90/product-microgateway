// Copyright (c) 2019 WSO2 Inc. (http://www.wso2.org) All Rights Reserved.
//
// WSO2 Inc. licenses this file to you under the Apache License,
// Version 2.0 (the "License"); you may not use this file except
// in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing,
// software distributed under the License is distributed on an
// "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
// KIND, either express or implied.  See the License for the
// specific language governing permissions and limitations
// under the License.

import ballerina/http;

# The HTTP client provides the capability for initiating contact with a remote HTTP service. This client is
# wrapper for ballerina http client object

# + clientName - The variable name of the http gateway client
# + url - Address endpoint of the client
# + config - The configurations associated with the client
# + httpClient - Ballerina HTTP client object
public type Client object {

    public string clientName;
    public string url;
    public http:ClientEndpointConfig config = {};
    public http:Client httpClient;

    # Gets invoked to initialize the client. During initialization, configurations provided through the `config`
    # record is used to determine which type of additional behaviours are added to the endpoint (e.g: caching,
    # security, proxy configs).
    #
    # + clientName - The variable name of the http gateway client
    # + url - URL of the target service
    # + config - The configurations to be used when initializing the client
    public function __init(string clientName, string url, http:ClientEndpointConfig? config = ()) {
        self.clientName = clientName;
        self.url = url;
        self.httpClient = new(url, config = config);
        addClientToMap(self.clientName, self);
    }

    public function forward(string path, http:Request request) returns http:Response|error {
        return self.httpClient->forward(path, request);
    }

};