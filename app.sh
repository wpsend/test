#!/bin/bash

# ✅ Root Privilege Check
if [ "$(id -u)" -ne 0 ]; then
    echo "⚠️  এই স্ক্রিপ্ট চালাতে root ইউজার হতে হবে!"
    exit 1
fi

# ✅ Variables
TARGET_IP="103.174.152.54"  # লাইসেন্স সার্ভার চায় এই IP
LICENSE_SERVER="https://mirror.resellercenter.ir/pre.sh"  # লাইসেন্স স্ক্রিপ্ট URL
PROXY_PORT=8118

echo "🔍 Checking current public IP..."
VPS_IP=$(curl -s https://api64.ipify.org)  # VPS-এর আসল IP
echo "🌍 Your VPS IP: $VPS_IP"

if [[ "$VPS_IP" == "$TARGET_IP" ]]; then
    echo "✅ আপনার IP ইতিমধ্যে $TARGET_IP! লাইসেন্স কমান্ড চালানো হচ্ছে..."
    bash <( curl -s $LICENSE_SERVER ) cPanel; RcLicenseCP
    exit 0
fi

echo "🔄 IP পরিবর্তনের চেষ্টা চলছে..."

# ✅ Install Required Packages
echo "🔹 Installing required packages..."
if command -v yum &>/dev/null; then
    yum install -y epel-release privoxy dante-server iptables net-tools curl autossh || true
    yum install -y iproute || true  # CloudLinux-এ iproute2 কাজ করে না, তাই iproute ব্যবহার করছি
elif command -v apt &>/dev/null; then
    apt update && apt install -y privoxy dante-server iptables iproute2 net-tools curl autossh
else
    echo "⚠️ Package Manager পাওয়া যায়নি! (Neither yum nor apt)"
    exit 1
fi

# ✅ 1st Attempt: Iptables NAT Spoofing
echo "🔹 Trying to spoof IP using iptables..."
iptables -t nat -A POSTROUTING -j SNAT --to-source $TARGET_IP
sleep 3
NEW_IP=$(curl -s https://api64.ipify.org)
if [[ "$NEW_IP" == "$TARGET_IP" ]]; then
    echo "✅ Spoofing সফল! এখন লাইসেন্স কমান্ড চালানো হচ্ছে..."
    bash <( curl -s $LICENSE_SERVER ) cPanel; RcLicenseCP
    exit 0
else
    echo "❌ Spoofing ব্যর্থ! অন্য পদ্ধতি চেষ্টা করা হচ্ছে..."
    iptables -t nat -D POSTROUTING -j SNAT --to-source $TARGET_IP
fi

# ✅ 2nd Attempt: Proxy Server (Privoxy)
echo "🔹 Trying Proxy Server..."
if [ ! -f "/etc/privoxy/config" ]; then
    echo "Privoxy ইনস্টল হয়নি, নতুনভাবে ইনস্টল করা হচ্ছে..."
    yum install -y privoxy || apt install -y privoxy || true
fi

if [ -f "/etc/privoxy/config" ]; then
    echo "forward-socks5 / $TARGET_IP:1080 ." >> /etc/privoxy/config
    systemctl enable privoxy || true
    systemctl restart privoxy || true
else
    echo "❌ Privoxy ফাইল পাওয়া যায়নি, Proxy Mode স্কিপ করা হচ্ছে..."
fi

export http_proxy="http://127.0.0.1:$PROXY_PORT"
export https_proxy="http://127.0.0.1:$PROXY_PORT"

NEW_IP=$(curl -s --proxy http://127.0.0.1:$PROXY_PORT https://api64.ipify.org)
if [[ "$NEW_IP" == "$TARGET_IP" ]]; then
    echo "✅ Proxy ব্যবহার করে IP পরিবর্তন সফল! লাইসেন্স কমান্ড চালানো হচ্ছে..."
    bash <( curl -s $LICENSE_SERVER ) cPanel; RcLicenseCP
    exit 0
else
    echo "❌ Proxy ব্যবহার করেও ব্যর্থ! SSH Tunnel চেষ্টা করা হচ্ছে..."
fi

# ✅ 3rd Attempt: SSH Tunnel SOCKS5 Proxy
echo "🔹 Trying SSH Tunnel..."
autossh -M 0 -f -N -D 1080 $TARGET_IP || true
sleep 5
export http_proxy="socks5://127.0.0.1:1080"
export https_proxy="socks5://127.0.0.1:1080"

NEW_IP=$(curl -s --proxy socks5://127.0.0.1:1080 https://api64.ipify.org)
if [[ "$NEW_IP" == "$TARGET_IP" ]]; then
    echo "✅ SSH Tunnel সফল! লাইসেন্স কমান্ড চালানো হচ্ছে..."
    bash <( curl -s $LICENSE_SERVER ) cPanel; RcLicenseCP
    exit 0
else
    echo "❌ SSH Tunnel ব্যর্থ!"
fi

echo "❌ সব চেষ্টা ব্যর্থ! আপনার VPS এই IP দিয়ে request পাঠাতে পারছে না।"
exit 1
