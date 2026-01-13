

#!/bin/bash





# ===========================
# CONFIG
# ===========================
MM_URL="YOUR_MATTERMOST_URL"              
TOKEN="YOUR_API_TOKEN"    
CHANNEL_ID="YOUR_CHANNEL_ID"
OUTPUT_FILE="channel_export_$(date +%Y%m%d_%H%M%S).html"


api() {
    curl -s -H "Authorization: Bearer $TOKEN" "$MM_URL/api/v4/$1"
}

to_readable_date() {
    ms=$1
    sec=$((ms / 1000))
    date -r "$sec" +"%Y-%m-%d %H:%M:%S"
}

# Convert URLs in text to clickable HTML links
linkify() {
    printf '%s' "$1" | \
        sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g' | \
        sed -E 's|(https?://[^[:space:]<>"'\'']+)|<a href="\1">\1</a>|g'
}

echo "Starting export..."

# Get channel name FIRST before creating HTML
echo "Fetching channel info..."
TEMP_CHANNEL=$(mktemp)
api "channels/$CHANNEL_ID" > "$TEMP_CHANNEL"

# Try to extract channel name, handling control characters
channel_name=$(jq -r '.display_name // .name // empty' "$TEMP_CHANNEL" 2>/dev/null | tr -d '\000-\037' | head -1)

echo "Channel name: '$channel_name'"

# If channel name is empty, set a default
if [[ -z "$channel_name" || "$channel_name" == "null" ]]; then
    channel_name="Channel Export"
    echo "Warning: Could not fetch channel name, using default"
fi

rm "$TEMP_CHANNEL"

# Create temp file for all posts
ALL_POSTS=$(mktemp)
echo '{"order":[],"posts":{}}' > "$ALL_POSTS"

# Fetch all posts with pagination
page=0
per_page=200
total_fetched=0

while true; do
    echo "Fetching page $page..."
    TEMP_RESPONSE=$(mktemp)
    api "channels/$CHANNEL_ID/posts?page=$page&per_page=$per_page" > "$TEMP_RESPONSE"
    
    # Check for valid JSON
    if ! jq -e '.order' "$TEMP_RESPONSE" > /dev/null 2>&1; then
        echo "ERROR: Failed to parse API response on page $page"
        rm "$TEMP_RESPONSE" "$ALL_POSTS"
        exit 1
    fi
    
    # Count posts in this page
    page_count=$(jq '.order | length' "$TEMP_RESPONSE")
    echo "  Got $page_count posts"
    
    # Break if no more posts
    if [[ "$page_count" -eq 0 ]]; then
        rm "$TEMP_RESPONSE"
        break
    fi
    
    # Merge this page into ALL_POSTS
    jq -s '
        {
            order: (.[0].order + .[1].order),
            posts: (.[0].posts + .[1].posts)
        }
    ' "$ALL_POSTS" "$TEMP_RESPONSE" > "${ALL_POSTS}.tmp"
    mv "${ALL_POSTS}.tmp" "$ALL_POSTS"
    
    total_fetched=$((total_fetched + page_count))
    rm "$TEMP_RESPONSE"
    
    # Break if count is fewer than requested (last page)
    if [[ "$page_count" -lt "$per_page" ]]; then
        break
    fi
    
    ((page++))
done

echo "Total posts fetched: $total_fetched"

# Create HTML output with channel name and export date
{
    echo '<!DOCTYPE html>'
    echo '<html><head><meta charset="UTF-8"><title>'"$channel_name"' - Export</title>'
    echo '<style>'
    echo 'body { font-family: Arial, sans-serif; max-width: 800px; margin: 0 auto; padding: 20px; }'
    echo '.post { border-bottom: 1px solid #ccc; padding: 15px 0; }'
    echo '.meta { color: #666; font-size: 0.9em; }'
    echo '.message { white-space: pre-wrap; margin-top: 10px; }'
    echo 'a { color: #0066cc; }'
    echo 'h1 { margin-bottom: 5px; }'
    echo '.export-date { color: #666; margin-bottom: 20px; }'
    echo '</style></head><body>'
    echo "<h1>$channel_name</h1>"
    echo "<p class=\"export-date\">Exported: $(date)</p>"
    echo '<hr>'
} > "$OUTPUT_FILE"

# Use a temp file to track count
COUNT_FILE=$(mktemp)
echo "0" > "$COUNT_FILE"

# Reverse the order array (oldest first) and process
jq -r '.order | reverse | .[]' "$ALL_POSTS" | while read -r post_id; do
    # Extract all fields in one jq call, using @base64 for message to handle special chars
    post_data=$(jq -r --arg pid "$post_id" '
        .posts[$pid] // empty | 
        select(.message != null and .message != "") |
        [.create_at, .user_id, (.message | @base64)] | @tsv
    ' "$ALL_POSTS" 2>/dev/null)
    
    if [[ -n "$post_data" ]]; then
        create_at=$(echo "$post_data" | cut -f1)
        user_id=$(echo "$post_data" | cut -f2)
        message_b64=$(echo "$post_data" | cut -f3-)
        
        # Decode base64 message
        message=$(echo "$message_b64" | base64 -d)
        
        # Get username, default to "unknown" if user lookup fails
        username=""
        if [[ -n "$user_id" && "$user_id" != "null" ]]; then
            user_info=$(api "users/$user_id")
            username=$(echo "$user_info" | jq -r '.username // empty')
        fi
        if [[ -z "$username" ]]; then
            username="unknown"
        fi
        
        # Format date, or show "unknown date" if missing
        if [[ -n "$create_at" && "$create_at" != "null" && "$create_at" != "0" ]]; then
            post_date=$(to_readable_date "$create_at")
        else
            post_date="unknown date"
        fi
        
        linked_message=$(linkify "$message")
        
        {
            echo '<div class="post">'
            echo "<div class=\"meta\">🗓️ $post_date &nbsp;|&nbsp; 👤 @$username</div>"
            echo "<div class=\"message\">$linked_message</div>"
            echo '</div>'
        } >> "$OUTPUT_FILE"
        
        # Increment count
        count=$(<"$COUNT_FILE")
        echo "$((count + 1))" > "$COUNT_FILE"
        
        # Show progress every 50 posts
        if [[ $((count % 50)) -eq 0 ]]; then
            echo "Processed $((count + 1)) posts..."
        fi
    fi
done

post_count=$(<"$COUNT_FILE")

# Close HTML
{
    echo "<p><strong>Total posts exported: $post_count</strong></p>"
    echo '</body></html>'
} >> "$OUTPUT_FILE"

# Cleanup
rm "$ALL_POSTS" "$COUNT_FILE"

echo "Export complete: $OUTPUT_FILE"
echo "Posts found: $post_count"
