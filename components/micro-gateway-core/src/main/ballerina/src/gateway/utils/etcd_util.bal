// Copyright (c) 2019, WSO2 Inc. (http://www.wso2.org) All Rights Reserved.
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

import ballerina/config;
import ballerina/http;
import ballerina/io;
import ballerina/task;

map<string> etcdUrls = {};
map<any> urlChanged = {};
map<string> defaultUrls = {};
string etcdToken = "";
boolean etcdPeriodicQueryInitialized = false;
boolean etcdConnectionEstablished = false;
boolean etcdConnectionAttempted = false;
boolean credentialsProvided = false;
boolean etcdAuthenticationEnabled = true;
string etcdBasePath = getConfigValue("", "etcdbasepath", "/v3");
string etcdKVBasePath = etcdBasePath + "/kv";
string etcdAuthBasePath = etcdBasePath + "/auth";
int etcdTriggerTime = config:getAsInt("etcdtimer", DEFAULT_ETCD_TRIGGER_TIME);
task:TimerConfiguration timerConfiguration = {
    intervalInMillis: etcdTriggerTime,
    initialDelayInMillis: 1000
};
task:Scheduler timer = new (timerConfiguration);

# Setting up etcd timer task
public function initiateEtcdTimerTask() {
    printDebug(KEY_ETCD_UTIL, "initiateEtcdTimerTask Called");
    int etcdTriggerTime = config:getAsInt("etcdtimer", DEFAULT_ETCD_TRIGGER_TIME);
    string | error trigTime = etcdTriggerTime.toString();
    // The Task Timer configuration record to configure the Task Listener.

    var searchResult = timer.attach(etcdService);
    if (searchResult is error) {
        printError(KEY_ETCD_UTIL, searchResult.toString());
    }
    var startResult = timer.start();
    if (startResult is error) {
        printError(KEY_ETCD_UTIL, "Starting the etcd service task is failed.");
    }
    if (trigTime is string) {
        printInfo(KEY_ETCD_UTIL, "Etcd periodic timer task started with a periodic time of " + trigTime + "ms");
    }
}

// Creating a service on the task Listener.
service etcdService = service {
    resource function onTrigger() {
        error? onTriggerFunction = etcdTimerTask();
        if (onTriggerFunction is error) {
            printError(KEY_ETCD_UTIL, "Error occured while triggering etcd timer task " + onTriggerFunction.toString());
        }
    }
};

# Periodic Etcd Query. Trigger function of etcd timer task
# + return - ....
public function etcdTimerTask() returns error? {
    printDebug(KEY_ETCD_UTIL, "Etcd Periodic Query Initiated");
    if (etcdUrls.length() > 0) {
        printDebug(KEY_ETCD_UTIL, "etcdurl map values - start");
        foreach var [key, value] in etcdUrls.entries() {
            string currentUrl = <string>value;
            string fetchedUrl = etcdLookup(<string>key);
            if (currentUrl != fetchedUrl) {
                etcdUrls[<string>key] = <@untainted> fetchedUrl;
                urlChanged[<string>key] = true;
            }
            printDebug(KEY_ETCD_UTIL, key + " : " + <string>etcdUrls[<string>key]);
        }
        printDebug(KEY_ETCD_UTIL, "etcdurl map values - end");
    } else {
        printInfo(KEY_ETCD_UTIL, "No Etcd keys provided. Stopping etcd periodic call");
        var stopResult = timer.stop();
        if (stopResult is error) {
            printError(KEY_ETCD_UTIL, "Error while stopping the etcd periodic timer task");
        }

    }
    return ();
}

