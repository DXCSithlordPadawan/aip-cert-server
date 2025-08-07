#!/bin/bash
##########################################################
# Certificate Request Client Script
##########################################################
# This script allows remote servers to request certificates
# from the Certificate Authority API
##########################################################
# Usage: ./request-cert.sh [options]
# Author: Iain Reid / Assistant
# Created: 2025-08-06
##########################################################

# Default configuration
CA_SERVER="https://cert-server.aip.dxc.com"
API_KEY="changeme-secure-api-key-here"
CONFIG_FILE="/etc/ssl/ca-client.conf"
CERT_DIR="/etc/ssl/certs"
KEY_DIR="/etc/ssl/private"
VERBOSE=0

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print usage
usage() {
    echo "Usage: $0 [OPTIONS] COMMAND"
    echo ""
    echo "Commands:"
    echo "  request           Request a new certificate"
    echo "  submit-csr        Submit existing CSR"
    echo "  download          Download certificate files"
    echo "  status            Check request status"
    echo "  download-ca       Download CA certificates"
    echo ""
    echo "Options:"
    echo "  -s, --server URL       CA server URL (default: $CA_SERVER)"
    echo "  -k, --api-key KEY      API key for authentication"
    echo "  -c, --config FILE      Configuration file (default: $CONFIG_FILE)"
    echo "  -o, --output DIR       Output directory for certificates"
    echo "  -v, --verbose          Verbose output"
    echo "  -h, --help            Show this help"
    echo ""
    echo "Certificate Request Options:"
    echo "  --common-name CN       Common name (required)"
    echo "  --organization ORG     Organization (default: DXC Technology)"
    echo "  --org-unit OU          Organizational unit"
    echo "  --country CC           Country code (default: GB)"
    echo "  --state STATE          State/Province (default: Hampshire)"
    echo "  --locality CITY        Locality/City (default: Farnborough)"
    echo "  --email EMAIL          Email address (required)"
    echo "  --san NAMES            Subject Alternative Names (comma-separated)"
    echo "  --type TYPE            Certificate type: server, client, code_signing"
    echo "  --key-type TYPE        Key type: ecdsa, rsa (default: ecdsa)"
    echo ""
    echo "Examples:"
    echo "  $0 request --common-name web.example.com --email admin@example.com"
    echo "  $0 submit-csr --csr-file /path/to/request.csr"
    echo "  $0 download --serial 1A2B3C4D5E --output /etc/ssl"
    echo "  $0 download-ca --output /usr/local/share/ca-certificates"
}

# Function for verbose logging
log() {
    if [ $VERBOSE -eq 1 ]; then
        echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}" >&2
    fi
}

# Function for success messages
success() {
    echo -e "${GREEN}✓ $1${NC}"
}

# Function for error messages
error() {
    echo -e "${RED}✗ Error: $1${NC}" >&2
}

# Function for warning messages
warn() {
    echo -e "${YELLOW}⚠ Warning: $1${NC}" >&2
}

# Function to load configuration file
load_config() {
    if [ -f "$CONFIG_FILE" ]; then
        log "Loading configuration from $CONFIG_FILE"
        source "$CONFIG_FILE"
    fi
}

# Function to make API requests
api_request() {
    local method=$1
    local endpoint=$2
    local data=$3
    local output_file=$4
    
    local url="${CA_SERVER}/api.php${endpoint}"
    local temp_response=$(mktemp)
    
    log "Making $method request to $url"
    
    local curl_args=(
        -s -S
        -X "$method"
        -H "X-API-Key: $API_KEY"
        -H "Content-Type: application/json"
        -w "HTTPSTATUS:%{http_code}"
        -o "$temp_response"
    )
    
    if [ -n "$data" ]; then
        curl_args+=(-d "$data")
    fi
    
    local response
    response=$(curl "${curl_args[@]}" "$url")
    local http_code=$(echo "$response" | grep -o 'HTTPSTATUS:[0-9]*' | cut -d: -f2)
    
    log "HTTP Status: $http_code"
    
    if [ "$http_code" -ge 200 ] && [ "$http_code" -lt 300 ]; then
        if [ -n "$output_file" ]; then
            mv "$temp_response" "$output_file"
        else
            cat "$temp_response"
        fi
        rm -f "$temp_response"
        return 0
    else
        error "API request failed with status $http_code"
        if [ -f "$temp_response" ]; then
            cat "$temp_response" >&2
        fi
        rm -f "$temp_response"
        return 1
    fi
}

