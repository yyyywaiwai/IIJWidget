'use strict';

// Observe MyIIJmio's application-layer networking without retaining credentials
// or user data. Every emitted record is prefixed with [IIJ-FRIDA] and contains
// URL query names, header names, and JSON/form shapes instead of their values.

const PREFIX = '[IIJ-FRIDA]';
const installedImplementations = new Set();
const retainedBlocks = new Set();

function emit(event, fields) {
    const payload = Object.assign({
        event: event,
        timestamp: new Date().toISOString()
    }, fields || {});
    console.log(PREFIX + ' ' + JSON.stringify(payload));
}

function describeError(errorPointer) {
    if (!errorPointer || errorPointer.isNull()) {
        return null;
    }

    try {
        const error = new ObjC.Object(errorPointer);
        return {
            domain: error.domain().toString(),
            code: Number(error.code())
        };
    } catch (_) {
        return { present: true };
    }
}

function redactedURL(value) {
    if (!value) {
        return null;
    }

    const raw = value.toString();
    const fragmentIndex = raw.indexOf('#');
    const withoutFragment = fragmentIndex >= 0 ? raw.slice(0, fragmentIndex) : raw;
    const queryIndex = withoutFragment.indexOf('?');
    if (queryIndex < 0) {
        return withoutFragment;
    }

    const base = withoutFragment.slice(0, queryIndex);
    const query = withoutFragment.slice(queryIndex + 1);
    const names = query
        .split('&')
        .filter(Boolean)
        .map(function (part) {
            const equalsIndex = part.indexOf('=');
            return equalsIndex >= 0 ? part.slice(0, equalsIndex) : part;
        })
        .map(function (name) {
            try {
                return decodeURIComponent(name.replace(/\+/g, ' '));
            } catch (_) {
                return name;
            }
        });

    return base + (names.length > 0 ? '?' + names.map(function (name) {
        return name + '=<redacted>';
    }).join('&') : '');
}

function safeHeaderValue(name, value) {
    const normalized = name.toLowerCase();
    const allowed = new Set([
        'accept',
        'accept-encoding',
        'accept-language',
        'content-type',
        'user-agent',
        'x-requested-with'
    ]);
    return allowed.has(normalized) ? value : '<redacted>';
}

function describeHeaders(dictionaryPointer) {
    if (!dictionaryPointer || dictionaryPointer.isNull()) {
        return {};
    }

    try {
        const dictionary = new ObjC.Object(dictionaryPointer);
        const keys = dictionary.allKeys();
        const result = {};
        for (let index = 0; index < Number(keys.count()); index += 1) {
            const keyObject = keys.objectAtIndex_(index);
            const key = keyObject.toString();
            const value = dictionary.objectForKey_(keyObject).toString();
            result[key] = safeHeaderValue(key, value);
        }
        return result;
    } catch (_) {
        return { unavailable: true };
    }
}

