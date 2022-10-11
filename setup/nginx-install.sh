#!/usr/bin/env bash
YW=`echo "\033[33m"`
RD=`echo "\033[01;31m"`
BL=`echo "\033[36m"`
GN=`echo "\033[1;92m"`
CL=`echo "\033[m"`
RETRY_NUM=10
RETRY_EVERY=3
NUM=$RETRY_NUM
CM="${GN}✓${CL}"
CROSS="${RD}✗${CL}"
BFR="\\r\\033[K"
HOLD="-"
set -o errexit
set -o errtrace
set -o nounset
set -o pipefail
shopt -s expand_aliases
alias die='EXIT=$? LINE=$LINENO error_exit'
trap die ERR

function error_exit() {
  trap - ERR
  local reason="Unknown failure occurred."
  local msg="${1:-$reason}"
  local flag="${RD}‼ ERROR ${CL}$EXIT@$LINE"
  echo -e "$flag $msg" 1>&2
  exit $EXIT
}

function msg_info() {
    local msg="$1"
    echo -ne " ${HOLD} ${YW}${msg}..."
}

function msg_ok() {
    local msg="$1"
    echo -e "${BFR} ${CM} ${GN}${msg}${CL}"
}

function msg_error() {
    local msg="$1"
    echo -e "${BFR} ${CROSS} ${RD}${msg}${CL}"
}

msg_info "Setting up Container OS "
sed -i "/$LANG/ s/\(^# \)//" /etc/locale.gen
locale-gen >/dev/null
while [ "$(hostname -I)" = "" ]; do
  1>&2 echo -en "${CROSS}${RD} No Network! "
  sleep $RETRY_EVERY
  ((NUM--))
  if [ $NUM -eq 0 ]
  then
    1>&2 echo -e "${CROSS}${RD} No Network After $RETRY_NUM Tries${CL}"    
    exit 1
  fi
done
msg_ok "Set up Container OS"
msg_ok "Network Connected: ${BL}$(hostname -I)"

# if nc -zw1 8.8.8.8 443; then  msg_ok "Internet Connected"; else  msg_error "Internet NOT Connected"; exit 1; fi;
RESOLVEDIP=$(nslookup "github.com" | awk -F':' '/^Address: / { matched = 1 } matched { print $2}' | xargs)
if [[ -z "$RESOLVEDIP" ]]; then msg_error "DNS Lookup Failure";  else msg_ok "DNS Resolved github.com to $RESOLVEDIP";  fi;

msg_info "Updating Container OS"
apt-get update &>/dev/null
apt-get -y upgrade &>/dev/null
msg_ok "Updated Container OS"

msg_info "Installing Dependencies"
apt-get update &>/dev/null
apt-get -y install \
    sudo \
    curl \
    gnupg2 \
    ca-certificates \
	debian-archive-keyring \
    lsb-release  &>/dev/null
msg_ok "Installed Dependencies"

msg_info "Importing official nginx signing key"
# Import an official nginx signing key so apt could verify the packages authenticity. Fetch the key:
curl https://nginx.org/keys/nginx_signing.key | gpg --dearmor \
    | sudo tee /usr/share/keyrings/nginx-archive-keyring.gpg &>/dev/null
msg_ok "Imported official nginx signing key"

# Verify that the downloaded file contains the proper key:
gpg --dry-run --quiet --no-keyring --import --import-options import-show /usr/share/keyrings/nginx-archive-keyring.gpg

echo "Key should be:"
echo "pub   rsa2048 2011-08-19 [SC] [expires: 2024-06-14]"
echo "      573BFD6B3D8FBC641079A6ABABF5BD827BD9BF62"
echo "uid                      nginx signing key <signing-key@nginx.com>"

msg_info "Setup repository for nginx packages"
echo "deb [signed-by=/usr/share/keyrings/nginx-archive-keyring.gpg] \
http://nginx.org/packages/debian `lsb_release -cs` nginx" \
    | sudo tee /etc/apt/sources.list.d/nginx.list &>/dev/null
	
# If you would like to use mainline nginx packages, run the following command instead:
# echo "deb [signed-by=/usr/share/keyrings/nginx-archive-keyring.gpg] \
# http://nginx.org/packages/mainline/debian `lsb_release -cs` nginx" \
    # | sudo tee /etc/apt/sources.list.d/nginx.list
	
# Set up repository pinning to prefer our packages over distribution-provided ones
echo -e "Package: *\nPin: origin nginx.org\nPin: release o=nginx\nPin-Priority: 900\n" \
    | sudo tee /etc/apt/preferences.d/99nginx &>/dev/null
msg_ok "Repository for nginx packages added"

msg_info "Installing nginx"
sudo apt update &>/dev/null
sudo apt install nginx &>/dev/null
msg_ok "Installed nginx"

msg_info "Cleaning up"
apt-get autoremove >/dev/null
apt-get autoclean >/dev/null
msg_ok "Cleaned"
