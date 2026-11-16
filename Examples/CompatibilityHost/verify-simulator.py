#!/usr/bin/env python3
"""构建并运行真实消费宿主；所有输出目录由调用者显式传入。"""

import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import time


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--device", required=True, help="已存在的 iOS Simulator UDID")
    parser.add_argument("--derived-data", required=True, type=Path)
    parser.add_argument("--packages", required=True, type=Path)
    parser.add_argument("--evidence", required=True, type=Path)
    parser.add_argument("--scheme", action="append", choices=["LYRouterCoreCompatibility", "LYRouterDiscoveryCompatibility"])
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[2]
    args.evidence.mkdir(parents=True, exist_ok=False)
    commands = []

    def run(command, name, timeout=1200, accept_failure=False):
        commands.append(command)
        with (args.evidence / (name + ".log")).open("w") as log:
            result = subprocess.run(command, cwd=repo, stdout=log, stderr=subprocess.STDOUT, timeout=timeout)
        if result.returncode and not accept_failure:
            raise RuntimeError(name + " failed; see log")

    try:
        run(["xcrun", "simctl", "boot", args.device], "boot", accept_failure=True)
        run(["xcrun", "simctl", "bootstatus", args.device, "-b"], "boot-status", timeout=180)
        for scheme in args.scheme or ["LYRouterCoreCompatibility", "LYRouterDiscoveryCompatibility"]:
            run([
                "xcodebuild", "build", "-project", "Examples/CompatibilityHost/LYRouterCompatibility.xcodeproj",
                "-scheme", scheme, "-configuration", "Release",
                "-destination", "platform=iOS Simulator,id=" + args.device,
                "-derivedDataPath", str(args.derived_data), "-clonedSourcePackagesDirPath", str(args.packages),
                "CODE_SIGNING_ALLOWED=NO", "SWIFT_STRICT_CONCURRENCY=complete",
            ], scheme + "-build")
            app = args.derived_data / "Build/Products/Release-iphonesimulator" / (scheme + ".app")
            bundle = "com.kahnli." + scheme
            run(["xcrun", "simctl", "terminate", args.device, bundle], scheme + "-terminate", accept_failure=True)
            run(["xcrun", "simctl", "install", args.device, str(app)], scheme + "-install", timeout=180)
            container_command = ["xcrun", "simctl", "get_app_container", args.device, bundle, "data"]
            commands.append(container_command)
            container = Path(subprocess.check_output(container_command, text=True, timeout=30).strip())
            report = container / "Documents/compatibility-report.json"
            if report.exists():
                shutil.copy2(report, args.evidence / (scheme + "-previous-report.json"))
                report.unlink()
            run(["xcrun", "simctl", "launch",
                 "--stdout=" + str((args.evidence / (scheme + "-stdout.log")).resolve()),
                 "--stderr=" + str((args.evidence / (scheme + "-stderr.log")).resolve()),
                 args.device, bundle], scheme + "-launch", timeout=60)
            deadline = time.monotonic() + 45
            while not report.exists():
                if time.monotonic() >= deadline:
                    raise RuntimeError(scheme + " produced no fresh report in 45 seconds")
                time.sleep(0.1)
            shutil.copy2(report, args.evidence / (scheme + "-report.json"))
            data = json.loads(report.read_text())
            if data.get("passed") is not True or len(data.get("checks", [])) < 10:
                raise RuntimeError(scheme + " failed public API checks: " + json.dumps(data))
            print(scheme + ": PASS " + str(len(data["checks"])) + " checks on iOS " + data["systemVersion"], flush=True)
            run(["xcrun", "simctl", "terminate", args.device, bundle], scheme + "-stop")
    finally:
        (args.evidence / "commands.json").write_text(json.dumps(commands, indent=2) + "\n")
        files = [path for directory in [repo / "Sources", Path(__file__).parent] for path in directory.rglob("*.swift")]
        (args.evidence / "source-manifest.json").write_text(json.dumps({
            "head": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=repo, text=True).strip(),
            "files": {str(path.relative_to(repo)): hashlib.sha256(path.read_bytes()).hexdigest() for path in files},
        }, indent=2) + "\n")


if __name__ == "__main__":
    main()
