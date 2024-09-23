#!/usr/bin/env bash

root=$(realpath $(dirname $0)/..)
db_socket_path=$(echo $(pwd)/devsupport/db_sockets)

set -x
echo $root

psql -h $db_socket_path postgres < $root/devsupport/create_db.sql
pushd backend;
sqlx migrate run
popd
psql -h $db_socket_path wagthepig < $root/devsupport/seeds.sql
