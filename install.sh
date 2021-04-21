# Const
RED='\033[0;31m'
NC='\033[0m' # No Color
GREEN='\033[0;32m'
NEXTCLOUD_VERSION="21.0.0"

if [ $# -lt 4 ]
then
	echo "Usage: ./install.sh mydomain.com nextcloud_subdomain users_subdomain MyOrganizationName"
	exit
fi

# PARAMETERS
DOMAIN=$(echo $1 | cut -d. -f1)
DOMAIN_TLD=$(echo $1 | cut -d. -f2)
NEXTCLOUD_SUBDOMAIN=$2
MANAGE_USERS_SUBDOMAIN=$3
ORGANIZATION_NAME=$4

LDAP_PASSWORD=""
mysql_passwd=""


sudo apt -qq update
##############################################################
############## ASK USER
#sudo apt-get update
read -ep "Vols instalar docker? (Y/n): " install_docker
read -ep "Vols instalar el servidor web (nginx)? (Y/n): " install_nginx
read -ep "Vols descarregar el codi font de Nextcloud? (Y/n): " install_nextcloud
read -ep "Vols descarregar els fitxers de docker-compose per a desplegar els contenidors docker? (Y/n): " install_containers

install_docker=${install_docker,,}
install_nginx=${install_nginx,,}
install_nextcloud=${install_nextcloud,,}
install_containers=${install_containers,,}


##############################################################
############## DOCKER
if [ $install_docker == "y" ]
then
sudo apt install -y \
    apt-transport-https \
    ca-certificates \
    curl \
    gnupg \
    lsb-release 1>/dev/null

curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

 echo \
  "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
 sudo apt -qq update

 sudo apt install -y docker-ce docker-ce-cli containerd.io docker-compose 1>/dev/null
fi

##############################################################
############## NEXTCLOUD
if [ $install_nextcloud == "y" ]
then
 wget -O /tmp/nextcloud.zip https://download.nextcloud.com/server/releases/nextcloud-$NEXTCLOUD_VERSION.zip 2>/dev/null
 sudo apt install -y unzip 1>/dev/null
 sudo unzip -o /tmp/nextcloud.zip -d /var/www/ 1>/dev/null
 sudo chown -R www-data:www-data /var/www/nextcloud
 
 sudo apt install -y php-imagick php7.4-common php7.4-gd php7.4-json php7.4-curl php7.4-zip php7.4-xml php7.4-mbstring php7.4-bz2 php7.4-intl php7.4-fpm php7.4-mysql mysql-server 1>/dev/null

 mysql_passwd=`openssl rand -base64 14`
 sudo mysql -uroot -e "CREATE USER 'nextcloud'@'localhost' IDENTIFIED BY '$mysql_passwd'; 
        CREATE DATABASE IF NOT EXISTS nextcloud CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;
        GRANT ALL PRIVILEGES ON nextcloud.* TO 'nextcloud'@'localhost';
	FLUSH PRIVILEGES;"
fi

##############################################################
############## NGINX
if [ $install_nginx == "y" ]
then
 sudo apt install -y nginx certbot python3-certbot-nginx 1>/dev/null
 
 sudo cp initSite  /etc/nginx/sites-available/nextcloud
 sudo cp initSite  /etc/nginx/sites-available/manage_ldap_users
 sudo cp initSite  /etc/nginx/sites-available/webmail

 sudo sed -i -e "s/MYDOMAIN/$DOMAIN/g" -e "s/MYDOM_TLD/$DOMAIN_TLD/g" -e "s/MYSUBDOMAIN/$NEXTCLOUD_SUBDOMAIN/g" /etc/nginx/sites-available/nextcloud
 sudo sed -i -e "s/MYDOMAIN/$DOMAIN/g" -e "s/MYDOM_TLD/$DOMAIN_TLD/g" -e "s/MYSUBDOMAIN/$MANAGE_USERS_SUBDOMAIN/g" /etc/nginx/sites-available/manage_ldap_users
 sudo sed -i -e "s/MYDOMAIN/$DOMAIN/g" -e "s/MYDOM_TLD/$DOMAIN_TLD/g" -e "s/MYSUBDOMAIN/mail/g" /etc/nginx/sites-available/webmail

 sudo ln -s /etc/nginx/sites-available/nextcloud /etc/nginx/sites-enabled/nextcloud
 sudo ln -s /etc/nginx/sites-available/manage_ldap_users /etc/nginx/sites-enabled/manage_ldap_users
 sudo ln -s /etc/nginx/sites-available/webmail /etc/nginx/sites-enabled/webmail
 
 for sub in $NEXTCLOUD_SUBDOMAIN $MANAGE_USERS_SUBDOMAIN mail
 do
   sudo certbot --redirect -n -d $sub.$DOMAIN.$DOMAIN_TLD --nginx --agree-tos --email fake@fake.com
 done
 
 sudo cp nextcloud /etc/nginx/sites-available/
 sudo cp manage_ldap_users /etc/nginx/sites-available/
 sudo cp webmail /etc/nginx/sites-available/
 
 sudo sed -i -e "s/MYDOMAIN/$DOMAIN/g" -e "s/MYDOM_TLD/$DOMAIN_TLD/g" -e "s/NEXTCLOUD_SUBDOMAIN/$NEXTCLOUD_SUBDOMAIN/g" /etc/nginx/sites-available/nextcloud
 sudo sed -i -e "s/MYDOMAIN/$DOMAIN/g" -e "s/MYDOM_TLD/$DOMAIN_TLD/g" -e "s/USERS_SUBDOMAIN/$MANAGE_USERS_SUBDOMAIN/g" /etc/nginx/sites-available/manage_ldap_users
 sudo sed -i -e "s/MYDOMAIN/$DOMAIN/g" -e "s/MYDOM_TLD/$DOMAIN_TLD/g" /etc/nginx/sites-available/webmail
 
 sudo killall -9 nginx
 sudo systemctl start nginx

fi

##############################################################
############## CONTENIDORS: mail i ldap
if [ $install_containers == "y" ]
then
  # The sed here prevents a slash
  LDAP_PASSWORD=$(openssl rand -base64 32 | sed "s/\//4/g")
  wget -O /tmp/mailserver.zip https://github.com/chverma/docker-mailserver/archive/refs/tags/v1.0.0.zip 2>/dev/null
  wget -O /tmp/openldap.zip https://github.com/chverma/docker-openldap/archive/refs/tags/v1.0.0.zip 2>/dev/null

  unzip -o /tmp/openldap.zip 1>/dev/null
  unzip -o /tmp/mailserver.zip 1>/dev/null
  
  
  bash docker-openldap-1.0.0/config.sh $DOMAIN.$DOMAIN_TLD $MANAGE_USERS_SUBDOMAIN $ORGANIZATION_NAME $LDAP_PASSWORD
  $(cd docker-openldap-1.0.0 && docker-compose up -d)

  bash docker-mailserver-1.0.0/configure.sh $DOMAIN.$DOMAIN_TLD $LDAP_PASSWORD
  $(cd docker-mailserver-1.0.0 && docker-compose up -d)
  $(cd docker-mailserver-1.0.0 && ./setup.sh config dkim domain "$DOMAIN.$DOMAIN_TLD") 
fi


if [ $install_nextcloud == "y" ]
then
  echo -e "${GREEN}S'ha creat l'usuari ${RED}nextcloud${GREEN} amb contrasenya ${RED}$mysql_passwd${NC}"
fi

if [ $install_containers == "y" ]
then
  echo -e "${GREEN}S'ha creat la contrasenya per a LDAP ${RED}$LDAP_PASSWORD${NC}"
  echo -e "${GREEN}Visita ${RED}https://$MANAGE_USERS_SUBDOMAIN.$DOMAIN.$DOMAIN_TLD/setup ${GREEN} i utilitza la contrasenya d'LDAP generada"
  echo -e "${GREEN}Ja pots visitar ${RED}https://mail.$DOMAIN.$DOMAIN_TLD ${GREEN}per provar el webmail${NC}"
fi
