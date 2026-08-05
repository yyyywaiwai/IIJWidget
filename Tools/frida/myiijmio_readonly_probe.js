'use strict';

// Reuses the official app's in-process authorization header to inspect only
// read-only MyIIJmio endpoints. Credential/token values and response values are
// never printed; output contains endpoint names, status codes, and JSON shapes.

const PREFIX = '[IIJ-PROBE]';
const retainedBlocks = new Set();
let probeStarted = false;

function emit(event, fields) {
    console.log(PREFIX + ' ' + JSON.stringify(Object.assign({
        event: event,
        timestamp: new Date().toISOString()
    }, fields || {})));
}

function shapeValue(value, depth) {
    if (depth > 10) {
        return '<max-depth>';
    }
    if (value === null) {
        return null;
    }
    if (Array.isArray(value)) {
        if (value.length === 0) {
            return [];
        }
        return [shapeValue(value[0], depth + 1), '<count:' + value.length + '>'];
    }

    const type = typeof value;
    if (type === 'object') {
        const output = {};
        Object.keys(value).sort().forEach(function (key) {
            output[key] = shapeValue(value[key], depth + 1);
        });
        return output;
    }
    if (type === 'string') {
        return '<string:' + value.length + '>';
    }
    if (type === 'number') {
        return '<number>';
    }
    if (type === 'boolean') {
        return '<boolean>';
    }
    return '<' + type + '>';
}

function stringFromData(dataPointer) {
    if (!dataPointer || dataPointer.isNull()) {
        return null;
    }
    const data = new ObjC.Object(dataPointer);
    const string = ObjC.classes.NSString.alloc().initWithData_encoding_(data, 4);
    return string ? string.toString() : null;
}

function headerValue(headers, targetName) {
    if (!headers || headers.isNull()) {
        return null;
    }
    const keys = headers.allKeys();
    for (let index = 0; index < Number(keys.count()); index += 1) {
        const key = keys.objectAtIndex_(index);
        if (key.toString().toLowerCase() === targetName.toLowerCase()) {
            return headers.objectForKey_(key).toString();
        }
    }
    return null;
}

function currentRequest(taskPointer) {
    try {
        const task = new ObjC.Object(taskPointer);
        const selector = ObjC.selector('currentRequest');
        if (!task.respondsToSelector_(selector)) {
            return null;
        }
        const request = task.currentRequest();
        return request && !request.isNull() ? request : null;
    } catch (_) {
        return null;
    }
}

function queryString(parameters) {
    return Object.keys(parameters || {})
        .filter(function (key) {
            return parameters[key] !== null && parameters[key] !== undefined && parameters[key] !== '';
        })
        .map(function (key) {
            return encodeURIComponent(key) + '=' + encodeURIComponent(String(parameters[key]));
        })
        .join('&');
}

function requestJSON(authorization, endpoint, parameters, forceUpdate) {
    return new Promise(function (resolve) {
        const query = queryString(parameters);
        const urlString = 'https://gapi.iijmio.jp' + endpoint + (query ? '?' + query : '');
        const url = ObjC.classes.NSURL.URLWithString_(urlString);
        const request = ObjC.classes.NSMutableURLRequest.requestWithURL_(url).mutableCopy();
        request.setHTTPMethod_('GET');
        request.setTimeoutInterval_(45);
        request.setValue_forHTTPHeaderField_('application/json', 'Accept');
        request.setValue_forHTTPHeaderField_('application/json', 'Content-Type');
        request.setValue_forHTTPHeaderField_('utf-8', 'charset');
        request.setValue_forHTTPHeaderField_('no-store', 'Cache-Control');
        request.setValue_forHTTPHeaderField_(authorization, 'Authorization');
        request.setValue_forHTTPHeaderField_('45000', 'timeout');
        if (forceUpdate) {
            request.setValue_forHTTPHeaderField_('1', 'ForceUpdate');
        }

        const block = new ObjC.Block({
            retType: 'void',
            argTypes: ['object', 'object', 'object'],
            implementation: function (data, response, error) {
                retainedBlocks.delete(block);
                let statusCode = null;
                if (response && !response.isNull()) {
                    const responseObject = new ObjC.Object(response);
                    if (responseObject.respondsToSelector_(ObjC.selector('statusCode'))) {
                        statusCode = Number(responseObject.statusCode());
                    }
                }

                let json = null;
                let parseError = null;
                try {
                    const text = stringFromData(data);
                    if (text !== null) {
                        json = JSON.parse(text);
                    }
                } catch (caught) {
                    parseError = caught.message;
                }

                emit('response', {
                    endpoint: endpoint,
                    parameterNames: Object.keys(parameters || {}).sort(),
                    statusCode: statusCode,
                    shape: json === null ? null : shapeValue(json, 0),
                    parseError: parseError,
                    networkError: error && !error.isNull() ? true : null
                });
                resolve({ statusCode: statusCode, json: json });
            }
        });
        retainedBlocks.add(block);
        ObjC.classes.NSURLSession.sharedSession()
            .dataTaskWithRequest_completionHandler_(request, block)
            .resume();
    });
}

