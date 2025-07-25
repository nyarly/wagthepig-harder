#!/usr/bin/env bash

root=$(realpath $(dirname $0)/..)
db_socket_path=$(echo $(pwd)/devsupport/db_sockets)

set -x
echo $root

psql -h $db_socket_path postgres << SQL
  CREATE DATABASE wtp_empty_template WITH owner wagthepig;
  CREATE DATABASE wtp_seeded_template WITH owner wagthepig;
SQL
sqlx migrate run -D $(echo $DATABASE_URL | sed 's/wagthepig/wtp_empty_template/') --source $root/backend/migrations
sqlx migrate run -D $(echo $DATABASE_URL | sed 's/wagthepig/wtp_seeded_template/') --source $root/backend/migrations
psql -h $db_socket_path wtp_seeded_template < $root/devsupport/test_seeds.sql
