#!/bin/bash
#===============================================================================
#
#           DIR: /etc/backup-assistant
#
#         USAGE: backup-assistant.sh , backup-assistant.sh --force
#
#   DESCRIPTION: create a gz backup of your files and upload them to ftp,ssh server
#
#  REQUIREMENTS: curl, gpg, rsync, ftp
#        AUTHOR: Shayan Goudarzi, me@shayangoudarzi.ir
#  ORGANIZATION: Linux
#       CREATED: 09/16/2022
#===============================================================================
export TOP_PID=$$
export ARGS=($@)


hostname=$(hostname -s)
pidFile=/var/run/ba.sh.pid

nowShortDate=$(date +"%Y%m%d")
nowFullDate=$(date +"%d/%b/%Y:%H:%M:%S %:::z")
scriptConfigPath="/etc/backup-assistant"
scriptSourceFilesPath="$scriptConfigPath/source"
logMainFile="/var/log/backup-assistant.log"
logTmpFile="/tmp/backup-assistant.log"

week_day=$(date +"%u")
month_day=$(date +"%d")

G_daily_fileName="backup.daily"
G_weekly_fileName="backup.weekly"
G_monthly_fileName="backup.monthly"


#### Default Status
SSH_CONNECTION_STATUS=1
FTP_CONNECTION_STATUS=1

#### Default Variables
week_backup_day="5"
month_backup_day="29"


### Colors
red() {
  tput bold
  tput setaf 1
}
yellow() {
  tput bold
  tput setaf 3
}
white() {
  tput bold
  tput setaf 7
}
green() {
  tput bold
  tput setaf 2
}
blue() {
  tput bold
  tput setaf 6
}
resetcolor() {
  tput sgr0
}



##### Functions #####

function logger() {
  while read data; do
    echo -e "$(date +"%d/%b/%Y:%H:%M:%S %:::z") $data" | tee -a $logMainFile
  done
}

function funCheckStart() {
  if [ -f $pidFile ];
  then

    echo -e "Script is already running"  | logger
    resetcolor;

    local old_pid=$( cat $pidFile )
    if [ "${ARGS[0]}" == "--force" ]; then
        echo -e "Fresh start..."  | logger
        kill -9 $old_pid
        rm -rf $pidFile
        echo $TOP_PID >"$pidFile"
    else
        echo -e "run script by --force to skip limitation "  | logger
        exit 0
    fi


  else
    echo $TOP_PID >"$pidFile"
  fi
}

function funCheckEnd() {
  trap "rm -f -- '$pidFile'" EXIT
}



function funCheckDependency {
   command -v curl >/dev/null 2>&1 || { echo -e "I require 'curl' but it's not installed. Please install it and try again." | logger; kill -s 1 "$TOP_PID"; }
   command -v gpg >/dev/null 2>&1 || { echo -e "I require 'gpg' but it's not installed. Please install it and try again." | logger; kill -s 1 "$TOP_PID"; }
   command -v rsync >/dev/null 2>&1 || { echo -e "I require 'rsync' but it's not installed. Please install it and try again." | logger; kill -s 1 "$TOP_PID"; }
   command -v sshpass >/dev/null 2>&1 || { echo -e "I require 'sshpass' but it's not installed. Please install it and try again." | logger; kill -s 1 "$TOP_PID"; }
   command -v ftp >/dev/null 2>&1 || { echo -e "I require 'ftp' but it's not installed. Please install it and try again." | logger; kill -s 1 "$TOP_PID"; }
}

function funFirstInstallation() {
    if [ ! -f $scriptConfigPath/main.conf ];
    then
        mkdir -p $scriptSourceFilesPath > /dev/null 2>&1
        cat <<EOF > $scriptConfigPath/main.conf

### Date ###
week_backup_day="5"            # 5:friday
month_backup_day="29"


### Path ###
local_save_path="/local-backup/"
ftpSavePath="/ftp-backup/"
ssh_save_path="/ssh-backup/"

### Encryption ###
encryption_enable="no"
encryption_name="$hostname"


### FTP method ###
ftp_enable="no"
ftp_server="ftp.example.com"
ftp_username="ftpuser"
ftp_password="ftppassword"

### SSH method ###
ssh_enable="no"
ssh_server="ssh.example.com"
ssh_port=22
ssh_username="root"
ssh_password=""              # if is null, script will use sshkey by default

#### Clean ###
local_save_last_versions=4
ftp_save_last_versions=12
ssh_save_last_versions=12
EOF

        cat <<EOF >>$scriptSourceFilesPath/$G_weekly_fileName
# Put you Absolute sshProperPeriodSavePath bellow and seprate them by ENTER
$HOME
EOF

        touch $scriptSourceFilesPath/$G_daily_fileName $scriptSourceFilesPath/$G_monthly_fileName
        echo -e "$nowFullDate Script has been installed successfully\n$nowFullDate Write your paths in source config files: $scriptSourceFilesPath"
        exit 0
    fi
}


