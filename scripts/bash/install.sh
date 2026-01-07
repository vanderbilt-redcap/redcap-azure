#!/bin/bash

# Copyright (c) Microsoft Corporation
# All rights reserved.
#
# MIT License

echo -e "\nHello from install.sh"

echo "mysql: $(which mysql)"

####################################################################################
#
# Update additional configuration settings including 
# user file uploading settings to Azure Blob Storage
#
####################################################################################

#!/bin/bash

# Create database and application user if they do not exist, then configure REDCap settings.
# Use admin credentials provided in APPSETTING_DBUserName/APPSETTING_DBPassword. Do not require SSL from client here.

/usr/bin/mysql -u"$APPSETTING_DBUserName" -h"$APPSETTING_DBHostName" -p"$APPSETTING_DBPassword" <<EOF
CREATE DATABASE IF NOT EXISTS $APPSETTING_DBName;
CREATE USER IF NOT EXISTS '$APPSETTING_DBUserName'@'%' IDENTIFIED WITH mysql_native_password BY '$APPSETTING_DBPassword';
GRANT SELECT, INSERT, UPDATE, DELETE, CREATE, DROP, INDEX, ALTER ON $APPSETTING_DBName.* TO '$APPSETTING_DBUserName'@'%';
FLUSH PRIVILEGES;

UPDATE $APPSETTING_DBName.redcap_config SET value = 'https://$WEBSITE_HOSTNAME/' WHERE field_name = 'redcap_base_url';
UPDATE $APPSETTING_DBName.redcap_config SET value = '$APPSETTING_StorageAccount' WHERE field_name = 'azure_app_name';
UPDATE $APPSETTING_DBName.redcap_config SET value = '$APPSETTING_StorageKey' WHERE field_name = 'azure_app_secret';
UPDATE $APPSETTING_DBName.redcap_config SET value = '$APPSETTING_StorageContainerName' WHERE field_name = 'azure_container';
UPDATE $APPSETTING_DBName.redcap_config SET value = '4' WHERE field_name = 'edoc_storage_option';
REPLACE INTO $APPSETTING_DBName.redcap_config (field_name, value) VALUES ('azure_quickstart', '1');
EOF
