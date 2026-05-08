#!/bin/bash
# Run this script on your VPS as root/sudo
# Replace YOUR_EMAIL with your actual email

EMAIL="your@email.com"
DOMAIN="api.nexaround.com"

# 1. Install Nginx and Certbot
apt update
apt install -y nginx certbot python3-certbot-nginx

# 2. Copy nginx config
cp nginx.conf /etc/nginx/sites-available/nexaround
ln -sf /etc/nginx/sites-available/nexaround /etc/nginx/sites-enabled/nexaround
rm -f /etc/nginx/sites-enabled/default

# 3. Test and reload nginx (HTTP only first, for cert challenge)
sed -i '/ssl_certificate/d; /ssl_dhparam/d; /include.*options-ssl/d; /listen 443/d' /etc/nginx/sites-available/nexaround
nginx -t && systemctl reload nginx

# 4. Get SSL certificate from Let's Encrypt
certbot --nginx -d $DOMAIN --non-interactive --agree-tos -m $EMAIL

# 5. Restore full HTTPS nginx config
cp nginx.conf /etc/nginx/sites-available/nexaround
nginx -t && systemctl reload nginx

# 6. Auto-renew cert (runs twice daily)
systemctl enable certbot.timer

echo "✅ SSL setup complete! https://$DOMAIN should now work."