################
##### Init
################
echo -e "###########################" | logger
echo -e "Preparing..." | logger

##### Call Necessary Functions
funCheckStart
funCheckEnd
funCheckDependency
funFirstInstallation

##### Load Config File
source $scriptConfigPath/main.conf


totalSourceFilesName=()
scriptSourceFilesList=$(find $scriptSourceFilesPath -type f | grep -E "$G_daily_fileName|$G_weekly_fileName|$G_monthly_fileName" | xargs)
for scriptSourceFile in $scriptSourceFilesList;
do
    if [ $(cat $scriptSourceFile | wc -l) -ne 0 ];
    then

        scriptSourceFileName=$(basename $scriptSourceFile)
        case $scriptSourceFileName in

           $G_daily_fileName)
             totalSourceFilesName+=($scriptSourceFileName)
             ;;

           $G_weekly_fileName)
             if [ $week_day == $week_backup_day ];
             then
                 totalSourceFilesName+=($scriptSourceFileName)
             fi
             ;;

           $G_monthly_fileName)
             if [ $month_day == $month_backup_day ];
             then
                 totalSourceFilesName+=($scriptSourceFileName)
             fi
             ;;
        esac
    fi

done


if [ -z "$totalSourceFilesName" ];
then
    echo -e "Not found any source config files or today is not the backup day!" | logger
    exit 0
fi



sleep 1;
###########################
##### Creating Backup #####
###########################

yellow;
echo "Creating Backup archives..." | logger
resetcolor;

localGeneratedBackupsFullPathList=()
for sourceFileName in ${totalSourceFilesName[@]};
do
    backupPeriod=$(echo $sourceFileName | cut -d "." -f 2)
    localPeriodSavePath=$local_save_path/$backupPeriod
    mkdir -p $localPeriodSavePath > /dev/null 2>&1

    sourceFilePeriodName=$scriptSourceFilesPath/$sourceFileName
    sourceFilePeriodContents=$(cat $sourceFilePeriodName | sed '/^[[:space:]]*$/d' | sed '/^#/d' | xargs)
    backupResultFullPathName=$localPeriodSavePath/$backupPeriod-fullbackup-$hostname-$nowShortDate.tar.gz

    tar -czf $backupResultFullPathName $sourceFilePeriodContents > /dev/null 2>&1
    localGeneratedBackupsFullPathList+=($backupResultFullPathName)

done
green;
echo -e "Backup archives has have been created successfully" | logger
resetcolor;



# GPG Encryption
if [ "$encryption_enable" == "yes" ];
then
    yellow;
    echo -e "Encrypting Backup archives..." | logger
    resetcolor;

    counter=0
    for localGeneratedBackupFile in ${localGeneratedBackupsFullPathList[@]};
    do
        gpg --always-trust -e -r "$encryption_name" $localGeneratedBackupFile

        if [ $? -ne 0 ]
        then
            red;
            echo -e "Encrypting backup archives FAILD" | logger
            resetcolor;
            exit 0;
        fi

        rm -rf $localGeneratedBackupFile
        localGeneratedBackupsFullPathList[$counter]="$localGeneratedBackupFile.gpg"
        counter=$counter+1

    done

    green;
    echo -e "Encrypting backup archives has have been completed successfully" | logger
    resetcolor;
fi


sleep 1;
###########################
##### Uploading #####
###########################


