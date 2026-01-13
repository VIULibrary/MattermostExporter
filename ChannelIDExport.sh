#!/bin/bash

# ===========================
# CONFIG
# ===========================
MM_URL="YOUR_MATTERMOST_URL"              
TOKEN="YOUR_API_TOKEN"    
OUTPUT_FILE="channels.csv"


api() {
    curl -s -H "Authorization: Bearer $TOKEN" "$MM_URL/api/v4/$1"
}

# macOS timestamp converter (ms → ISO)
to_iso8601() {
    ms=$1
    if [[ -z "$ms" || "$ms" == "0" ]]; then
        echo ""
        return
    fi
    sec=$((ms / 1000))
    date -u -r "$sec" +"%Y-%m-%dT%H:%M:%SZ"
}

# CSV header
echo "team_name,channel_id,channel_name,display_name,channel_type,purpose,archived,create_date,last_post_date,member_count,total_post_count" \
    > "$OUTPUT_FILE"

# Get all teams and store in a temporary file
teams_file=$(mktemp)
api "teams" | jq -c '.[]' > "$teams_file"

# Get ALL channels globally (this includes private channels with proper team_id)
channels=$(api "channels?per_page=1000&include_deleted=true")

echo "$channels" | jq -c '.[]' | while read -r channel; do
    channel_id=$(echo "$channel" | jq -r '.id')
    team_id=$(echo "$channel" | jq -r '.team_id')
    
    # Skip if no team_id (direct messages)
    if [[ "$team_id" == "null" || -z "$team_id" ]]; then
        continue
    fi
    
    # Look up team name from the teams file (handle team IDs with leading zeros properly)
    team_name=$(cat "$teams_file" | jq -r --arg team_id "$team_id" 'select(.id == $team_id) | .display_name')
    
    # Skip if team not found
    if [[ -z "$team_name" ]]; then
        continue
    fi

    echo "Processing channel: $channel_id in team: $team_name"

    # Get full channel metadata
    full=$(api "channels/$channel_id")

    channel_name=$(echo "$full" | jq -r '.name')
    display_name=$(echo "$full" | jq -r '.display_name')
    channel_type=$(echo "$full" | jq -r '.type')     # O, P, G, D
    purpose=$(echo "$full" | jq -r '.purpose')
    delete_at=$(echo "$full" | jq -r '.delete_at')
    create_at=$(echo "$full" | jq -r '.create_at')
    last_post_at=$(echo "$full" | jq -r '.last_post_at')
    total_post_count=$(echo "$full" | jq -r '.total_msg_count')

    # Convert timestamps via macOS-compatible function
    create_date=$(to_iso8601 "$create_at")
    last_post_date=$(to_iso8601 "$last_post_at")

    # Archived?
    archived=$([[ "$delete_at" != "0" ]] && echo "true" || echo "false")

    # Member count
    member_count=$(api "channels/$channel_id/stats" | jq -r '.member_count')

    # Escape quotes in purpose
    purpose_escaped=$(echo "$purpose" | sed 's/"/""/g')

    echo "\"$team_name\",\"$channel_id\",\"$channel_name\",\"$display_name\",\"$channel_type\",\"$purpose_escaped\",\"$archived\",\"$create_date\",\"$last_post_date\",\"$member_count\",\"$total_post_count\"" \
        >> "$OUTPUT_FILE"
done

# Clean up
rm -f "$teams_file"

echo "Export complete: $OUTPUT_FILE"