function firstLine(lineInfoResponse) {
    const lineInfo = lineInfoResponse && lineInfoResponse.lineInfo;
    if (!lineInfo) {
        return null;
    }
    const candidates = []
        .concat(lineInfo.hdcList || [])
        .concat(lineInfo.hddList || []);
    if (candidates.length === 0) {
        return null;
    }
    return {
        serviceCode: candidates[0].serviceCode || null,
        lineServiceCode: candidates[0].lineServiceCode || null
    };
}

function firstTrafficLine(dataTrafficResponse) {
    const dataTraffic = dataTrafficResponse && dataTrafficResponse.dataTraffic;
    if (!dataTraffic) {
        return null;
    }

    const hdc = dataTraffic.hdcList || [];
    if (hdc.length > 0) {
        return {
            serviceCode: hdc[0].serviceCode || null,
            lineServiceCode: null
        };
    }

    const grouped = []
        .concat(dataTraffic.hddList || [])
        .concat(dataTraffic.mainHdd || []);
    for (let index = 0; index < grouped.length; index += 1) {
        const group = grouped[index];
        const lines = group.lineServiceCodeList || [];
        if (lines.length > 0) {
            return {
                serviceCode: group.serviceCode || lines[0].serviceCode || null,
                lineServiceCode: lines[0].lineServiceCode || null
            };
        }
    }
    return null;
}

async function runReadOnlyProbes(authorization) {
    emit('started', {
        endpoints: ['/lineInfo', '/contract', '/usageFee', '/dataTraffic', '/pastDataTraffic']
    });

    const lineInfo = await requestJSON(authorization, '/lineInfo', {}, true);
    await requestJSON(authorization, '/contract', {}, false);
    await requestJSON(authorization, '/usageFee', {}, false);

    const line = firstLine(lineInfo.json);
    const trafficParameters = { dataDetailFlag: 0 };
    if (line && line.lineServiceCode) {
        trafficParameters.mainLineServiceCode = line.lineServiceCode;
    }
    const dataTraffic = await requestJSON(authorization, '/dataTraffic', trafficParameters, false);

    const trafficLine = firstTrafficLine(dataTraffic.json) || line;
    if (trafficLine && trafficLine.serviceCode) {
        await requestJSON(authorization, '/pastDataTraffic', {
            serviceCode: trafficLine.serviceCode,
            lineServiceCode: trafficLine.lineServiceCode
        }, false);
    } else {
        emit('skipped', { endpoint: '/pastDataTraffic', reason: 'no-line-identifier' });
    }

    emit('completed');
}

if (!ObjC.available) {
    emit('fatal', { reason: 'Objective-C runtime is unavailable' });
} else {
    const resume = ObjC.classes.NSURLSessionTask['- resume'];
    Interceptor.attach(resume.implementation, {
        onEnter: function (args) {
            if (probeStarted) {
                return;
            }

            const request = currentRequest(args[0]);
            if (!request) {
                return;
            }
            const url = request.URL();
            if (!url || !url.host() || url.host().toString() !== 'gapi.iijmio.jp') {
                return;
            }

            const headers = request.allHTTPHeaderFields();
            const authorization = headerValue(headers, 'Authorization');
            if (!authorization || !authorization.startsWith('Bearer ')) {
                return;
            }

            probeStarted = true;
            setTimeout(function () {
                runReadOnlyProbes(authorization).catch(function (error) {
                    emit('fatal', { reason: error.message });
                });
            }, 250);
        }
    });
    emit('ready');
}
