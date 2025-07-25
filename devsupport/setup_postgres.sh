#!/usr/bin/env bash

root=$(realpath $(dirname $0)/..)
db_socket_path=$(echo $(pwd)/devsupport/db_sockets)

set -x

# We use this to create the DB because sqlx database setup can't (?) create an app user?
psql -h $db_socket_path postgres -c "create user postgres with superuser;"
psql -h $db_socket_path postgres -c "create user wagthepig;"
psql -h $db_socket_path postgres -c "create database wagthepig with owner wagthepig;"
sqlx migrate run --source $root/backend/migrations
psql -h $db_socket_path wagthepig < $root/devsupport/seeds.sql