### FTP Upload
if [ "$ftp_enable" == "yes" ];
then
    is_ok=1

    yellow;
    echo -e "Uploading to FTP-server..." | logger
    resetcolor;

    for localGeneratedBackupFile in ${localGeneratedBackupsFullPathList[@]};
    do
        localSavePath=$(echo $local_save_path | sed 's/\//\\\//g')
        ftpSavePath=$(echo $ftpSavePath | sed 's/\//\\\//g')
        ftpProperPeriodSavePath=$(dirname $localGeneratedBackupFile | sed -e "s/$localSavePath/$ftpSavePath/")
        curl --show-error --connect-timeout 10 --retry 3 --retry-delay 30 --upload-file $localGeneratedBackupFile --ftp-create-dirs "ftp://$ftp_server:21/$ftpProperPeriodSavePath/" --user "$ftp_username:$ftp_password"

        if [ $? -ne 0 ]
        then
            red;
            echo -e "Uploading to FTP-server FAILD" | logger
            resetcolor;
            FTP_CONNECTION_STATUS=0
            is_ok=0
        fi

    done


    if [ $is_ok -eq 1 ]
    then
      green;
      echo -e "Uploading to FTP-server has have been completed successfully." | logger
      resetcolor;
    fi
fi



### SSH Upload
if [ "$ssh_enable" == "yes" ];
then
    is_ok=1

    yellow;
    echo -e "Uploading to SSH-server..." | logger
    resetcolor;


    for localGeneratedBackupFile in ${localGeneratedBackupsFullPathList[@]};
    do
        localSavePath=$(echo $local_save_path | sed 's/\//\\\//g')
        sshSavePath=$(echo $ssh_save_path | sed 's/\//\\\//g')
        sshProperPeriodSavePath=$(dirname $localGeneratedBackupFile | sed -e "s/$localSavePath/$sshSavePath/")
        if [ "$ssh_password" != "" ];
        then
            sshpass -p $ssh_password ssh -o StrictHostKeyChecking=no -t $ssh_username@$ssh_server -p $ssh_port  "mkdir -p /$sshProperPeriodSavePath/"
            rsync -avh -e "sshpass -p $ssh_password ssh -p $ssh_port -o StrictHostKeyChecking=no" $localGeneratedBackupFile $ssh_username@$ssh_server:/$sshProperPeriodSavePath/ | logger
        else
            ssh -t $ssh_username@$ssh_server -p $ssh_port -o StrictHostKeyChecking=no "mkdir -p /$sshProperPeriodSavePath/"
            rsync -avh -e "ssh -p $ssh_port -o StrictHostKeyChecking=no" $localGeneratedBackupFile $ssh_username@$ssh_server:/$sshProperPeriodSavePath/ | logger
        fi

        if [ $? -ne 0 ]
        then
            red;
            echo -e "Uploading to SSH-server FAILD" | logger
            resetcolor;
            SSH_CONNECTION_STATUS=0
            is_ok=0
        fi

    done

    if [ $is_ok -eq 1 ]
    then
      green;
      echo -e "Uploading to SSH-server has have been completed successfully." | logger
      resetcolor;
    fi

fi



sleep 1;
###########################
##### Cleaning #####
###########################


### Local
yellow;
echo -e "Cleaning local backups older than $local_save_last_versions last old versions..." | logger
resetcolor;

localTotalCleaningList=()
for sourceFileName in ${totalSourceFilesName[@]};
do
  backupPeriod=$(echo $sourceFileName | cut -d "." -f 2)
  localPeriodSavePath=$local_save_path/$backupPeriod

  count=$(( $(ls -ltr $localPeriodSavePath | grep "^-r" | wc -l) - $local_save_last_versions ))
  if [ $count -gt 0 ];
  then
      files=$(ls -ltr $localPeriodSavePath | grep "^-r" | head -n $count | awk '{print $NF}' | awk -F ' ' -v awklocal_path_dir="$localPeriodSavePath/" '{print awklocal_path_dir $1}' | xargs)
      localTotalCleaningList+=($files)
  fi

done

if [ -z "$localTotalCleaningList" ];
then
    echo -e "ّNot need." | logger
else
    rm -rf ${localTotalCleaningList[@]}
    echo -e "ّFiles: $files" | logger

    green;
    echo -e "Cleaning Done." | logger
fi

resetcolor;



