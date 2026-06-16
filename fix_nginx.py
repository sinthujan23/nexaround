content = """server {
    server_name api.nexaround.com;

    location / {
        proxy_pass http://127.0.0.1:8010;

        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;

        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
    }

    listen 443 ssl; # managed by Certbot
    ssl_certificate /etc/letsencrypt/live/api.nexaround.com/fullchain.pem; # managed by Certbot
    ssl_certificate_key /etc/letsencrypt/live/api.nexaround.com/privkey.pem; # managed by Certbot
    include /etc/letsencrypt/options-ssl-nginx.conf; # managed by Certbot
    ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem; # managed by Certbot
}

server {
    server_name admin.nexaround.com;

    location / {
        proxy_pass http://127.0.0.1:8020;

        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    listen 443 ssl; # managed by Certbot
    ssl_certificate /etc/letsencrypt/live/api.nexaround.com/fullchain.pem; # managed by Certbot
    ssl_certificate_key /etc/letsencrypt/live/api.nexaround.com/privkey.pem; # managed by Certbot
    include /etc/letsencrypt/options-ssl-nginx.conf; # managed by Certbot
    ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem; # managed by Certbot
}

server {
    listen 80;
    server_name nexaround.com www.nexaround.com;

    root /var/www/nexaround/nexaround_landing/dist;
    index index.html;

    location / {
        try_files $uri $uri/ /index.html;
    }
}

server {
    if ($host = admin.nexaround.com) {
        return 301 https://$host$request_uri;
    }
    if ($host = api.nexaround.com) {
        return 301 https://$host$request_uri;
    } # managed by Certbot

    listen 80;
    server_name api.nexaround.com admin.nexaround.com;
    return 404; # managed by Certbot
}
"""
with open("/etc/nginx/sites-available/nexaround", "w") as f:
    f.write(content)