# Function to download and save file from API response
download_file_from_response() {
    local response_file=$1
    local output_dir=$2
    
    local success=$(jq -r '.success' < "$response_file" 2>/dev/null)
    
    if [ "$success" != "true" ]; then
        error "API response indicates failure"
        cat "$response_file" >&2
        return 1
    fi
    
    local filename=$(jq -r '.filename' < "$response_file" 2>/dev/null)
    local content=$(jq -r '.content' < "$response_file" 2>/dev/null)
    
    if [ "$filename" = "null" ] || [ "$content" = "null" ]; then
        error "Invalid response format"
        return 1
    fi
    
    local output_path="$output_dir/$filename"
    
    # Ensure output directory exists
    mkdir -p "$output_dir"
    
    # Decode and save file
    echo "$content" | base64 -d > "$output_path"
    
    if [ $? -eq 0 ]; then
        success "Downloaded: $output_path"
        
        # Set appropriate permissions
        if [[ "$filename" == *.key ]]; then
            chmod 600 "$output_path"
        else
            chmod 644 "$output_path"
        fi
        
        return 0
    else
        error "Failed to decode and save file: $output_path"
        return 1
    fi
}

# Function to request a new certificate
request_certificate() {
    log "Requesting new certificate"
    
    # Validate required parameters
    if [ -z "$COMMON_NAME" ]; then
        error "Common name is required (--common-name)"
        return 1
    fi
    
    if [ -z "$EMAIL" ]; then
        error "Email address is required (--email)"
        return 1
    fi
    
    # Build JSON payload
    local json_data
    json_data=$(jq -n \
        --arg common_name "$COMMON_NAME" \
        --arg organization "${ORGANIZATION:-DXC Technology}" \
        --arg org_unit "${ORG_UNIT:-EntServ D S}" \
        --arg country "${COUNTRY:-GB}" \
        --arg state "${STATE:-Hampshire}" \
        --arg locality "${LOCALITY:-Farnborough}" \
        --arg email "$EMAIL" \
        --arg san "${SAN:-}" \
        --arg cert_type "${CERT_TYPE:-server}" \
        --arg key_type "${KEY_TYPE:-ecdsa}" \
        '{
            common_name: $common_name,
            organization: $organization,
            org_unit: $org_unit,
            country: $country,
            state: $state,
            locality: $locality,
            email: $email,
            san: $san,
            cert_type: $cert_type,
            key_type: $key_type
        }')
    
    local response_file=$(mktemp)
    
    if api_request "POST" "/submit" "$json_data" "$response_file"; then
        local success=$(jq -r '.success' < "$response_file" 2>/dev/null)
        local message=$(jq -r '.message' < "$response_file" 2>/dev/null)
        local request_id=$(jq -r '.request_id' < "$response_file" 2>/dev/null)
        local auto_approved=$(jq -r '.auto_approved' < "$response_file" 2>/dev/null)
        local serial=$(jq -r '.serial' < "$response_file" 2>/dev/null)
        
        if [ "$success" = "true" ]; then
            success "$message"
            
            if [ "$request_id" != "null" ]; then
                echo "Request ID: $request_id"
            fi
            
            if [ "$auto_approved" = "true" ] && [ "$serial" != "null" ]; then
                success "Certificate automatically approved with serial: $serial"
                
                # Download certificate files
                if [ -n "$OUTPUT_DIR" ]; then
                    echo "Downloading certificate files..."
                    download_certificate_files "$serial" "$OUTPUT_DIR"
                fi
            fi
        else
            error "$message"
            rm -f "$response_file"
            return 1
        fi
    else
        rm -f "$response_file"
        return 1
    fi
    
    rm -f "$response_file"
    return 0
}

# Function to submit existing CSR
submit_csr() {
    log "Submitting existing CSR"
    
    if [ -z "$CSR_FILE" ] || [ ! -f "$CSR_FILE" ]; then
        error "CSR file not found: $CSR_FILE"
        return 1
    fi
    
    local csr_content
    csr_content=$(cat "$CSR_FILE")
    
    local json_data
    json_data=$(jq -n \
        --arg csr_pem "$csr_content" \
        --arg cert_type "${CERT_TYPE:-server}" \
        '{
            csr_pem: $csr_pem,
            cert_type: $cert_type
        }')
    
    local response_file=$(mktemp)
    
    if api_request "POST" "/submit-csr" "$json_data" "$response_file"; then
        local success=$(jq -r '.success' < "$response_file" 2>/dev/null)
        local message=$(jq -r '.message' < "$response_file" 2>/dev/null)
        local serial=$(jq -r '.serial' < "$response_file" 2>/dev/null)
        
        if [ "$success" = "true" ]; then
            success "$message"
            
            if [ "$serial" != "null" ]; then
                echo "Certificate serial: $serial"
                
                # Download certificate files
                if [ -n "$OUTPUT_DIR" ]; then
                    echo "Downloading certificate files..."
                    download_certificate_files "$serial" "$OUTPUT_DIR" "no-key"
                fi
            fi
        else
            error "$message"
        fi
    fi
    
    rm -f "$response_file"
}

