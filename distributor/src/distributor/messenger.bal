 import ballerina/config;
 import ballerina/log;
 import ballerina/stringutils;
 import chamil/govsms;

govsms:Configuration govsmsConfig = {
     username: config:getAsString("eclk.govsms.username"),
     password: config:getAsString("eclk.govsms.password")
};

govsms:Client smsClient = new (govsmsConfig);

// Keeps registered sms recipients in-memory. Values are populated in every service init and recipient registration
map<string> mobileSubscribers = {};
string sourceDepartment = config:getAsString("eclk.govsms.source");
boolean validSmsClient = false;

function getAwaitResultsMessage(string electionCode, string resultType, string resultCode, string level, 
                                string? ed_name, string? pd_name) returns string {
    string message;

    match level {
        LEVEL_PD => {
            string electoralDistrict = "/" + (ed_name ?: "<unknown electoral district>");
            string pollingDivision = "/" + (pd_name ?: "<unknown polling division>");

            string pdLevelName = "";
            if (resultCode.endsWith("PV") {
                pdLevelName = "POSTAL";
            } else if (resultCode.endsWith("DV") {
                pdLevelName = "DISPLACED";
            } else if (resultCode.endsWith("QV") {
                pdLevelName = "QUARANTINE";
            } else {
                pdLevelName = "POLLING-DIVISION";
            }
            message  = "Await " + pdLevelName + " results for " + electionCode + resultType +
                            electoralDistrict + pollingDivision;
        }
        LEVEL_ED => {
            string electoralDistrict = "/" + (ed_name ?: "<unknown electoral district>");

            message  = "Await ELECTORAL-DISTRICT results for " + electionCode + resultType + electoralDistrict;
        }
        LEVEL_NF => {
            message  = "Await NATIONAL-FINAL results for " + electionCode + resultType;
        }
        _ => {
            message  = "Await results for " + electionCode + resultType + "/" + resultCode;
        }
    }

    return message + "(" + resultCode + ")";
}

# Send SMS notification to all the subscribers.
#
# + message - The message to send
# + resultId - The message identification
function sendSMS(string message, string resultId) {
    if (mobileSubscribers.length() == 0) {
        return;
    }
    string logMessage = "Sending SMS for " + resultId;
    log:printInfo(logMessage);
    foreach string targetMobile in mobileSubscribers {
        log:printInfo(logMessage + " to " + targetMobile);
        var response = smsClient->sendSms(sourceDepartment, message, targetMobile);
        if response is error {
            log:printError("Message sending failed for \'" + targetMobile + "\'", response);
        }
    }
}

# Validate and sanitize local mobile number into the proper format.(0771234567).
#
# + mobileNo - User provided mobile number
# + return - Formatted mobile number or the error
function validate(string mobileNo) returns string|error {
    string mobile = <@untained> mobileNo.trim();

    if (mobile.startsWith("+94") && mobile.length() == 12) {
        mobile = mobile.substring(1);
    }

    boolean number = stringutils:matches(mobile, "^[0-9]*$");
    if !number {
        return error(ERROR_REASON, message = "Invalid mobile number. Given mobile number contains non numeric " +
                                           "characters: " + mobile);
    }

    if (mobile.startsWith("0") && mobile.length() == 10) {
        return mobile;
    }
    if (mobile.startsWith("94") && mobile.length() == 11) {
        return mobile;
    }
    // Allow only the local mobile numbers to register via public API. International number are avoided.
    return error(ERROR_REASON, message = "Invalid mobile number. Resend the request as follows: If the " +
                                     "mobile no is 0771234567, send POST request to  \'/sms\' with JSON payload " +
                                     "\'{\"username\":\"myuser\", \"mobile\":\"0771234567\"}\'");
}

# Register recipient in the mobileSubscribers list and persist in the smsRecipients db table.
#
# + username - The recipient username
# + mobileNo - The recipient number
# + return - The status of registration or operation error
function registerAsSMSRecipient(string username, string mobileNo) returns string|error {

    if mobileSubscribers.hasKey(username) {
        string errMsg = "Registration failed: username:" + username + " is already registered with mobile:" + mobileNo;
        log:printError(errMsg);
        return error(ERROR_REASON, message = errMsg);
    }

    // Persist recipient number in database
    var status = dbClient->update(INSERT_RECIPIENT, username, mobileNo);
    if status is error {
        log:printError("Failed to persist recipient no in database", status);
        return error(ERROR_REASON, message = "Registration failed: username:" + username + " mobile:" + mobileNo
                                         + ": " + <string> status.detail()?.message);
    }
    mobileSubscribers[username] = mobileNo;

    return "Successfully registered: username:" + username + " mobile:"  + mobileNo;
}

# Unregister recipient from the mobileSubscribers map and remove from the smsRecipients db table.
#
# + username - The recipient username
# + mobileNo - The recipient number
# + return - The status of deregistration or operation error
function unregisterAsSMSRecipient(string username, string mobileNo) returns string|error {
    string result = "";
    if mobileSubscribers.hasKey(username) && mobileSubscribers.get(username) == mobileNo {
        result = "Successfully unregistered: username:" + username + " mobile:" + mobileSubscribers.remove(username);
    } else {
        string errMsg = "Unregistration failed: No entry found for username:" + username + " mobile:"  + mobileNo;
        log:printError(errMsg);
        return error(ERROR_REASON, message = errMsg);
    }

    // Remove persisted recipient number from database
    var status = dbClient->update(DELETE_RECIPIENT, username);
    if status is error {
        log:printError("Failed to remove recipient from the database", status);
        return error(ERROR_REASON, message = "Failed to remove from the database: username:" + username + " mobile:"
                     + mobileNo + ": " + <string> status.detail()?.message);
    }
    return result;
}