function shapeValue(value, depth) {
    if (depth > 8) {
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

function dataToUTF8(data) {
    try {
        const NSString = ObjC.classes.NSString;
        const string = NSString.alloc().initWithData_encoding_(data, 4);
        if (!string) {
            return null;
        }
        return string.toString();
    } catch (_) {
        return null;
    }
}

function describeData(dataPointer, contentType) {
    if (!dataPointer || dataPointer.isNull()) {
        return null;
    }

    try {
        const data = new ObjC.Object(dataPointer);
        const byteLength = Number(data.length());
        const description = { byteLength: byteLength };
        if (byteLength === 0 || byteLength > 1024 * 1024) {
            return description;
        }

        const text = dataToUTF8(data);
        if (text === null) {
            return description;
        }

        const normalizedContentType = (contentType || '').toLowerCase();
        const trimmed = text.trim();
        if (normalizedContentType.includes('json') || trimmed.startsWith('{') || trimmed.startsWith('[')) {
            try {
                description.format = 'json';
                description.shape = shapeValue(JSON.parse(trimmed), 0);
                return description;
            } catch (_) {
                description.format = 'json-invalid';
                return description;
            }
        }

        if (normalizedContentType.includes('application/x-www-form-urlencoded')) {
            description.format = 'form';
            description.fields = text.split('&').filter(Boolean).map(function (part) {
                const equalsIndex = part.indexOf('=');
                const rawName = equalsIndex >= 0 ? part.slice(0, equalsIndex) : part;
                try {
                    return decodeURIComponent(rawName.replace(/\+/g, ' '));
                } catch (_) {
                    return rawName;
                }
            });
            return description;
        }

        description.format = normalizedContentType || 'unknown';
        description.textLength = text.length;
        return description;
    } catch (_) {
        return { unavailable: true };
    }
}

function getHeader(headers, name) {
    const target = name.toLowerCase();
    const key = Object.keys(headers).find(function (candidate) {
        return candidate.toLowerCase() === target;
    });
    return key ? headers[key] : null;
}

function describeRequest(requestPointer) {
    if (!requestPointer || requestPointer.isNull()) {
        return null;
    }

    try {
        const request = new ObjC.Object(requestPointer);
        const headers = describeHeaders(request.allHTTPHeaderFields());
        const body = request.HTTPBody();
        return {
            method: request.HTTPMethod() ? request.HTTPMethod().toString() : 'GET',
            url: request.URL() ? redactedURL(request.URL().absoluteString()) : null,
            headers: headers,
            body: describeData(body, getHeader(headers, 'content-type'))
        };
    } catch (error) {
        return { unavailable: true, reason: error.message };
    }
}

function requestFromTask(taskPointer) {
    if (!taskPointer || taskPointer.isNull()) {
        return null;
    }

    try {
        const task = new ObjC.Object(taskPointer);
        let request = null;
        if (task.respondsToSelector_(ObjC.selector('currentRequest'))) {
            request = task.currentRequest();
        }
        if ((!request || request.isNull()) && task.respondsToSelector_(ObjC.selector('originalRequest'))) {
            request = task.originalRequest();
        }
        return request && !request.isNull() ? describeRequest(request) : null;
    } catch (_) {
        return null;
    }
}

function describeResponse(responsePointer) {
    if (!responsePointer || responsePointer.isNull()) {
        return null;
    }

    try {
        const response = new ObjC.Object(responsePointer);
        const result = {
            url: response.URL() ? redactedURL(response.URL().absoluteString()) : null,
            mimeType: response.MIMEType() ? response.MIMEType().toString() : null,
            expectedContentLength: Number(response.expectedContentLength())
        };

        if (response.respondsToSelector_(ObjC.selector('statusCode'))) {
            result.statusCode = Number(response.statusCode());
        }
        if (response.respondsToSelector_(ObjC.selector('allHeaderFields'))) {
            result.headers = describeHeaders(response.allHeaderFields());
        }
        return result;
    } catch (_) {
        return { unavailable: true };
    }
}

function attachOnce(method, handlers, label) {
    if (!method) {
        return false;
    }

    const address = method.implementation.toString();
    if (installedImplementations.has(address)) {
        return false;
    }
    installedImplementations.add(address);
    Interceptor.attach(method.implementation, handlers);
    emit('hook-installed', { target: label, address: address });
    return true;
}

function wrapDataCompletion(blockPointer, requestDescription, source) {
    if (!blockPointer || blockPointer.isNull()) {
        return;
    }

    try {
        const block = new ObjC.Block(blockPointer);
        const original = block.implementation;
        retainedBlocks.add(block);
        block.implementation = function (data, response, error) {
            try {
                const responseDescription = describeResponse(response);
                const contentType = responseDescription && responseDescription.headers
                    ? getHeader(responseDescription.headers, 'content-type')
                    : (responseDescription ? responseDescription.mimeType : null);
                emit('http-completion', {
                    source: source,
                    request: requestDescription,
                    response: responseDescription,
                    responseBody: describeData(data, contentType),
                    error: describeError(error)
                });
            } finally {
                retainedBlocks.delete(block);
            }
            return original(data, response, error);
        };
    } catch (error) {
        emit('hook-warning', { target: source, reason: error.message });
    }
}

function installURLSessionHooks() {
    const candidateClasses = ['NSURLSession', '__NSCFURLSession'];
    candidateClasses.forEach(function (className) {
        const klass = ObjC.classes[className];
        if (!klass) {
            return;
        }

        const requestSelector = '- dataTaskWithRequest:completionHandler:';
        attachOnce(klass[requestSelector], {
            onEnter: function (args) {
                const request = describeRequest(args[2]);
                emit('http-request', { source: className + ' ' + requestSelector, request: request });
                wrapDataCompletion(args[3], request, className + ' ' + requestSelector);
            }
        }, className + ' ' + requestSelector);

        const urlSelector = '- dataTaskWithURL:completionHandler:';
        attachOnce(klass[urlSelector], {
            onEnter: function (args) {
                const url = args[2].isNull() ? null : redactedURL(new ObjC.Object(args[2]).absoluteString());
                const request = { method: 'GET', url: url, headers: {}, body: null };
                emit('http-request', { source: className + ' ' + urlSelector, request: request });
                wrapDataCompletion(args[3], request, className + ' ' + urlSelector);
            }
        }, className + ' ' + urlSelector);

        const uploadSelector = '- uploadTaskWithRequest:fromData:completionHandler:';
        attachOnce(klass[uploadSelector], {
            onEnter: function (args) {
                const request = describeRequest(args[2]);
                if (request && !request.body) {
                    request.body = describeData(args[3], request.headers ? getHeader(request.headers, 'content-type') : null);
                }
                emit('http-request', { source: className + ' ' + uploadSelector, request: request });
                wrapDataCompletion(args[4], request, className + ' ' + uploadSelector);
            }
        }, className + ' ' + uploadSelector);
    });

    const taskClass = ObjC.classes.NSURLSessionTask;
    if (taskClass) {
        const resumeSelector = '- resume';
        attachOnce(taskClass[resumeSelector], {
            onEnter: function (args) {
                try {
                    const task = new ObjC.Object(args[0]);
                    emit('task-resume', {
                        taskClass: task.$className,
                        request: requestFromTask(args[0])
                    });
                } catch (error) {
                    emit('hook-warning', { target: 'NSURLSessionTask resume', reason: error.message });
                }
            }
        }, 'NSURLSessionTask ' + resumeSelector);
    }
}

function installURLSessionDelegateHooks() {
    // MyIIJmio 3.2.5 uses React Native's networking delegates. Restricting the
    // hooks to these classes avoids attaching to unrelated UIKit methods that
    // happen to share the same Objective-C selector text.
    const classNames = ['RCTHTTPRequestHandler', 'RCTMultipartDataTask'];

    const selectors = [
        '- URLSession:dataTask:didReceiveResponse:completionHandler:',
        '- URLSession:dataTask:didReceiveData:',
        '- URLSession:task:didCompleteWithError:',
        '- URLSession:task:willPerformHTTPRedirection:newRequest:completionHandler:'
    ];

    classNames.forEach(function (className) {
        const klass = ObjC.classes[className];
        if (!klass) {
            return;
        }

        selectors.forEach(function (selector) {
            const method = klass[selector];
            if (!method) {
                return;
            }

            if (selector === '- URLSession:dataTask:didReceiveResponse:completionHandler:') {
                attachOnce(method, {
                    onEnter: function (args) {
                        emit('http-delegate-response', {
                            delegateClass: className,
                            request: requestFromTask(args[3]),
                            response: describeResponse(args[4])
                        });
                    }
                }, className + ' ' + selector);
                return;
            }

            if (selector === '- URLSession:dataTask:didReceiveData:') {
                attachOnce(method, {
                    onEnter: function (args) {
                        const request = requestFromTask(args[3]);
                        emit('http-delegate-data', {
                            delegateClass: className,
                            request: request,
                            responseBodyChunk: describeData(
                                args[4],
                                request && request.headers ? getHeader(request.headers, 'content-type') : null
                            )
                        });
                    }
                }, className + ' ' + selector);
                return;
            }

            if (selector === '- URLSession:task:didCompleteWithError:') {
                attachOnce(method, {
                    onEnter: function (args) {
                        emit('http-delegate-completion', {
                            delegateClass: className,
                            request: requestFromTask(args[3]),
                            error: describeError(args[4])
                        });
                    }
                }, className + ' ' + selector);
                return;
            }

            attachOnce(method, {
                onEnter: function (args) {
                    emit('http-redirect', {
                        delegateClass: className,
                        request: requestFromTask(args[3]),
                        response: describeResponse(args[4]),
                        nextRequest: describeRequest(args[5])
                    });
                }
            }, className + ' ' + selector);
        });
    });
}

function installWebAuthenticationHooks() {
    const candidates = [
        ['ASWebAuthenticationSession', '- initWithURL:callbackURLScheme:completionHandler:'],
        ['SFAuthenticationSession', '- initWithURL:callbackURLScheme:completionHandler:']
    ];

    candidates.forEach(function (candidate) {
        const className = candidate[0];
        const selector = candidate[1];
        const klass = ObjC.classes[className];
        if (!klass) {
            return;
        }

        attachOnce(klass[selector], {
            onEnter: function (args) {
                const url = args[2].isNull() ? null : redactedURL(new ObjC.Object(args[2]).absoluteString());
                const callbackScheme = args[3].isNull() ? null : new ObjC.Object(args[3]).toString();
                emit('web-auth-start', {
                    implementation: className,
                    url: url,
                    callbackScheme: callbackScheme
                });

                if (args[4].isNull()) {
                    return;
                }

                try {
                    const block = new ObjC.Block(args[4]);
                    const original = block.implementation;
                    retainedBlocks.add(block);
                    block.implementation = function (callbackURL, error) {
                        try {
                            emit('web-auth-completion', {
                                implementation: className,
                                callbackURL: callbackURL && !callbackURL.isNull()
                                    ? redactedURL(new ObjC.Object(callbackURL).absoluteString())
                                    : null,
                                error: describeError(error)
                            });
                        } finally {
                            retainedBlocks.delete(block);
                        }
                        return original(callbackURL, error);
                    };
                } catch (error) {
                    emit('hook-warning', { target: className, reason: error.message });
                }
            }
        }, className + ' ' + selector);
    });

    const webView = ObjC.classes.WKWebView;
    if (webView) {
        const selector = '- loadRequest:';
        attachOnce(webView[selector], {
            onEnter: function (args) {
                emit('webview-request', {
                    request: describeRequest(args[2])
                });
            }
        }, 'WKWebView ' + selector);
    }
}

function installHooks() {
    installURLSessionHooks();
    installURLSessionDelegateHooks();
    installWebAuthenticationHooks();
}

if (!ObjC.available) {
    emit('fatal', { reason: 'Objective-C runtime is unavailable' });
} else {
    emit('observer-ready', {
        processId: Process.id,
        architecture: Process.arch,
        bundleIdentifier: ObjC.classes.NSBundle.mainBundle().bundleIdentifier().toString()
    });
    installHooks();
    setInterval(installHooks, 1000);
}
