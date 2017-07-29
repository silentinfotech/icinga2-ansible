#!/bin/bash
DATE=`date +%Y-%m-%d`

copy_docker_logs(){
    if [ "$#" -ne 1 ]; then
        echo "Usage: $0 <TAR_FILE_PATH>" >&2
        exit 1
    fi


    MYSQL_LOG_DIR="/var/log/mysql"
    HTTPD_LOG_DIR="/usr/local/apache2/logs"
    LOCAL_DIR="/var/tmp/docker_logs"

    # MySQL Docker ID
    mysql_id=`docker ps | grep mysql | awk '{print $1}'`

    # HTTPD Docker ID
    httpd_id=`docker ps | grep httpd | awk '{print $1}'`

    # Remove Old Structures
    rm -rf $LOCAL_DIR/

    # Creates http LogDir
    mkdir -p $LOCAL_DIR/httpd/

    # Creates mysql LogDir
    mkdir -p $LOCAL_DIR/mysql/

    # Copy mysql files from docker to host
    docker cp $mysql_id:$MYSQL_LOG_DIR $LOCAL_DIR
    
    docker exec $mysql_id rm -rf $MYSQL_LOG_DIR/*

    # Copy http files from docker to host
    docker cp $httpd_id:$HTTPD_LOG_DIR/access_log  $LOCAL_DIR/httpd/
    docker cp $httpd_id:$HTTPD_LOG_DIR/error_log  $LOCAL_DIR/httpd/
    docker exec $httpd_id sh -c '>$HTTPD_LOG_DIR/access_log ; >$HTTPD_LOG_DIR/error_log'

    # Compress LogFiles to send to S3
    cd $LOCAL_DIR
    tar czvf $1 *

}

s3_put(){
    if [ "$#" -ne 3 ]; then
      echo "Usage: $0 <UPLOAD_FILE_PATH> <S3_BUCKET> <S3_PATH>" >&2
      exit 1
    fi

    S3KEY="AKIAJHOWKZXRU4ADKKXA"
    S3SECRET="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" # pass these in

    FILE_PATH=$1
    DIR=$(dirname "${FILE_PATH}")
    FILE=$(basename "${FILE_PATH}")
    BUCKET=$2
    AWS_PATH=$3
    date=$(date +"%a, %d %b %Y %T %z")
    acl="x-amz-acl:public-read"
    content_type='application/x-compressed-tar'
    string="PUT\n\n$content_type\n$date\n$acl\n/$BUCKET$AWS_PATH$FILE"
    signature=$(echo -en "${string}" | openssl sha1 -hmac "${S3SECRET}" -binary | base64)
    curl -X PUT -T "$DIR/$FILE" \
            -H "Host: $BUCKET.s3.amazonaws.com" \
            -H "Date: $date" \
            -H "Content-Type: $content_type" \
            -H "$acl" \
            -H "Authorization: AWS ${S3KEY}:$signature" \
            "https://$BUCKET.s3.amazonaws.com$AWS_PATH$FILE"

}

copy_docker_logs "/tmp/logs_$DATE.tar.gz"
s3_put "/tmp/logs_$DATE.tar.gz"  "logbackupcluster" "/dockerlogs/" 
