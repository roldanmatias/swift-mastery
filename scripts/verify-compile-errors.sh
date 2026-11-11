#!/bin/bash
# Compiles every snippet in CompileFailures/ (full compile, so SIL-level
# diagnostics like `discard` and lifetime errors are included) and checks that
# it FAILS with the message in its `// expect:` line. An optional second line
# `// flags: …` adds compiler flags (the Day 5 concurrency snippets use
# `-swift-version 6`, and some `-default-isolation MainActor`).
# Usage: scripts/verify-compile-errors.sh   (uses the repo's .swift-version via swiftly)
cd "$(dirname "$0")/../CompileFailures" || exit 1
SWIFTC=(swiftc); command -v swiftly >/dev/null && SWIFTC=(swiftly run swiftc)
pass=0; fail=0
for file in *.swift; do
    expected=$(head -1 "$file" | sed 's#^// expect: ##')
    flags=(); second=$(sed -n 2p "$file")
    [[ "$second" == "// flags: "* ]] && read -r -a flags <<< "${second#// flags: }"
    output=$("${SWIFTC[@]}" -parse-as-library -module-name Main "${flags[@]}" -c "$file" -o /dev/null 2>&1 | sed 's/\x1b\[[0-9;]*m//g')
    first=$(echo "$output" | grep -m1 "error:" | sed 's/.*error: //')
    if echo "$output" | grep -q "error:.*$expected"; then
        pass=$((pass + 1)); printf "✔ %-40s %s\n" "${file%.swift}" "$first"
    else
        fail=$((fail + 1)); printf "✘ %-40s expected '%s', got: %s\n" "${file%.swift}" "$expected" "${first:-<compiled successfully>}"
    fi
done
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
