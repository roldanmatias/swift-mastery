#!/bin/bash
# Ex 20 step 6 — migration-debt report: every scoped warning escape in the repo.
# `reason:` must be a static string (no interpolation, SE-0522), which is exactly
# what makes this grep-able by tools and agents.
cd "$(dirname "$0")/.." || exit 1
echo "| File | Group | Behavior | Reason |"
echo "| --- | --- | --- | --- |"
grep -rn --include='*.swift' -E '^\s*@diagnose\(' Sources | while IFS= read -r line; do
    location=${line%%:@diagnose*}; location=${location%%:*}:$(echo "$line" | cut -d: -f2)
    attribute=$(echo "$line" | sed -E 's/.*@diagnose\((.*)\).*/\1/')
    group=$(echo "$attribute" | cut -d, -f1 | xargs)
    behavior=$(echo "$attribute" | sed -E 's/.*as: *([a-z]+).*/\1/')
    reason=$(echo "$attribute" | sed -nE 's/.*reason: *"([^"]*)".*/\1/p')
    echo "| $location | $group | $behavior | ${reason:-⚠️ no reason} |"
done
