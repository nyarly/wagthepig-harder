#!/usr/bin/env bash

set -x
cd $(dirname $0)

mkdir -p nginx/conf

ls nginx
ls nginx/nginx.conf.envsubst
envsubst -no-unset -no-empty < nginx/nginx.conf.envsubst > nginx/conf/nginx.conf
cp tls/backend/server.crt.pem nginx/conf/server.crt.pem
cp tls/backend/server.key.pem nginx/conf/server.key.pem
#ln -s ../../tls/backend/server.crt.pem nginx/conf/server.crt.pem
#ln -s ../../tls/backend/server.key.pem nginx/conf/server.key.pem
# generate nginx.conf from nginx.conf.template
# including pointing to the server cert
#
# NGINX key and cert in PEM format
#
# nginx --prefix=path sets a prefix that everything is relative too
