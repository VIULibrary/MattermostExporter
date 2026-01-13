# Mattermost Exporter

A bundle of bash scripts to export Mattermost . . . 

1. Mattermost Users `UserExport.sh`
2. Channel IDs `ChannelIDExport.sh`
3. Content from a single channel `SingleChannelExport.sh`
4. All channel content (to HTML files with clickable links, perfect for archiving or viewing in Google Docs.) `AllChannelExport.sh`

## Features (for the AllChannelExport.sh)

- 📦 **Batch export** multiple channels from a CSV file
- 🔗 **Clickable links** in exported HTML (works in Google Docs)
- 📅 **Chronological order** (oldest posts first)
- 👤 **User attribution** with timestamps
- 📄 **Pagination support** for channels with 500+ posts
- 🎨 **Clean HTML formatting** ready for Google Docs import

## Requirements

- Bash shell
- `curl` - for API requests
- `jq` - for JSON parsing
- Mattermost API access with a valid token

## Installation

1. Clone this repository:
```bash
git clone https://github.com/VIULibrary/MattermostExporter.git
cd mattermost-exporter
```

2. Make the scripts executable:
```bash
chmod +x SCRIPT.sh
```

3. Install dependencies (if needed):
```bash
# macOS
brew install jq

# Ubuntu/Debian
sudo apt-get install jq

# CentOS/RHEL
sudo yum install jq
```

## Configuration

Edit the scripts and set these variables as needed

```bash
MM_URL="YOUR_MATTERMOST_URL"              
TOKEN="YOUR_API_TOKEN"              
CSV_FILE="YOUR_CHANNEL_ID_EXPORT.csv"
OUTPUT_FOLDER="YOUR_EXPORT_FOLDER"  
```

### Getting Your MatterMost API Token

1. Log into Mattermost
2. Enable Personal Access Token in **System console** → **Intergration Management**
3. Go to **Account Settings** → **Security** → **Personal Access Tokens**
4. Click **Create Token** 
5. Copy the token and add it to the script(s)

## Usage

1. Set up your configurations in the scripts
2. Generate your `channels.csv` file
3. Run the script(s):

```bash
./SCRIPT.sh
```

For`AllChannelExport.sh` script will:
- Create the output folder if needed
- Process each channel in the CSV
- Show progress for each channel
- Export HTML files named like: `AI_LLM_20260112_132037.html`


## Rate Limiting

Increase the sleep period avoid API rate limits as needed. 

```bash
sleep 2  # Change from 1 to 2 seconds
```

## License

MIT License - feel free to use and modify as needed.

## Contributing

Contributions welcome! Please open an issue or submit a pull request.


