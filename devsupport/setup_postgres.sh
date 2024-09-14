#!/usr/bin/env bash

root=$(realpath $(dirname $0)/..)
db_socket_path=$(echo $(pwd)/devsupport/db_sockets)

set -x
echo $root

psql -h $db_socket_path postgres < $root/backend/database/create.sql
psql -h $db_socket_path wagthepig < $root/backend/database/schema.sql
psql -h $db_socket_path wagthepig < $root/backend/database/extra.sql
