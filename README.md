# backup-assistant
Simple Bash script for Creating Full Backup of Linux files and Upload to FTP, SSH Server


+ Backup custom files and directories
+ Config file:   `/etc/backup-assistant/main.conf`
+ Set different interval (`Daily`, `Weekly`, `Monthly`) for creating backup of each group of directories: `/etc/backup-assistant/source`
+ Encrypts backup file using GPG
+ Send to FTP,SSH Server 
+ Auto delete old backup versions, created older than x last old versions ( from local and remote server )
+ Logging all the activities `/var/log/backup-assistant.log`
+ Easy to use as cron jobs
-------------------------------------
#### Backup multiple MariaDB/MySQL docker containers: https://github.com/ShGoudarzi/mysql-assistant
-------------------------------------

## Download
```bash
curl -o /usr/bin/backup-assistant.sh -L https://raw.githubusercontent.com/ShGoudarzi/backup-assistant/main/backup-assistant.sh \
&& chmod +x /usr/bin/backup-assistant.sh
```

## Usage
```
backup-assistant.sh 
backup-assistant.sh --force
```

## Remove
```
rm -rf /etc/backup-assistant /usr/bin/backup-assistant.sh /var/run/ba.sh.pid /var/log/backup-assistant.log
```

#### Note
ssh-key need for send backup through ssh!