# Setting up etcd requirements
# + key - endpoint override key ex : Pizaashack_http_endpoint_0
# + etcdConfigKey - etcdKey taken as runtime paramate ex: value returned by - Pizaashack_http_0_etcdKey
# + defaultUrl - endpoint url mentioned in the open API ex: etcd(pizza, "http://test.com") -> http://test.com
# + defaultEtcdKey - etcd key from open API ex: etcd(pizza, "http://test.com") -> pizza
# + return - Endpoint url of the given API resource
public function etcdSetup(string key, string etcdConfigKey, string defaultUrl, string defaultEtcdKey) returns string {
    string endpointUrl;

    if (!etcdConnectionAttempted) {
        establishEtcdConnection();
        etcdConnectionAttempted = true;
        printDebug(KEY_ETCD_UTIL, "Etcd Connection Attempted");
    }
    printDebug(KEY_ETCD_UTIL, "Endpoint override key : " + key);
    printDebug(KEY_ETCD_UTIL, "ETCD config key provided from runtime : " + etcdConfigKey);
    printDebug(KEY_ETCD_UTIL, "Default url from the open API : " + defaultUrl);
    printDebug(KEY_ETCD_UTIL, "ETCD key from the open API : " + defaultEtcdKey);
    if (etcdConnectionEstablished) {
        if (!etcdPeriodicQueryInitialized) {
            etcdPeriodicQueryInitialized = true;
            initiateEtcdTimerTask();
        }
        string etcdKey = config:getAsString(etcdConfigKey, "");
        if (etcdKey == "") {
            config:setConfig(etcdConfigKey, defaultEtcdKey);
            etcdKey = defaultEtcdKey;
        }
        if (etcdKey == "") {
            printInfo(KEY_ETCD_UTIL, "Etcd Key not provided for: " + key);
            endpointUrl = config:getAsString(key, defaultUrl);
        } else {
            printDebug(KEY_ETCD_UTIL, "Etcd Key provided for: " + key);
            defaultUrls[etcdKey] = config:getAsString(key, defaultUrl);
            urlChanged[etcdKey] = false;
            etcdUrls[etcdKey] = <@untainted>etcdLookup(etcdKey);
            endpointUrl = <string>etcdUrls[etcdKey];
        }
    } else {
        endpointUrl = config:getAsString(key, defaultUrl);
    }
    printDebug(KEY_ETCD_UTIL, "Resolved endpoint url : " + endpointUrl);
    return endpointUrl;
}

# Establish etcd connection by authenticating etcd
public function establishEtcdConnection() {
    printDebug(KEY_ETCD_UTIL, "Establishing Etcd Connection");
    string etcdurl = config:getAsString("etcdurl", "");
    if (etcdurl != "") {
        printDebug(KEY_ETCD_UTIL, "etcdurl CLI parameter has been provided");
        etcdAuthenticate();
    } else {
        printError(KEY_ETCD_UTIL, "etcdurl CLI parameter has not been provided");
        etcdConnectionEstablished = false;
    }
}

# Query etcd passing the key and retrieves value
# + base10EncodedKey - encoded etcd key
# +return - endpoint url retrived from etcd server
public function etcdLookup(string base10EncodedKey) returns @tainted string {
    string base64EncodedKey;
    string base64EncodedValue = "";
    string endpointUrl;
    http:Request req = new;
    boolean valueNotFound = false;

    base64EncodedKey = base10EncodedKey.toBytes().toBase64();
    req.setPayload({"key": <@untainted>base64EncodedKey});

    if (etcdAuthenticationEnabled) {
        printDebug(KEY_ETCD_UTIL, "Setting authorization header for etcd requests");
        etcdAuthenticate();
        req.setHeader("Authorization", etcdToken);
    }

    var response = etcdEndpoint->post(etcdKVBasePath + "/range", req);
    if (response is http:Response) {
        printDebug(KEY_ETCD_UTIL, "Http Response object obtained");
        var msg = response.getJsonPayload();
        if (msg is json) {
            printDebug(KEY_ETCD_UTIL, "Etcd lookup response : " + msg.toJsonString());
            //map<json>|error message = map<json>.constructFrom(msg);
            if (msg is map<json>) {
                printDebug(KEY_ETCD_UTIL, "etcd responded with a payload");
                //json value = msg["kvs"][0].value;
                var kvsArray = msg["kvs"];
                if (kvsArray is json[]) {
                    json[] val = <json[]>msg["kvs"];
                    json value = val[0];
                    if (value is map<json>) {
                        base64EncodedValue = value["value"].toString();
                    } else {
                        printError("No availale endpoint for the provided etcd key : '" + base10EncodedKey + "'.", "");
                        valueNotFound = true;
                    }
                } else {
                    printError("ETCD server does not have a key : '" + base10EncodedKey + "'.", "");
                    valueNotFound = true;
                }
            }
        } else {
            printError(KEY_ETCD_UTIL, msg.reason());
        }
    } else {
        printDebug(KEY_ETCD_UTIL, "Error object obtained");
        valueNotFound = true;
        printError(KEY_ETCD_UTIL, response.reason());
    }

    if (valueNotFound) {
        printDebug(KEY_ETCD_UTIL, "value not found at etcd");
        endpointUrl = <string>defaultUrls[base10EncodedKey];
    } else {
        printDebug(KEY_ETCD_UTIL, "value found at etcd");
        endpointUrl = decodeValueToBase10(base64EncodedValue);
    }
    return endpointUrl;
}

