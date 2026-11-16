#!/usr/bin/env python3
"""在登记的缓存中复现弱代理释放后的真实默认侧滑，不修改输入工作区。"""
import argparse
import hashlib
import io
import json
import os
from pathlib import Path, PurePosixPath
import shutil
import subprocess
import tarfile
import tempfile

BASE = "28c384f4af4383cd0c813f6ea2a8f22547c3bcb4"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", required=True, type=Path)
    parser.add_argument("--destination", required=True)
    args = parser.parse_args()
    repo = args.repo.resolve()
    work = Path(tempfile.mkdtemp(prefix="weak-edge-probe-", dir=os.environ["CODEX_CACHE_DIR"]))
    evidence = Path(os.environ["CODEX_EVIDENCE_DIR"]) / work.name
    evidence.mkdir()
    checkout = work / "checkout"
    checkout.mkdir()
    archive = subprocess.check_output(["git", "-C", str(repo), "archive", BASE])
    # 输入只来自固定 Git 提交。拒绝链接/特殊文件/越界路径，以支持系统 Python 3.9。
    with tarfile.open(fileobj=io.BytesIO(archive)) as source:
        members = []
        for member in source.getmembers():
            path = PurePosixPath(member.name)
            if path.is_absolute() or ".." in path.parts or not (member.isfile() or member.isdir()):
                raise RuntimeError("unsafe Git archive member: " + member.name)
            if path.parts[0] != "Sources":
                members.append(member)
        source.extractall(checkout, members=members)
    shutil.copytree(repo / "Sources", checkout / "Sources")
    patch = Path(__file__).with_name("probe.patch").resolve()
    environment = os.environ.copy()
    environment.pop("SDKROOT", None)
    commands = [["patch", "-p1", "-i", str(patch)]]
    command = [
        "xcodebuild", "test", "-project", str(checkout / "Examples/LYStackRouterExamples.xcodeproj"),
        "-scheme", "LYStackRouterExamples", "-destination", args.destination,
        "-derivedDataPath", str(work / "derived-data"),
        "-clonedSourcePackagesDirPath", str(Path(os.environ["CODEX_DEPENDENCIES_DIR"]) / "packages"),
        "-resultBundlePath", str(evidence / "weak-edge.xcresult"),
        "-parallel-testing-enabled", "NO", "SWIFT_STRICT_CONCURRENCY=complete", "CODE_SIGNING_ALLOWED=NO",
    ]
    for test in ["testCompletedSwipeBackIsNotTreatedAsRouterCleanup",
                 "testInteractivePopCancelKeepsPageAndWakesDeferredDeepLink",
                 "testDefaultSwipeBackWorksAfterWeakInteractionDelegateRelease"]:
        command.append("-only-testing:LYStackRouterExamplesUITests/RoutingUITests/" + test)
    commands.append(command)
    files = sorted((repo / "Sources").rglob("*.swift"))
    (evidence / "inputs.json").write_text(json.dumps({
        "fixture_base": BASE,
        "source_head": subprocess.check_output(["git", "-C", str(repo), "rev-parse", "HEAD"], text=True).strip(),
        "source_sha256": {str(p.relative_to(repo)): hashlib.sha256(p.read_bytes()).hexdigest() for p in files},
        "probe_sha256": hashlib.sha256(patch.read_bytes()).hexdigest(),
        "commands": commands,
    }, indent=2) + "\n")
    for index, invocation in enumerate(commands):
        with (evidence / ("patch.log" if index == 0 else "test.log")).open("w") as log:
            result = subprocess.run(invocation, cwd=checkout, env=environment, stdout=log, stderr=subprocess.STDOUT)
        if result.returncode:
            raise RuntimeError("probe failed; preserved at " + str(evidence))
    output = subprocess.check_output([
        "xcrun", "xcresulttool", "get", "test-results", "summary", "--path", str(evidence / "weak-edge.xcresult"), "--format", "json",
    ], env=environment, text=True)
    (evidence / "summary.json").write_text(output)
    summary = json.loads(output)
    if summary.get("passedTests") != 3 or summary.get("failedTests") != 0 or summary.get("skippedTests") != 0:
        raise RuntimeError("expected all three UI cases; see " + str(evidence))
    print("Weak delegate edge probe: PASS 3/3; " + str(evidence), flush=True)


if __name__ == "__main__":
    main()
