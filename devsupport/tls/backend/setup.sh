#!/usr/bin/env bash

cd $(dirname $0)

set -x
if ! [ -e ca.key.pem -a -e ca.csr ]; then
  openssl req -noenc \
    -newkey rsa:2048 \
    -outform PEM -keyform PEM \
    -out ca.csr -keyout ca.key.pem \
    -config req.cfg -section ca -batch
fi
[ -e ca.crt.pem ] || openssl x509 -req -extfile req.cfg -days 3650 -in ca.csr -signkey ca.key.pem -out ca.crt.pem
if ! [ -e server.key.pem -a -e server.csr ]; then
  openssl req -noenc \
    -newkey rsa:2048 \
    -outform PEM -keyform PEM \
    -out server.csr -keyout server.key.pem \
    -config req.cfg -section server -batch
fi
[ -e server.crt.pem ] || openssl x509 -req -extfile req.cfg -days 3650 -in server.csr -CA ca.crt.pem -CAkey ca.key.pem -out server.crt.pem
