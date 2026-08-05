#!/usr/bin/env python3

import argparse
import os
import shutil
import stat
import subprocess


SCRIPT = r"""
'use strict';

let delivered = false;

function inspectRequest(request) {
    if (delivered || !request || request.isNull()) {
        return;
    }

    try {
        const url = request.URL();
        if (!url || !url.host() || url.host().toString() !== 'gapi.iijmio.jp') {
            return;
        }

        const headers = request.allHTTPHeaderFields();
        if (!headers || headers.isNull()) {
            return;
        }
        const keys = headers.allKeys();
        for (let index = 0; index < Number(keys.count()); index += 1) {
            const key = keys.objectAtIndex_(index);
            if (key.toString().toLowerCase() !== 'authorization') {
                continue;
            }
            const authorization = headers.objectForKey_(key).toString();
            if (authorization.startsWith('Bearer ')) {
                delivered = true;
                console.log(authorization);
            }
            return;
        }
    } catch (_) {
        // The task may be transitioning between states. Future resume calls
        // remain hooked and will retry without logging request contents.
    }
}

function inspectTask(task) {
    try {
        if (task.respondsToSelector_(ObjC.selector('currentRequest'))) {
            inspectRequest(task.currentRequest());
        }
        if (!delivered && task.respondsToSelector_(ObjC.selector('originalRequest'))) {
            inspectRequest(task.originalRequest());
        }
    } catch (_) {
    }
}

if (!ObjC.available) {
    console.error('Objective-C runtime is unavailable');
} else {
    const resume = ObjC.classes.NSURLSessionTask['- resume'];
    Interceptor.attach(resume.implementation, {
        onEnter(args) {
            inspectTask(new ObjC.Object(args[0]));
        }
    });

    ObjC.choose(ObjC.classes.NSURLSessionTask, {
        onMatch(task) {
            inspectTask(task);
            return delivered ? 'stop' : undefined;
        },
        onComplete() {}
    });
}
"""


def write_secret(path: str, value: str) -> None:
    flags = os.O_WRONLY | os.O_CREAT | os.O_TRUNC
    descriptor = os.open(path, flags, stat.S_IRUSR | stat.S_IWUSR)
    try:
        os.write(descriptor, value.encode("utf-8"))
    finally:
        os.close(descriptor)
    os.chmod(path, stat.S_IRUSR | stat.S_IWUSR)


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Capture MyIIJmio's Bearer header into a mode-0600 file without printing it."
    )
    parser.add_argument("--output", required=True)
    parser.add_argument("--bundle-id", default="jp.ad.iij.my-iijmio")
    parser.add_argument("--timeout", type=float, default=60.0)
    args = parser.parse_args()

    frida_cli = shutil.which("frida")
    if frida_cli is None:
        print("frida CLI was not found in PATH")
        return 1

    process = subprocess.Popen(
        [
            frida_cli,
            "-U",
            "-N",
            args.bundle_id,
            "-q",
            "-e",
            SCRIPT,
            "-t",
            str(max(int(args.timeout), 1)),
        ],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        bufsize=1,
    )

    authorization = None
    assert process.stdout is not None
    for line in process.stdout:
        candidate = line.strip()
        if candidate.startswith("Bearer "):
            authorization = candidate
            process.terminate()
            break

    try:
        _, stderr = process.communicate(timeout=3)
    except subprocess.TimeoutExpired:
        process.kill()
        _, stderr = process.communicate()

    if authorization is None:
        if "unable to find process" in stderr.lower():
            print(f"Running application not found: {args.bundle_id}")
        else:
            print("Timed out waiting for an authenticated GAPI request")
        return 1

    write_secret(args.output, f"Authorization: {authorization}\n")
    print(f"Captured authorization header ({len(authorization)} characters) into a mode-0600 file")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
