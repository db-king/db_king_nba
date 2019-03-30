# Set up package manager
export DEBIAN_FRONTEND=noninteractive
echo 'Upgrading package manager...'
apt-get update >/dev/null

# Install mysql - no password as root user
echo 'Installing MySQL (if not already installed...)'
echo 'mysql-server mysql-server/root_password_again password ' | debconf-set-selections
echo 'mysql-server-5.5 mysql-server/root_password password ' | debconf-set-selections
echo 'mysql-server-5.5 mysql-server/root_password_again password ' | debconf-set-selections
apt-get -q -y install mysql-server #>/dev/null

function createscript() {
  if [ ! -f /usr/local/bin/"$1" ]; then
    echo "Creating helper script... $1"
    echo -e "$2" > /usr/local/bin/"$1"
    chmod +x /usr/local/bin/"$1"
  else
    echo "Helper script has already been created... $1"
  fi
}

# Create our home path
echo "Setting up a home directory for this project... /home/dbking"
mkdir -p /home/dbking/
chown vagrant /home/dbking/
mkdir -p /home/dbking/source
chown vagrant /home/dbking/source
cp /vagrant/source/*.sql /home/dbking/source/
mkdir -p /home/dbking/migrations/
cp -n /vagrant/migrations/*.sql /home/dbking/migrations

createscript make-db \
  'mysql -u root -e "CREATE DATABASE IF NOT EXISTS db_king_nba"'

createscript dbking-add-source \
  'mysql -u root -Ddb_king_nba < /vagrant/source/*'

createscript dbking-add-changes \
	'mysql -u root -Ddb_king_nba < /vagrant/migrations/*' 

createscript dbking-migrate \
	 'make-db\necho\necho "Importing Base Source Data!"\ndbking-add-source\necho "Importing migrations!"\ndbking-add-changes'

# Add our cool banner text
cp /vagrant/motd /etc/motd

# Don't print last login
sed -i -e 's/PrintLastLog yes/PrintLastLog no/g' /etc/ssh/sshd_config

# More informative PS1
if ! grep -q '# DB KING PS1' /home/vagrant/.bashrc; then
  echo -e '# DB KING PS1\nPS1="\\nDBKING - \A\\n\W\\n $ "' >> /home/vagrant/.bashrc
fi

# Change into our dbking folder on login
if ! grep -q '# DB KING HOME' /home/vagrant/.bashrc; then
  echo -e '# DB KING HOME\ncd /home/dbking' >> /home/vagrant/.bashrc
fi

# Restart SSH so this takes effect now
restart ssh
