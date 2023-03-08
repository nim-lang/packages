#!/bin/bash

set -e

targetRepository="https://github.com/$GITHUB_REPOSITORY"
targetBranch="$GITHUB_BASE_REF"

git branch merge-branch
cp packages.json packages.json.bak
git fetch "$targetRepository" "$targetBranch:base"
# Get packages.json at the branching point
git checkout "$(git merge-base merge-branch base)" packages.json
mv packages.json packages_old.json
mv packages.json.bak packages.json
