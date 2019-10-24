import ballerina/io;
import ballerina/log;
import ballerina/system;
import ballerina/time;
import ballerina/websub;

// TODO: set correct ones once decided
const JSON_TOPIC = "https://github.com/ECLK/Results-Dist-json";
const XML_TOPIC = "https://github.com/ECLK/Results-Dist-xml";
const TEXT_TOPIC = "https://github.com/ECLK/Results-Dist-text";
const IMAGE_TOPIC = "https://github.com/ECLK/Results-Dist-image";

const UNDERSOCRE = "_";
const COLON = ":";

const JSON_EXT = ".json";
const XML_EXT = ".xml";
const TEXT_EXT = ".txt";
const PDF_EXT = ".pdf";

const JSON_PATH = "/json";
const XML_PATH = "/xml";
const TEXT_PATH = "/txt";
const IMAGE_PATH = "/image";

const TWO_DAYS_IN_SECONDS = 172800;

string hub = "http://localhost:9090/websub/hub";
string subscriberSecret = "";

string subscriberPublicUrl = "";
int subscriberPort = 8080;
string subscriberDirectoryPath = "";

function getJsonSubscriber() returns service {
    return
    @websub:SubscriberServiceConfig {
        path: JSON_PATH,
        subscribeOnStartUp: true,
        target: [hub, JSON_TOPIC],
        leaseSeconds: TWO_DAYS_IN_SECONDS,
        secret: subscriberSecret,
        callback: getUrl(JSON_PATH)
    }
    service {
        resource function onNotification(websub:Notification notification) {
            json|error jsonPayload = notification.getJsonPayload();
            if (jsonPayload is json) {
                writeJson(subscriberDirectoryPath.concat(getFileName(JSON_EXT)), jsonPayload);
            } else {
                log:printError("Error extracting JSON payload", jsonPayload);
            }
        }
    };
}

function getXmlSubscriber() returns service {
    return
    @websub:SubscriberServiceConfig {
        path: XML_PATH,
        subscribeOnStartUp: true,
        target: [hub, XML_TOPIC],
        leaseSeconds: TWO_DAYS_IN_SECONDS,
        secret: subscriberSecret,
        callback: getUrl(XML_PATH)
    }
    service {
        resource function onNotification(websub:Notification notification) {
            xml|error xmlPayload = notification.getXmlPayload();
            if (xmlPayload is xml) {
                writeXml(subscriberDirectoryPath.concat(getFileName(XML_EXT)), xmlPayload);
            } else {
                log:printError("Error extracting XML payload", xmlPayload);
            }
        }
    };
}

function getTextSubscriber() returns service {
    return
    @websub:SubscriberServiceConfig {
        path: TEXT_PATH,
        subscribeOnStartUp: true,
        target: [hub, TEXT_TOPIC],
        leaseSeconds: TWO_DAYS_IN_SECONDS,
        secret: subscriberSecret,
        callback: getUrl(TEXT_PATH)
    }
    service {
        resource function onNotification(websub:Notification notification) {
            string|error textPayload = notification.getTextPayload();
            if (textPayload is string) {
                write(subscriberDirectoryPath.concat(getFileName(TEXT_EXT)), textPayload);
            } else {
                log:printError("Error extracting text payload", textPayload);
            }
        }
    };
}

function getImageSubscriber() returns service {
    return
    @websub:SubscriberServiceConfig {
        path: IMAGE_PATH,
        subscribeOnStartUp: true,
        target: [hub, IMAGE_TOPIC],
        leaseSeconds: TWO_DAYS_IN_SECONDS,
        secret: subscriberSecret,
        callback: getUrl(IMAGE_PATH)
    }
    service {
        resource function onNotification(websub:Notification notification) {
            byte[]|error binaryPayload = notification.getBinaryPayload();
            if (binaryPayload is byte[]) {
                write(subscriberDirectoryPath.concat(getFileName(PDF_EXT)), binaryPayload.toBase64());
            } else {
                log:printError("Error extracting image payload", binaryPayload);
            }
        }
    };
}

public function main(string secret, string publicUrl, string? hubUrl = (), boolean 'json = false, boolean 'xml = false,
                     boolean text = false, int port = 8080, string? certFile = (), string directoryPath = "") {
    subscriberSecret = <@untainted> secret;
    subscriberPublicUrl = <@untainted> publicUrl;
    subscriberPort = <@untainted> port;
    subscriberDirectoryPath = <@untainted> directoryPath;

    if (hubUrl is string) {
        hub = <@untainted> hubUrl;
    }

    websub:SubscriberListenerConfiguration config = {};
    if (certFile is string) {
        config.httpServiceSecureSocket = {
            certFile: certFile
        };
    }

    websub:Listener websubListener = new(subscriberPort, config);

    if ('json) {
        checkpanic websubListener.__attach(getJsonSubscriber());
    }

    if ('xml) {
        checkpanic websubListener.__attach(getXmlSubscriber());
    }

    if ('text) {
        checkpanic websubListener.__attach(getTextSubscriber());
    }

    checkpanic websubListener.__attach(getImageSubscriber());

    checkpanic websubListener.__start();
}

function getFileName(string ext) returns string {
    return time:currentTime().time.toString().concat(UNDERSOCRE, system:uuid(), ext);
}

function closeWcc(io:WritableCharacterChannel wc) {
    var result = wc.close();
    if (result is error) {
        log:printError("Error occurred while closing the character stream", result);
    }
}

function closeWbc(io:WritableByteChannel wc) {
    var result = wc.close();
    if (result is error) {
        log:printError("Error occurred while closing the byte stream", result);
    }
}

function writeJson(string path, json content) {
    writeContent(path, function(io:WritableCharacterChannel wch) returns error? {
        return wch.writeJson(content);
    });
}

function writeXml(string path, xml content) {
    writeContent(path, function(io:WritableCharacterChannel wch) returns error? {
        return wch.writeXml(content);
    });
}

function write(string path, string content) {
    writeContent(path, function(io:WritableCharacterChannel wch) returns int|error {
        return wch.write(content, 0);
    });
}

function writeContent(string path, function(io:WritableCharacterChannel wch) returns int|error? writeFunc) {
    io:WritableByteChannel|error wbc = io:openWritableFile(path);
    if (wbc is io:WritableByteChannel) {
        io:WritableCharacterChannel wch = new(wbc, "UTF8");
        var result = writeFunc(wch);
        if (result is error) {
            log:printError("Error writing content", result);
        } else {
            log:printInfo("Update written to " + path);
        }
        closeWcc(wch);
        closeWbc(wbc);
    } else {
        log:printError("Error creating a byte channel for " + path, wbc);
    }
}

function getUrl(string path) returns string {
    return subscriberPublicUrl.concat(path);
}
