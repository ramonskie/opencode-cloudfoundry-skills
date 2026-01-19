#!/bin/bash
# Smart search for buildpack repos: local first, GitHub fallback

set -e

PATTERN="$1"
LOCAL_ROOT="$HOME/workspace/cloudfoundry"

if [ -z "$PATTERN" ]; then
    echo "Usage: $0 <search-pattern>"
    echo ""
    echo "Example: $0 'libbuildpack\.Manifest'"
    exit 1
fi

echo "🔍 Searching local buildpack repos for: $PATTERN"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Search local repos
RESULTS=$(rg "$PATTERN" "$LOCAL_ROOT" 2>/dev/null || true)

if [ -n "$RESULTS" ]; then
    echo "✅ Found in local repos:"
    echo ""
    echo "$RESULTS"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    # Count matches
    MATCH_COUNT=$(echo "$RESULTS" | wc -l)
    FILE_COUNT=$(echo "$RESULTS" | cut -d: -f1 | sort -u | wc -l)
    echo "📊 Found $MATCH_COUNT matches in $FILE_COUNT files"
else
    echo "❌ Not found in local repos"
    echo ""
    echo "💡 Suggestions:"
    echo ""
    echo "1. Use librarian agent to search GitHub repos:"
    echo "   - cloudfoundry/nodejs-buildpack"
    echo "   - cloudfoundry/hwc-buildpack"
    echo "   - cloudfoundry/buildpack-packager"
    echo ""
    echo "2. Consider cloning frequently-accessed repos:"
    echo "   cd ~/workspace/cloudfoundry/buildpacks/"
    echo "   git clone https://github.com/cloudfoundry/[repo-name].git"
    echo ""
    echo "3. Try different search patterns:"
    echo "   - Use regex: 'libbuildpack\..*'"
    echo "   - Case insensitive: -i flag"
    echo "   - Specific file types: --type go"
    echo ""
    echo "4. Check if you meant to search libbuildpack first:"
    echo "   rg '$PATTERN' ~/workspace/cloudfoundry/libbuildpack/"
fi
