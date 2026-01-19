#!/bin/bash
# Smart search for BOSH repos: local first, GitHub fallback

set -e

PATTERN="$1"
LOCAL_ROOT="$HOME/workspace/bosh"

if [ -z "$PATTERN" ]; then
    echo "Usage: $0 <search-pattern>"
    echo ""
    echo "Example: $0 'Agent.*Apply'"
    exit 1
fi

echo "🔍 Searching local BOSH repos for: $PATTERN"
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
    echo "   - cloudfoundry/bosh-openstack-cpi-release"
    echo "   - cloudfoundry/bosh-azure-cpi-release"
    echo "   - cloudfoundry/bosh-vsphere-cpi-release"
    echo "   - cloudfoundry/bosh-cli"
    echo "   - cloudfoundry/bosh-utils"
    echo ""
    echo "2. Consider cloning frequently-accessed repos:"
    echo "   cd ~/workspace/bosh/"
    echo "   git clone https://github.com/cloudfoundry/[repo-name].git"
    echo ""
    echo "3. Try different search patterns:"
    echo "   - Use regex: 'Agent.*Apply'"
    echo "   - Case insensitive: -i flag"
    echo "   - Specific file types: --type go"
fi