# Authenticate etcd by providing username and password and retrieve etcd token
public function etcdAuthenticate() {
    printDebug(KEY_ETCD_UTIL, "Authenticating Etcd");
    http:Request req = new;
    string username = config:getAsString("etcdusername", "");
    string password = config:getAsString("etcdpassword", "");

    if (username == "" && password == "") {
        printDebug(KEY_ETCD_UTIL, "etcdusername and etcdpassword CLI parameters has not been provided");
        credentialsProvided = false;
    } else {
        printDebug(KEY_ETCD_UTIL, "both or one of etcdusername and etcdpassword CLI parameters have been provided");
        credentialsProvided = true;
    }
    req.setPayload({"name": <@untainted>username, "password": <@untainted>password});

    var response = etcdEndpoint->post(etcdAuthBasePath + "/authenticate", req);
    if (response is http:Response) {
        printDebug(KEY_ETCD_UTIL, "Http Response object obtained");
        io:println(response.getTextPayload());
        json | error msg = response.getJsonPayload();
        if (msg is json) {
            map<json> | error payload = map<json>.constructFrom(msg);
            if (payload is map<json>) {
                if (payload["token"] != null) {
                    printDebug(KEY_ETCD_UTIL, "etcd has responded with a token");
                    string | error token = <string>payload["token"];
                    if (token is string) {
                        etcdToken = <@untainted>token;
                        etcdConnectionEstablished = true;
                        printInfo(KEY_ETCD_UTIL, "Etcd Authentication Successful");
                    } else {
                        etcdConnectionEstablished = false;
                        printError(KEY_ETCD_UTIL, token.reason());
                    }
                }
                if (payload["error"] != null) {
                    printDebug(KEY_ETCD_UTIL, "etcd has responded with an error");
                    string | error authenticationError = <string>payload["error"];
                    if (authenticationError is string) {
                        if (contains(authenticationError, "authentication is not enabled")) {
                            printDebug(KEY_ETCD_UTIL, "etcd authentication is not enabled");
                            etcdAuthenticationEnabled = false;
                            etcdConnectionEstablished = true;
                            if (credentialsProvided) {
                                printInfo(KEY_ETCD_UTIL, authenticationError);
                            }
                        }
                        if (contains(authenticationError, "authentication failed, invalid user ID or password")) {
                            etcdConnectionEstablished = false;
                            printError(KEY_ETCD_UTIL, authenticationError);
                        }
                    } else {
                        etcdConnectionEstablished = false;
                        printError(KEY_ETCD_UTIL, authenticationError.reason());
                    }
                }
            } else {
                etcdConnectionEstablished = false;
                printError(KEY_ETCD_UTIL, payload.toString());
            }
        } else {
            etcdConnectionEstablished = false;
            printError(KEY_ETCD_UTIL, msg.reason());
        }
    } else {
        printDebug(KEY_ETCD_UTIL, "Error object obtained");
        etcdConnectionEstablished = false;
        printError(KEY_ETCD_UTIL, response.reason());
    }
}

public function isEtcdConnectionEstablished() returns boolean {
    return etcdConnectionEstablished;
}

public function getUrlChangedMap() returns map<any> {
    return urlChanged;
}

public function getEtcdUrlsMap() returns map<string> {
    return etcdUrls;
}
