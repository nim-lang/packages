#!/bin/bash

# CI helper script to checkout the current packages.json and
# the version at the merge base to compare to.

set -e

targetRepository="https://github.com/$GITHUB_REPOSITORY"
targetBranch="$GITHUB_BASE_REF"

git branch merge-branch
cp packages.json packages.json.bak
git fetch "$targetRepository" "$targetBranch:base"
# Get packages.json at the branching point
mergeBase="$(git merge-base merge-branch base)"
echo "Comparing against packages.json at $mergeBase"
git checkout "$mergeBase" packages.json
mv packages.json packages_old.json
mv packages.json.bak packages.json