### FTP
if [ "$ftp_enable" == "yes" ] && [ $FTP_CONNECTION_STATUS == 1 ];
then
    is_ok=1

    yellow;
    echo -e "Cleaning remote ftp backups older than $ftp_save_last_versions last old versions..." | logger
    resetcolor;

    ftpTotalCleaningList=()
    for sourceFileName in ${totalSourceFilesName[@]};
    do
        sleep 1

        backupPeriod=$(echo $sourceFileName | cut -d "." -f 2)
        ftp_path_dir=$ftp_save_path/$backupPeriod

        ftp -i -n $ftp_server <<EOMYF > $logTmpFile
        user $ftp_username $ftp_password
        binary
        cd $ftp_path_dir
        ls --sort
        quit
EOMYF

        count=$(( $(cat $logTmpFile | grep -v "drwxr" | wc -l) - $ftp_save_last_versions ))
        if [ $count -gt 0 ];
        then
            ftp_dirs_list_path=$(cat $logTmpFile | grep -v "drwxr" | awk '{print $NF}' | head -n $count | awk -F ' ' -v awkftp_path_dir="$ftp_path_dir/" '{print awkftp_path_dir $1}' | xargs)
            ftpTotalCleaningList+=($ftp_dirs_list_path)
        fi

    done


    if [ -z "$ftpTotalCleaningList" ];
    then
        echo -e "ّNot need." | logger
    else

        ftp -i -n $ftp_server <<EOMYF
        user $ftp_username $ftp_password
        binary
        mdelete ${ftpTotalCleaningList[@]}
        quit
EOMYF

        echo -e "ّFiles: ${ftpTotalCleaningList[@]}" | logger

        green;
        echo -e "Cleaning FTP-server Done." | logger

    fi
    resetcolor;

fi


### SSH
if [ "$ssh_enable" == "yes" ] && [ $SSH_CONNECTION_STATUS == 1 ];
then
    yellow;
    echo -e "Cleaning SSH backups older than $ssh_save_last_versions last old versions..." | logger
    resetcolor;

    sshTotalCleaningList=()
    for sourceFileName in ${totalSourceFilesName[@]};
    do
        backupPeriod=$(echo $sourceFileName | cut -d "." -f 2)
        ssh_path_dir=$ssh_save_path/$backupPeriod

        if [ "$ssh_password" != "" ];
        then
            sshpass -p $ssh_password ssh -t $ssh_username@$ssh_server -p $ssh_port -o StrictHostKeyChecking=no <<EOMYF > $logTmpFile
            ls -ltr $ssh_path_dir
EOMYF
        else
            ssh -t $ssh_username@$ssh_server -p $ssh_port -o StrictHostKeyChecking=no <<EOMYF > $logTmpFile
            ls -ltr $ssh_path_dir
EOMYF
        fi

        count=$(( $(cat $logTmpFile | grep "^-r" | wc -l) - $ssh_save_last_versions ))
        if [ $count -gt 0 ];
        then
          ssh_dirs_list_path=$(cat $logTmpFile | grep "^-r" | head -n $count | awk '{print $NF}' | awk -F ' ' -v awkssh_path_dir="$ssh_path_dir/" '{print awkssh_path_dir $1}' | xargs)
          sshTotalCleaningList+=($ssh_dirs_list_path)
        fi

    done


    if [ -z "$sshTotalCleaningList" ];
    then
        echo -e "ّNot need." | logger
    else
        if [ "$ssh_password" != "" ];
        then
            sshpass -p $ssh_password ssh -t $ssh_username@$ssh_server -p $ssh_port -o StrictHostKeyChecking=no "rm -rf ${sshTotalCleaningList[@]}"
        else
            ssh -t $ssh_username@$ssh_server -p $ssh_port -o StrictHostKeyChecking=no "rm -rf ${sshTotalCleaningList[@]}"
        fi
        echo -e "ّFiles: $ssh_dirs_list_path" | logger

        green;
        echo -e "Cleaning Done." | logger
    fi
    resetcolor;
fi



########## Final ###########
echo -e "" | logger
green;
echo -e "*** Backup finished ***" | logger
resetcolor;
echo -e "Backup files:" | logger

for localGeneratedBackupFile in ${localGeneratedBackupsFullPathList[@]};
do
    localGeneratedBackupFile=$(echo $localGeneratedBackupFile | sed "s/\/\//\//")
    archive_size=$(ls -lh $localGeneratedBackupFile | awk '{print  $5}')
    yellow;
    echo -e "$localGeneratedBackupFile : $archive_size" | logger
    resetcolor;
done

rm -rf $logTmpFile
exit 0
