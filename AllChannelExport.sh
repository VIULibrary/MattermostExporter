

#!/bin/bash


# ===========================
# CONFIG
# ===========================
MM_URL="YOUR_MATTERMOST_URL"              
TOKEN="YOUR_API_TOKEN"    
CSV_FILE="channels.csv"
OUTPUT_FOLDER="FinalExports"  # Output subfolder for HTML files
DATESTAMP=$(date +%Y%m%d_%H%M%S)

api() {
    curl -s -H "Authorization: Bearer $TOKEN" "$MM_URL/api/v4/$1"
}

to_readable_date() {
    ms=$1
    sec=$((ms / 1000))
    date -r "$sec" +"%Y-%m-%d %H:%M:%S"
}

linkify() {
    local text="$1"
    printf '%s' "$text" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g' | sed -E 's|(https?://[^[:space:]<>"]+)|<a href="\1">\1</a>|g'
}

sanitize_filename() {
    echo "$1" | sed 's/[^a-zA-Z0-9._-]/_/g'
}

export_channel() {
    local channel_id="$1"
    local display_name="$2"
    
    echo ""
    echo "========================================"
    echo "Exporting: $display_name"
    echo "Channel ID: $channel_id"
    echo "========================================"
    
    if [[ -z "$channel_id" ]]; then
        echo "  ERROR: Empty channel ID, skipping"
        return 1
    fi
    
    local safe_name=$(sanitize_filename "$display_name")
    if [[ -z "$safe_name" ]]; then
        safe_name="channel_export"
    fi
    local output_file="${OUTPUT_FOLDER}/${safe_name}_${DATESTAMP}.html"
    echo "Output: $output_file"
    
    TEMP_CHANNEL=$(mktemp)
    api "channels/$channel_id" > "$TEMP_CHANNEL"
    channel_name=$(jq -r '.display_name // .name // empty' "$TEMP_CHANNEL" 2>/dev/null | tr -d '\000-\037' | head -1)
    rm "$TEMP_CHANNEL"
    
    if [[ -z "$channel_name" || "$channel_name" == "null" ]]; then
        channel_name="$display_name"
    fi
    
    echo "Channel name: $channel_name"
    
    ALL_POSTS=$(mktemp)
    echo '{"order":[],"posts":{}}' > "$ALL_POSTS"
    
    page=0
    per_page=200
    total_fetched=0
    
    while true; do
        echo "  Fetching page $page..."
        TEMP_RESPONSE=$(mktemp)
        api "channels/$channel_id/posts?page=$page&per_page=$per_page" > "$TEMP_RESPONSE"
        
        # Debug:
        response_size=$(wc -c < "$TEMP_RESPONSE")
        echo "    Response size: $response_size bytes"
        if [[ $response_size -lt 100 ]]; then
            echo "    Response content: $(cat "$TEMP_RESPONSE")"
        fi
        
        if ! jq -e '.order' "$TEMP_RESPONSE" > /dev/null 2>&1; then
            echo "  ERROR: Failed to parse API response on page $page"
            echo "  First 500 chars of response:"
            head -c 500 "$TEMP_RESPONSE"
            echo ""
            rm "$TEMP_RESPONSE" "$ALL_POSTS"
            return 1
        fi
        
        page_count=$(jq '.order | length' "$TEMP_RESPONSE")
        echo "    Got $page_count posts"
        
        if [[ "$page_count" -eq 0 ]]; then
            rm "$TEMP_RESPONSE"
            break
        fi
        
        jq -s '{order: (.[0].order + .[1].order), posts: (.[0].posts + .[1].posts)}' "$ALL_POSTS" "$TEMP_RESPONSE" > "${ALL_POSTS}.tmp"
        mv "${ALL_POSTS}.tmp" "$ALL_POSTS"
        
        total_fetched=$((total_fetched + page_count))
        rm "$TEMP_RESPONSE"
        
        if [[ "$page_count" -lt "$per_page" ]]; then
            break
        fi
        
        ((page++))
    done
    
    echo "  Total posts fetched: $total_fetched"
    
    cat > "$output_file" << 'EOF_HTML_START'
<!DOCTYPE html>
<html><head><meta charset="UTF-8"><title>
EOF_HTML_START
    echo "$channel_name - Export</title>" >> "$output_file"
    cat >> "$output_file" << 'EOF_HTML_STYLE'
<style>
body { font-family: Arial, sans-serif; max-width: 800px; margin: 0 auto; padding: 20px; }
.post { border-bottom: 1px solid #ccc; padding: 15px 0; }
.meta { color: #666; font-size: 0.9em; }
.message { white-space: pre-wrap; margin-top: 10px; }
a { color: #0066cc; }
h1 { margin-bottom: 5px; }
.export-date { color: #666; margin-bottom: 20px; }
</style></head><body>
EOF_HTML_STYLE
    echo "<h1>$channel_name</h1>" >> "$output_file"
    echo "<p class=\"export-date\">Exported: $(date)</p>" >> "$output_file"
    echo '<hr>' >> "$output_file"
    
    COUNT_FILE=$(mktemp)
    echo "0" > "$COUNT_FILE"
    
    jq -r '.order | reverse | .[]' "$ALL_POSTS" | while read -r post_id; do
        post_data=$(jq -r --arg pid "$post_id" '.posts[$pid] // empty | select(.message != null and .message != "") | [.create_at, .user_id, (.message | @base64)] | @tsv' "$ALL_POSTS" 2>/dev/null)
        
        if [[ -n "$post_data" ]]; then
            create_at=$(echo "$post_data" | cut -f1)
            user_id=$(echo "$post_data" | cut -f2)
            message_b64=$(echo "$post_data" | cut -f3-)
            message=$(echo "$message_b64" | base64 -d)
            
            username=""
            if [[ -n "$user_id" && "$user_id" != "null" ]]; then
                user_info=$(api "users/$user_id")
                username=$(echo "$user_info" | jq -r '.username // empty')
            fi
            if [[ -z "$username" ]]; then
                username="unknown"
            fi
            
            if [[ -n "$create_at" && "$create_at" != "null" && "$create_at" != "0" ]]; then
                post_date=$(to_readable_date "$create_at")
            else
                post_date="unknown date"
            fi
            
            linked_message=$(linkify "$message")
            
            echo '<div class="post">' >> "$output_file"
            echo "<div class=\"meta\">🗓️ $post_date &nbsp;|&nbsp; 👤 @$username</div>" >> "$output_file"
            echo "<div class=\"message\">$linked_message</div>" >> "$output_file"
            echo '</div>' >> "$output_file"
            
            count=$(<"$COUNT_FILE")
            echo "$((count + 1))" > "$COUNT_FILE"
            
            if [[ $((count % 100)) -eq 0 && $count -gt 0 ]]; then
                echo "    Processed $((count + 1)) posts..."
            fi
        fi
    done
    
    post_count=$(<"$COUNT_FILE")
    
    echo "<p><strong>Total posts exported: $post_count</strong></p>" >> "$output_file"
    echo '</body></html>' >> "$output_file"
    
    rm "$ALL_POSTS" "$COUNT_FILE"
    
    echo "  ✓ Export complete: $output_file"
    echo "  Posts exported: $post_count"
}

# ===========================
# MAIN SCRIPT
# ===========================

echo "Starting batch export from CSV: $CSV_FILE"
echo "Output folder: $OUTPUT_FOLDER"
echo "Datestamp: $DATESTAMP"
echo ""

# Create output folder if it doesn't exist
if [[ ! -d "$OUTPUT_FOLDER" ]]; then
    echo "Creating output folder: $OUTPUT_FOLDER"
    mkdir -p "$OUTPUT_FOLDER"
fi

if [[ ! -f "$CSV_FILE" ]]; then
    echo "ERROR: CSV file not found: $CSV_FILE"
    exit 1
fi

total_channels=$(tail -n +2 "$CSV_FILE" | grep -v '^[[:space:]]*$' | wc -l | tr -d ' ')
echo "Found $total_channels channels to export"
echo ""

current=0

TEMP_CSV=$(mktemp)
tail -n +2 "$CSV_FILE" > "$TEMP_CSV"

while IFS=, read -r team channel_id channel_name display_name rest; do
    # Skip if channel_id (column 2) is empty
    if [[ -z "$channel_id" ]]; then
        continue
    fi
    
    current=$((current + 1))
    
    # Clean up the fields
    channel_id=$(echo "$channel_id" | xargs | tr -d '"')
    display_name=$(echo "$display_name" | xargs | tr -d '"')
    
    # Skip if channel_id is still empty after cleaning
    if [[ -z "$channel_id" ]]; then
        continue
    fi
    
    # Use display_name if available, otherwise use channel_name
    if [[ -z "$display_name" ]]; then
        display_name=$(echo "$channel_name" | xargs | tr -d '"')
    fi
    
    echo "[$current/$total_channels] Processing channel..."
    echo "  Team: $team"
    echo "  Channel ID: $channel_id"
    echo "  Display Name: $display_name"
    
    export_channel "$channel_id" "$display_name"
    
    sleep 1
done < "$TEMP_CSV"

rm "$TEMP_CSV"

echo ""
echo "========================================"
echo "Batch export complete!"
echo "========================================"