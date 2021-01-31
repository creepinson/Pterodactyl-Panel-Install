#!/bin/bash
################################################################################
# Author:   crombiecrunch
# Credit:   appleboy ( appleboy.tw AT gmail.com)
# Web:      www.my4x4.club
#
# Program:
#   Install Pterodactyl-Panel on Ubuntu
#
################################################################################


clear
# get sever os name: ubuntu or centos
server_name=`lsb_release -ds | awk -F ' ' '{printf $1}' | tr A-Z a-z`
version_name=`lsb_release -cs`
usage() {
  echo 'Usage: '$0' [-i|--install] [nginx] [apache]'
  exit 1;
}

output() {
    printf "\E[0;33;40m"
    echo $1
    printf "\E[0m"
}

displayErr() {
    echo
    echo $1;
    echo
    exit 1;
}
    # get user input
server_setup() {
    clear
    output "Hope you enjoy this install script created by http://www.my4x4.club. Please enter the information below. "
    read -p "Enter admin email (e.g. admin@example.com) : " EMAIL
    read -p "Enter servername (e.g. portal.example.com) : " SERVNAME
    read -p "Enter time zone (e.g. America/New_York) : " TIME
    read -p "Portal password : " PORTALPASS
}

initial() {
    output "Updating all packages"
    # update package and upgrade Ubuntu
    sudo apt-get -y update 
    sudo apt -y upgrade
    sudo apt -y autoremove
    whoami=`whoami`
}

install_nginx() {
    output "Installing Nginx server."
    sudo apt -y install nginx
    sudo service nginx start
    sudo service cron start
}

install_apache() {
    output "Installing Apache server."
    sudo apt -y install apache2
    sudo service apache2 start
    sudo service cron start
}

install_mariadb() {
    output "Installing Mariadb Server."
    # create random password
    rootpasswd=$(openssl rand -base64 12)
    export DEBIAN_FRONTEND="noninteractive"
    sudo apt -y install mariadb-server
    
    # adding user to group, creating dir structure, setting permissions
    sudo mkdir -p /var/www/pterodactyl/html
    sudo chown -R $whoami:$whoami /var/www/pterodactyl/html
    sudo chmod -R 775 /var/www/pterodactyl/html
}

install_dependencies() {
    output "Installing PHP and Dependencies."
    sudo apt -y install php7.4 php7.4-cli php7.4-gd php7.4-mysql php7.4-common php7.4-mbstring php7.4-tokenizer php7.4-bcmath php7.4-xml php7.4-fpm php7.4-curl
}

install_timezone() {

}

server() {
    output "Installing Server Packages."
    # installing more server files
    sudo apt -y install curl tar unzip git python3-pip
    pip3 install --upgrade pip
    sudo apt -y install supervisor
    sudo aptitude -y install make g++ python-minimal gcc libssl-dev
}

