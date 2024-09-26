#!/usr/bin/env bash

cd $(dirname $0)

set -x
[ -e cert.key ] || openssl genrsa -out cert.key 2048
[ -e cert.csr ] || openssl req -new -key cert.key -out cert.csr -config req.cfg -batch
[ -e cert.crt ] || openssl x509 -req -extfile req.cfg -days 3650 -in cert.csr -signkey cert.key -out cert.crt
