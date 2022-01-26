#!/bin/bash

:<<DOC
Script for testing Jamf API endpoints using curl

Actions:
- Checks if we already have a token
- Grabs a new token if required using basic auth
- Works out the Jamf Pro version
- Performs a GET request on a supplied package object using the bearer token
- Uploads a package using the bearer token
- If that fails, uploads a package using basic auth
DOC

usage() {
    echo "Usage: api_tests.sh --jss someserver --user username --pass password --pkg /path/to/pkg.pkg --id 30"
    echo "(don't include https:// or .jamfcloud.com)"
}

get_token() {
    # request the token
    curl --request POST \
        --silent \
        --header "authorization: Basic $credentials" \
        --url "$url/api/v1/auth/token" \
        --header 'Accept: application/json' \
        -o "$token_file"
}

while test $# -gt 0 ; do
    case "$1" in
        -s|--jss)
            shift
            jss="$1"
            ;;
        -u|--user)
            shift
            user="$1"
            ;;
        -p|--pass)
            shift
            pass="$1"
            ;;
        -f|--pkg)
            shift
            pkg_path="$1"
            ;;
        -i|--id)
            shift
            pkg_id="$1"
            ;;
        *)
            usage
            exit
            ;;
    esac
    shift
done

if [[ ! $jss || ! $user || ! $pass || ! $pkg_path || ! $pkg_id ]]; then
    usage
    exit
fi

temp_file="/tmp/api_tests.txt"
token_file="/tmp/api_token.txt"

url="https://$jss.jamfcloud.com"

# generate a b64 hash of the credentials
credentials=$(printf "%s" "$user:$pass" | iconv -t ISO-8859-1 | base64 -i -)

if [[ -f "$token_file" ]]; then
    token=$(plutil -extract token raw "$token_file")
    expires=$(plutil -extract expires raw "$token_file")

    now=$(date -u +"%Y-%m-%dT%H:%M:%S")
    echo
    if [[ $expires < $now ]]; then
        echo "token expired or invalid ($expires v $now). Grabbing a new one"
        get_token
    else
        echo "Existing token still valid"
    fi
else
    echo "No token found. Grabbing a new one"
    get_token
fi

token=$(plutil -extract token raw "$token_file")
# expires=$(plutil -extract expires raw "$token_file")

# echo
# echo "Token = $token"
# echo
# echo "Expires = $expires"

# get the Jamf Pro version
curl --request GET \
    --silent \
    --header "authorization: Bearer $token" \
    --url "$url/api/v1/jamf-pro-version" \
    --header 'Accept: application/json' \
    -o "$temp_file"

jss_version_raw=$(plutil -extract version raw "$temp_file")

rm "$temp_file"

# remove timestamp from Jamf Pro version
jss_version="${jss_version_raw%%"-t"*}"

echo
echo "Jamf Pro Version = $jss_version"

# split the version string into an array of major, minor and patch version
IFS=.
read -ra version_array <<<"$jss_version"
IFS=''

echo
# echo "Major version = ${version_array[0]}"
# echo "Minor version = ${version_array[1]}"
# echo "Patch version = ${version_array[2]}"

if [[ ${version_array[0]} -lt 10 || (${version_array[0]} -eq 10 && ${version_array[1]} -lt 35) ]]; then
    echo "Basic auth required for the Classic API of Jamf Pro < 10.35"
    exit 
else
    echo "Token based auth is possible for the Classic API of Jamf Pro >= 10.35"
fi

# now perform a get request on an existing package
echo "Getting a package from the server (ID must exist!)"
curl --request GET \
    --silent \
    --header "authorization: Bearer $token" \
    --header 'Accept: application/xml' \
    "$url/JSSResource/packages/id/$pkg_id" \
    | xmllint --format - > "$temp_file"

echo
cat "$temp_file"
echo

rm "$temp_file"

# now try to post a package with a bearer token
echo 


pkg=$(basename "$pkg_path")
http_response=$(
    curl --request POST \
        --header "authorization: Bearer $token" \
        --header 'Accept: application/xml' \
        --header 'DESTINATION: 0' \
        --header 'OBJECT_ID: -1' \
        --header 'FILE_TYPE: 0' \
        --header 'FILE_NAME: '"$pkg"'' \
        --upload-file "$pkg_path" \
        -i \
        --output /tmp/jamf_upload/curl_output_from_api_tests.txt \
        --write-out %{http_code} \
        "$url/dbfileupload"
)

echo
echo "HTTP response: $http_response"

if [[ $http_response -gt 350 ]]; then
    sleep 2
    echo
    echo "Posting failed. Trying with basic authentication instead"
    http_response=$(
        curl --request POST \
            --header "authorization: Basic $credentials" \
            --header 'Accept: application/xml' \
            --header 'DESTINATION: 0' \
            --header 'OBJECT_ID: -1' \
            --header 'FILE_TYPE: 0' \
            --header 'FILE_NAME: '"$pkg"'' \
            --upload-file "$pkg_path" \
            -i -o /dev/null \
            --write-out %{http_code} \
            "$url/dbfileupload"
    )

    echo
    echo "HTTP response: $http_response"
fi