pterodactyl() {
    output "Install Pterodactyl-Panel."
    # Installing the Panel
    cd /var/www/pterodactyl/html
    curl -Lo panel.tar.gz https://github.com/pterodactyl/panel/releases/download/v1.2.2/panel.tar.gz
    tar --strip-components=1 -xzvf panel.tar.gz
    sudo chmod -R 777 storage/* bootstrap/cache
    curl -sS https://getcomposer.org/installer | sudo php -- --install-dir=/usr/local/bin --filename=composer
    composer setup
    # create mysql structure
    # create database
    password=`cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1`  
    Q1="CREATE DATABASE IF NOT EXISTS pterodactyl;"
    Q2="GRANT ALL ON *.* TO 'panel'@'localhost' IDENTIFIED BY '$password';"
    Q3="FLUSH PRIVILEGES;"
    SQL="${Q1}${Q2}${Q3}"
    
    sudo mysql -u root -p="" -e "$SQL"

    output "Database 'pterodactyl' and user 'panel' created with password $password"
}
pterodactyl_1() {
     clear
     output "Environment Setup"
     php artisan pterodactyl:env --dbhost=localhost --dbport=3306 --dbname=pterodactyl --dbuser=panel --dbpass=$password --url=http://$SERVNAME --timezone=$TIME
     output "Mail Setup"
     # php artisan pterodactyl:mail 
     output "Database Setup"
     php artisan migrate --force
     output "Seeding the database"
     php artisan db:seed --force
     output "Create First User"
     php artisan pterodactyl:user --email="$EMAIL" --password=$PORTALPASS --admin=1
     sudo service cron restart
     sudo service supervisor start
     

   output "Creating config files"
sudo bash -c 'cat > /etc/supervisor/conf.d/pterodactyl-worker.conf' <<-'EOF'
[program:pterodactyl-worker]
process_name=%(program_name)s_%(process_num)02d
command=php /var/www/pterodactyl/html/artisan queue:work database --queue=high,standard,low --sleep=3 --tries=3
autostart=true
autorestart=true
user=www-data
numprocs=2
redirect_stderr=true
stdout_logfile=/var/www/pterodactyl/html/storage/logs/queue-worker.log
EOF
    output "Updating Supervisor"
    sudo supervisorctl reread
    sudo supervisorctl update
    sudo supervisorctl start pterodactyl-worker:*
    sudo systemctl enable supervisor.service
}

pterodactyl_niginx() {
    output "Creating webserver initial config file"
echo '
    server {
        listen 80;
        listen [::]:80;
        server_name '"${SERVNAME}"';
    
        root "/var/www/pterodactyl/html/public";
        index index.html index.htm index.php;
        charset utf-8;
    
        location / {
            try_files $uri $uri/ /index.php?$query_string;
        }
    
        location = /favicon.ico { access_log off; log_not_found off; }
        location = /robots.txt  { access_log off; log_not_found off; }
    
        access_log off;
        error_log  /var/log/nginx/pterodactyl.app-error.log error;
    
        # allow larger file uploads and longer script runtimes
            client_max_body_size 100m;
        client_body_timeout 120s;
    
        sendfile off;
    
        location ~ \.php$ {
            fastcgi_split_path_info ^(.+\.php)(/.+)$;
            fastcgi_pass unix:/var/run/php/php7.0-fpm.sock;
            fastcgi_index index.php;
            include fastcgi_params;
            fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
            fastcgi_intercept_errors off;
            fastcgi_buffer_size 16k;
            fastcgi_buffers 4 16k;
            fastcgi_connect_timeout 300;
            fastcgi_send_timeout 300;
            fastcgi_read_timeout 300;
        }
    
        location ~ /\.ht {
            deny all;
        }
        location ~ /.well-known {
            allow all;
        }
    }
' | sudo -E tee /etc/nginx/sites-available/pterodactyl.conf >/dev/null 2>&1

    sudo ln -s /etc/nginx/sites-available/pterodactyl.conf /etc/nginx/sites-enabled/pterodactyl.conf
    output "Install LetsEncrypt and setting SSL"
    sudo service nginx restart
    sudo apt -y install certbot python3-certbot-nginx
    sudo certbot certonly -a webroot --webroot-path=/var/www/pterodactyl/html/public --email "$EMAIL" --agree-tos -d "$SERVNAME"
    sudo rm /etc/nginx/sites-available/pterodactyl.conf
    sudo openssl dhparam -out /etc/ssl/certs/dhparam.pem 2048
    echo '
        server {
            listen 80;
            listen [::]:80;
            server_name '"${SERVNAME}"';
            # enforce https
            return 301 https://$server_name$request_uri;
        }
        
        server {
            listen 443 ssl http2;
            listen [::]:443 ssl http2;
            server_name '"${SERVNAME}"';
        
            root /var/www/pterodactyl/html/public;
            index index.php;
        
            access_log /var/log/nginx/pterodactyl.app-accress.log;
            error_log  /var/log/nginx/pterodactyl.app-error.log error;
        
            # allow larger file uploads and longer script runtimes
            client_max_body_size 100m;
            client_body_timeout 120s;
            
            sendfile off;
        
            # strengthen ssl security
            ssl_certificate /etc/letsencrypt/live/'"${SERVNAME}"'/fullchain.pem;
            ssl_certificate_key /etc/letsencrypt/live/'"${SERVNAME}"'/privkey.pem;
            ssl_protocols TLSv1 TLSv1.1 TLSv1.2;
            ssl_prefer_server_ciphers on;
            ssl_session_cache shared:SSL:10m;
            ssl_ciphers "EECDH+AESGCM:EDH+AESGCM:ECDHE-RSA-AES128-GCM-SHA256:AES256+EECDH:DHE-RSA-AES128-GCM-SHA256:AES256+EDH:ECDHE-RSA-AES256-GCM-SHA384:DHE-RSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-SHA384:ECDHE-RSA-AES128-SHA256:ECDHE-RSA-AES256-SHA:ECDHE-RSA-AES128-SHA:DHE-RSA-AES256-SHA256:DHE-RSA-AES128-SHA256:DHE-RSA-AES256-SHA:DHE-RSA-AES128-SHA:ECDHE-RSA-DES-CBC3-SHA:EDH-RSA-DES-CBC3-SHA:AES256-GCM-SHA384:AES128-GCM-SHA256:AES256-SHA256:AES128-SHA256:AES256-SHA:AES128-SHA:DES-CBC3-SHA:HIGH:!aNULL:!eNULL:!EXPORT:!DES:!MD5:!PSK:!RC4";
            ssl_dhparam /etc/ssl/certs/dhparam.pem;
        
            # Add headers to serve security related headers
            add_header Strict-Transport-Security "max-age=15768000; preload;";
            add_header X-Content-Type-Options nosniff;
            add_header X-XSS-Protection "1; mode=block";
            add_header X-Robots-Tag none;
            add_header Content-Security-Policy "frame-ancestors 'self'";
        
            location / {
                    try_files $uri $uri/ /index.php?$query_string;
              }
        
            location ~ \.php$ {
                fastcgi_split_path_info ^(.+\.php)(/.+)$;
                fastcgi_pass unix:/var/run/php/php7.0-fpm.sock;
                fastcgi_index index.php;
                include fastcgi_params;
                fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
                fastcgi_intercept_errors off;
                fastcgi_buffer_size 16k;
                fastcgi_buffers 4 16k;
                fastcgi_connect_timeout 300;
                fastcgi_send_timeout 300;
                fastcgi_read_timeout 300;
                include /etc/nginx/fastcgi_params;
            }
        
            location ~ /\.ht {
                deny all;
            }
        }
    ' | sudo -E tee /etc/nginx/sites-available/pterodactyl.conf >/dev/null 2>&1    

    sudo service nginx restart
}

pterodactyl_daemon() {
    output "Installing the daemon now! Almost done!!"
    sudo apt -y install linux-image-extra-$(uname -r) linux-image-extra-virtual
    sudo apt update -y
    sudo apt upgrade -y
    curl -sSL https://get.docker.com/ | sh
    sudo usermod -aG docker $whoami
    sudo systemctl enable docker
    output "Installing Nodejs"
    curl -sL https://deb.nodesource.com/setup_14.x | sudo -E bash -
    sudo apt -y install nodejs
    output "Making sure we didnt miss any dependencies "
    sudo apt -y install tar unzip make gcc g++ python-minimal
    output "Ok really installing the daemon files now"
    mkdir -p /etc/pterodactyl
    curl -L -o /usr/local/bin/wings https://github.com/pterodactyl/wings/releases/latest/download/wings_linux_amd64
    chmod u+x /usr/local/bin/wings

    output "This step requires you to create your first node through your panel, only continue after you get your core code"
    output "Paste the code in the file and then hit CTRL + o then CTRL + x."
    read -p "Press enter to continue" nothing
    sudo nano /etc/pterodactyl/config.yml
sudo bash -c 'cat > /etc/systemd/system/wings.service' <<-EOF
[Unit]
Description=Pterodactyl Wings Daemon
After=docker.service

[Service]
User=root
WorkingDirectory=/etc/pterodactyl
LimitNOFILE=4096
PIDFile=/var/run/wings/daemon.pid
ExecStart=/usr/local/bin/wings
Restart=on-failure
StartLimitInterval=600

[Install]
WantedBy=multi-user.target
EOF

      sudo systemctl daemon-reload
      sudo systemctl enable wings
      sudo systemctl start wings
      sudo service wings start

      sudo usermod -aG www-data $whoami
      sudo chown -R www-data:www-data /var/www/pterodactyl/html
      sudo chown -R www-data:www-data /srv/daemon
      sudo chmod -R 775 /var/www/pterodactyl/html
      sudo chmod -R 775 /srv/daemon
      echo '
[client]
user=root
password='"${rootpasswd}"'
[mysql]
user=root
password='"${rootpasswd}"'
' | sudo -E tee ~/.my.cnf >/dev/null 2>&1
      sudo chmod 0600 ~/.my.cnf
      output "Setting mysql root password"
      sudo mysqladmin -u root password $rootpasswd    
      (crontab -l ; echo "* * * * * php /var/www/pterodactyl/html/artisan schedule:run >> /dev/null 2>&1")| crontab -
      
      output "Please reboot your server to apply new permissions"
    
    
}

# Process command line...
while [ $# -gt 0 ]; do
    case $1 in
        --help | -h)
            usage $0
        ;;
        --install | -i)
            shift
            action=$1
            shift
            ;;
        *)
            usage $0
            ;;
    esac
done
test -z $action && usage $0
case $action in
  "nginx")
    server_setup
    initial
    install_nginx
    install_mariadb
    install_dependencies
    install_timezone
    server
    pterodactyl
    pterodactyl_1
    pterodactyl_niginx
    pterodactyl_daemon
    ;;
  *)
    usage $0
    ;;
esac
exit 1;
