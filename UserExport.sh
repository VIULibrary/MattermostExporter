#!/bin/bash


# ===========================
# CONFIG
# ===========================
MM_URL="YOUR_MATTERMOST_URL"              
TOKEN="YOUR_API_TOKEN"    
OUTPUT_FILE="users_export.csv"


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
echo "id,username,email,first_name,last_name,nickname,create_date,last_activity_date,last_login_date,delete_date,roles,locale,timezone,position,status,auth_service,auth_data" > "$OUTPUT_FILE"

# Get all users with pagination
page=0
per_page=200
total_users=0

while true; do
    echo "Fetching page $page..."
    
    # Remove sort parameter or use a valid one
    response=$(api "users?page=$page&per_page=$per_page")
    
    # Check if response is valid JSON and not an error
    if ! echo "$response" | jq -e . >/dev/null 2>&1; then
        echo "Error: Invalid JSON response from API"
        echo "Response: $response"
        break
    fi
    
    # Check if for API error
    if echo "$response" | jq -e '.id' >/dev/null 2>&1 && echo "$response" | jq -r '.id' | grep -q "api"; then
        echo "API Error: $(echo "$response" | jq -r '.message')"
        break
    fi
    
    # Check for users
    user_count=$(echo "$response" | jq length 2>/dev/null || echo "0")
    if [[ "$user_count" -eq 0 ]]; then
        echo "No more users found."
        break
    fi
    
    echo "Processing $user_count users..."
    
    echo "$response" | jq -c '.[]' | while read -r user; do
        # Check if it's a valid user object
        if [[ -z "$user" || "$user" == "null" ]]; then
            continue
        fi
        
        user_id=$(echo "$user" | jq -r '.id // ""')
        username=$(echo "$user" | jq -r '.username // ""')
        email=$(echo "$user" | jq -r '.email // ""')
        first_name=$(echo "$user" | jq -r '.first_name // ""')
        last_name=$(echo "$user" | jq -r '.last_name // ""')
        nickname=$(echo "$user" | jq -r '.nickname // ""')
        create_at=$(echo "$user" | jq -r '.create_at // "0"')
        last_activity_at=$(echo "$user" | jq -r '.last_activity_at // "0"')
        last_login_at=$(echo "$user" | jq -r '.last_login_at // "0"')
        delete_at=$(echo "$user" | jq -r '.delete_at // "0"')
        roles=$(echo "$user" | jq -r '.roles // ""')
        locale=$(echo "$user" | jq -r '.locale // ""')
        timezone=$(echo "$user" | jq -r '.timezone // ""')
        position=$(echo "$user" | jq -r '.position // ""')
        status=$(echo "$user" | jq -r '.status // ""')
        auth_service=$(echo "$user" | jq -r '.auth_service // ""')
        auth_data=$(echo "$user" | jq -r '.auth_data // ""')

        # Skip if no user ID (invalid user object)
        if [[ -z "$user_id" ]]; then
            continue
        fi

        # Convert timestamps
        create_date=$(to_iso8601 "$create_at")
        last_activity_date=$(to_iso8601 "$last_activity_at")
        last_login_date=$(to_iso8601 "$last_login_at")
        delete_date=$(to_iso8601 "$delete_at")

        # Escape fields . . . 
        email_escaped=$(echo "$email" | sed 's/"/""/g')
        first_name_escaped=$(echo "$first_name" | sed 's/"/""/g')
        last_name_escaped=$(echo "$last_name" | sed 's/"/""/g')
        nickname_escaped=$(echo "$nickname" | sed 's/"/""/g')
        position_escaped=$(echo "$position" | sed 's/"/""/g')
        roles_escaped=$(echo "$roles" | sed 's/"/""/g')

        echo "\"$user_id\",\"$username\",\"$email_escaped\",\"$first_name_escaped\",\"$last_name_escaped\",\"$nickname_escaped\",\"$create_date\",\"$last_activity_date\",\"$last_login_date\",\"$delete_date\",\"$roles_escaped\",\"$locale\",\"$timezone\",\"$position_escaped\",\"$status\",\"$auth_service\",\"$auth_data\"" >> "$OUTPUT_FILE"
    done
    
    total_users=$((total_users + user_count))
    ((page++))
done

echo "User export complete: $OUTPUT_FILE"
echo "Total users exported: $total_users"