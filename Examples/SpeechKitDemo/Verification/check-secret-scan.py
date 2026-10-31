#!/usr/bin/env python3
"""Exercise the redacting wrapper in a disposable Git repository, including a custom ref."""
import os
from pathlib import Path
import subprocess
import tempfile

wrapper = Path(__file__).with_name("scan-secrets.sh").resolve()

with tempfile.TemporaryDirectory(prefix="speechkit-scan-check-") as temporary:
    repo = Path(temporary)

    def git(*args, input=None):
        return subprocess.check_output(
            ["git", "-c", "user.name=SpeechKit verification", "-c", "user.email=verification@example.invalid", *args],
            cwd=repo, input=input, stderr=subprocess.DEVNULL,
        ).decode().strip()

    git("init", "-q", "-b", "main")
    clean_tree = git("mktree", input=b"")
    clean_commit = git("commit-tree", clean_tree, input=b"Synthetic clean baseline\n")
    git("update-ref", "refs/heads/main", clean_commit)

    def scan():
        return subprocess.run(["bash", str(wrapper), str(repo)], cwd=repo, env=os.environ, capture_output=True, text=True)

    assert scan().returncode == 0, "Clean fixture must pass"
    # Deliberately invalid, synthetic GitLab-shaped canary, generated only in this temp repo.
    canary = "glpat-" + "A1b2C3d4E5f6G7h8I9j0"
    blob = git("hash-object", "-w", "--stdin", input=("token=" + canary + "\n").encode())
    tree = git("mktree", input=f"100644 blob {blob}\tfixture.txt\n".encode())
    commit = git("commit-tree", tree, "-p", clean_commit, input=b"Synthetic custom-ref canary\n")
    git("update-ref", "refs/t3/checkpoints/synthetic-canary", commit)
    result = scan()
    assert result.returncode != 0, "Custom-ref canary must fail the scan"
    assert canary not in result.stdout + result.stderr, "Scanner wrapper must never print values"
    assert "Findings are suppressed" in result.stdout, "Failure must explain the suppressed output"
    git("update-ref", "-d", "refs/t3/checkpoints/synthetic-canary")
    assert scan().returncode == 0, "Only the custom ref should have exposed the canary to --all"

print("Secret scan checks passed, including redaction and local checkpoint refs.")