# Function to download certificate files
download_certificate_files() {
    local serial=$1
    local output_dir=$2
    local skip_key=$3
    
    local types=("cert" "chain")
    
    if [ "$skip_key" != "no-key" ]; then
        types+=("key")
    fi
    
    for type in "${types[@]}"; do
        log "Downloading $type for serial $serial"
        
        local response_file=$(mktemp)
        
        if api_request "GET" "/download?type=$type&serial=$serial" "" "$response_file"; then
            download_file_from_response "$response_file" "$output_dir"
        fi
        
        rm -f "$response_file"
    done
}

# Function to download CA certificates
download_ca_certs() {
    log "Downloading CA certificates"
    
    local types=("root-ca" "intermediate-ca" "ca-chain")
    
    for type in "${types[@]}"; do
        log "Downloading $type"
        
        local response_file=$(mktemp)
        
        if api_request "GET" "/download?type=$type" "" "$response_file"; then
            download_file_from_response "$response_file" "$OUTPUT_DIR"
        fi
        
        rm -f "$response_file"
    done
}

# Function to check request status
check_status() {
    if [ -z "$REQUEST_ID" ]; then
        error "Request ID is required (--request-id)"
        return 1
    fi
    
    log "Checking status for request: $REQUEST_ID"
    
    local response_file=$(mktemp)
    
    if api_request "GET" "/status?request_id=$REQUEST_ID" "" "$response_file"; then
        local success=$(jq -r '.success' < "$response_file" 2>/dev/null)
        
        if [ "$success" = "true" ]; then
            echo "Request Status:"
            jq -r '.request | to_entries[] | "\(.key): \(.value)"' < "$response_file"
        else
            local error_msg=$(jq -r '.error' < "$response_file" 2>/dev/null)
            error "$error_msg"
        fi
    fi
    
    rm -f "$response_file"
}

# Parse command line arguments
COMMAND=""
while [[ $# -gt 0 ]]; do
    case $1 in
        -s|--server)
            CA_SERVER="$2"
            shift 2
            ;;
        -k|--api-key)
            API_KEY="$2"
            shift 2
            ;;
        -c|--config)
            CONFIG_FILE="$2"
            shift 2
            ;;
        -o|--output)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        -v|--verbose)
            VERBOSE=1
            shift
            ;;
        --common-name)
            COMMON_NAME="$2"
            shift 2
            ;;
        --organization)
            ORGANIZATION="$2"
            shift 2
            ;;
        --org-unit)
            ORG_UNIT="$2"
            shift 2
            ;;
        --country)
            COUNTRY="$2"
            shift 2
            ;;
        --state)
            STATE="$2"
            shift 2
            ;;
        --locality)
            LOCALITY="$2"
            shift 2
            ;;
        --email)
            EMAIL="$2"
            shift 2
            ;;
        --san)
            SAN="$2"
            shift 2
            ;;
        --type)
            CERT_TYPE="$2"
            shift 2
            ;;
        --key-type)
            KEY_TYPE="$2"
            shift 2
            ;;
        --csr-file)
            CSR_FILE="$2"
            shift 2
            ;;
        --serial)
            SERIAL="$2"
            shift 2
            ;;
        --request-id)
            REQUEST_ID="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        request|submit-csr|download|status|download-ca)
            COMMAND="$1"
            shift
            ;;
        *)
            error "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Load configuration if it exists
load_config

# Validate command
if [ -z "$COMMAND" ]; then
    error "No command specified"
    usage
    exit 1
fi

# Check dependencies
if ! command -v curl >/dev/null 2>&1; then
    error "curl is required but not installed"
    exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
    error "jq is required but not installed"
    exit 1
fi

# Execute command
case $COMMAND in
    request)
        request_certificate
        ;;
    submit-csr)
        submit_csr
        ;;
    download)
        if [ -z "$SERIAL" ]; then
            error "Serial number is required for download (--serial)"
            exit 1
        fi
        if [ -z "$OUTPUT_DIR" ]; then
            OUTPUT_DIR="."
        fi
        download_certificate_files "$SERIAL" "$OUTPUT_DIR"
        ;;
    status)
        check_status
        ;;
    download-ca)
        if [ -z "$OUTPUT_DIR" ]; then
            OUTPUT_DIR="."
        fi
        download_ca_certs
        ;;
    *)
        error "Unknown command: $COMMAND"
        usage
        exit 1
        ;;
esac