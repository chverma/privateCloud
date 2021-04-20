# Const
RED='\033[0;31m'
NC='\033[0m' # No Color
GREEN='\033[0;32m'
NEXTCLOUD_VERSION="21.0.0"

if [ $# -lt 4 ]
then
	echo "Usage: ./install.sh mydomain.com nextcloud users MyOrganizationName"
	exit
fi

# PARAMETERS
DOMAIN=$(echo $1 | cut -d. -f1)
DOMAIN_TLD=$(echo $1 | cut -d. -f2)
NEXTCLOUD_SUBDOMAIN=$2
MANAGE_USERS_SUBDOMAIN=$3
ORGANIZATION_NAME=$4
NEXTCLOUD_URL=$(echo $NEXTCLOUD_SUBDOMAIN.$DOMAIN.$DOMAIN_TLD)


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
    lsb-release

curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

 echo \
  "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
 sudo apt-get update

 sudo apt-get install -y docker-ce docker-ce-cli containerd.io
fi

##############################################################
############## NEXTCLOUD
if [ $install_nextcloud == "y" ]
then
 wget -O /tmp/nextcloud.zip https://download.nextcloud.com/server/releases/nextcloud-$NEXTCLOUD_VERSION.zip
 sudo apt install -y unzip
 sudo unzip /tmp/nextcloud.zip -d /var/www/
 sudo chown -R www-data:www-data /var/www/nextcloud
 
 sudo apt install -y php-imagick php7.4-common php7.4-gd php7.4-json php7.4-curl php7.4-zip php7.4-xml php7.4-mbstring php7.4-bz2 php7.4-intl php7.4-fpm php7.4-mysql

 sudo apt install -y mysql-server
 mysql_passwd=`openssl rand -base64 14`
 echo -e "${GREEN}S'ha creat l'usuari ${RED}nextcloud${GREEN} amb contrasenya ${RED}$mysql_passwd${NC}"
 sudo mysql -uroot -e "CREATE USER 'nextcloud'@'localhost' IDENTIFIED BY '$mysql_passwd'; 
        CREATE DATABASE IF NOT EXISTS nextcloud CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;
        GRANT ALL PRIVILEGES ON nextcloud.* TO 'nextcloud'@'localhost';
	FLUSH PRIVILEGES;"
fi

##############################################################
############## NGINX
if [ $install_nginx == "y" ]
then
 sudo apt install -y nginx certbot python3-certbot-nginx
 #wget
 sudo cp uji/nextcloud0 /etc/nginx/sites-available/nextcloud
 sudo sed -i "s/example\.com/$URL/g" /etc/nginx/sites-enabled/nextcloud
 sudo ln -s /etc/nginx/sites-enabled/nextcloud /etc/nginx/sites-available/nextcloud
 sudo certbot --redirect -n -d $URL --nginx
 sudo cp uji/nextcloud2 /etc/nginx/sites-enabled/nextcloud
 sudo sed -i "s/example\.com/$URL/g" /etc/nginx/sites-enabled/nextcloud
 sudo systemctl restart nginx
fi

##############################################################
############## CONTENIDORS: mail i ldap
if [ $install_containers == "y" ]
then
  # The sed here prevents a slash
  LDAP_PASSWORD=$(openssl rand -base64 32 | sed "s/\//4/g")
  echo -e "${GREEN}S'ha creat la contrasenya per a LDAP ${RED}$LDAP_PASSWORD${NC}"
  wget -O /tmp/mailserver.zip https://github.com/chverma/docker-mailserver/archive/refs/tags/v1.0.0.zip 2>/dev/null
  wget -O /tmp/openldap.zip https://github.com/chverma/docker-openldap/archive/refs/tags/v1.0.0.zip 2>/dev/null

  unzip -o /tmp/openldap.zip 1>/dev/null
  unzip -o /tmp/mailserver.zip 1>/dev/null
  
  
  bash docker-openldap-1.0.0/config.sh $DOMAIN.$DOMAIN_TLD $MANAGE_USERS_SUBDOMAIN $ORGANIZATION_NAME $LDAP_PASSWORD
  $(cd docker-openldap-1.0.0 && docker-compose up -d)
  echo -e "${GREEN}Visita ${RED}https://$MANAGE_USERS_SUBDOMAIN.$DOMAIN.$DOMAIN_TLD/setup ${GREEN} i utilitza la contrasenya d'LDAP generada"

  bash docker-mailserver-1.0.0/configure.sh $DOMAIN.$DOMAIN_TLD $LDAP_PASSWORD
  $(cd docker-mailserver-1.0.0 && docker-compose up -d)
  
  echo -e "${GREEN}Ja pots visitar ${RED}https://mail.$DOMAIN.$DOMAIN_TLD ${GREEN}per provar el webmail" 
fi
