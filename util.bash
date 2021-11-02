#!/usr/bin/bash
#############################################################################
## Licensed Materials - Property of BRZ
##
## Governed under the terms of the International
## License Agreement for Non-Warranted Sample Code.
##
## (C) COPYRIGHT Bundesrechenzentrum
## All Rights Reserved.
## Author : Wolfgang Brandl
#############################################################################

# This Script should test a specific backup / restore scenario
# There a several steps which could be executed


#Die folgenden Szenarien sollen mit diesem Skript nachgestellt werden kC6nnen.
#Es werden nur full online und incremental backups durchgefC<hrt. Aus diesem Backup Stand soll die DB nach einem Crash wieder erzeugt werden oder einzelene Tablespaces in einer anderen Instanz wieder hergestellt werden.

#1.     In der Datenbank wird eine Tabelle zerstC6rt
#  a.   Restore des Tablespaces welcher die Tabelle enthC$lt in die active Datenbank to point in time RESTOREINTOEXIST
#  b.   Restore des Tablespaces welcher die zerstC6rte Tabelle enthC$lt in eine neue Datenbank (REDIRECT)
#2.     Datenbank ist zerstC6rt
#  a.   Archive Logs sind noch vorhanden RESTOREWITHARCHLOGS
#  b.   Archive logs sind nicht vorhanden. Dadurch kann nicht vollstC$ndig recovered werden. RESTOREWITHOUTARCHLOGS

BACKUPPATH=$PGDATA/../backup
CONTAINERPATH=$PGDATA/../tablespace_PGTST1
SYN=PT
QUAL=PGTST1
LOCALINSTANCE=pgtst1


#-------------------------------------------------------------------
# Stopt den Postgres Server
#-------------------------------------------------------------------
stop_pg ()
{
  pg_ctl stop -D $PGDATA 
}
#-------------------------------------------------------------------
# Startet den Postgres Server
#-------------------------------------------------------------------
start_pg ()
{
  pg_ctl start -D $PGDATA
}
#-------------------------------------------------------------------
# Restart des Postgres Servers
#-------------------------------------------------------------------
restart_pg ()
{
  pg_ctl restart -D $PGDATA
}
#-------------------------------------------------------------------
# Erzeugt die genannte Datenbank
#-------------------------------------------------------------------
function create_db ()
{
  DBT=$1
  CONT=$2
  printf "Anlegen der Source Datenbank %s with Automatic Storage\n" "$DBT"

  mkdir -p "$CONT"/tablespace/"$DBT"
  mkdir -p "$CONT"/TS_U_SPACE/"$DBT"
  mkdir -p "$CONT"/TS_M_SPACE/"$DBT"
  mkdir -p "$CONT"/TS_B_SPACE/"$DBT"
  mkdir -p "$CONT"/TS_N_SPACE/"$DBT"
  mkdir -p "$CONT"/metadata/"$DBT"
  createdb -E UTF8 -e $DBT --lc-collate=en_US.UTF-8 --lc-ctype=en_US.UTF-8 -T template0
  psql -d $DBT -c "ALTER DATABASE $DBT OWNER TO postgres1"
  psql -d $DBT -c "CREATE TABLESPACE USPACE LOCATION '$CONT"/TS_U_SPACE/"$DBT'"
  psql -d $DBT -c "CREATE TABLESPACE BSPACE LOCATION '$CONT"/TS_B_SPACE/"$DBT'"
  psql -d $DBT -c "CREATE TABLESPACE NSPACE LOCATION '$CONT"/TS_N_SPACE/"$DBT'"
  psql -d $DBT -c "CREATE TABLESPACE MSPACE LOCATION '$CONT"/TS_M_SPACE/"$DBT'"
  psql -d $DBT -c "CREATE TABLESPACE META LOCATION '$CONT"/metadata/"$DBT'"


  cat << EOF > cr_random_function.sql
  BEGIN;
Create or replace function random_string(length integer) returns text as
\$\$
declare
  chars text[] := '{0,1,2,3,4,5,6,7,8,9,A,B,C,D,E,F,G,H,I,J,K,L,M,N,O,P,Q,R,S,T,U,V,W,X,Y,Z,a,b,c,d,e,f,g,h,i,j,k,l,m,n,o,p,q,r,s,t,u,v,w,x,y,z}';
  result text := '';
  i integer := 0;
begin
  if length < 0 then
    raise exception 'Given length cannot be less than 0';
  end if;
  for i in 1..length loop
    result := result || chars[1+random()*(array_length(chars, 1)-1)];
  end loop;
  return result;
end;
\$\$ language plpgsql;
  COMMIT;
EOF
  psql -d $DBT -x -q -A -f cr_random_function.sql
  rm -f cr_random_function.sql
}
#-------------------------------------------------------------------
# Versucht die mitgegebene Datenbank zu stoppen und dann zu loeschen
#-------------------------------------------------------------------
function smooth_drop ()
{
  DBT=$1
  CONT=$2
  cat << EOF | psql -U postgres1 -d $DBT
BEGIN;

SELECT pg_terminate_backend(pg_stat_activity.pid)
FROM pg_stat_activity
WHERE pg_stat_activity.datname = '$DBT'
  AND pid <> pg_backend_pid();

END;
EOF
  psql -d $DBT -c "DROP TABLE tablea"
  psql -d $DBT -c "DROP TABLE tableg"
  psql -d $DBT -c "DROP TABLE tablec"
  psql -d $DBT -c "DROP TABLE tableb"
  psql -d $DBT -c "DROP TABLE tablen"
  psql -d $DBT -c "DROP TABLE tablem"
  psql -d $DBT -c "DROP TABLESPACE USPACE"
  psql -d $DBT -c "DROP TABLESPACE BSPACE"
  psql -d $DBT -c "DROP TABLESPACE NSPACE"
  psql -d $DBT -c "DROP TABLESPACE MSPACE"
  psql -d $DBT -c "DROP TABLESPACE META"
  dropdb "$DBT"
  RC=$?
  if [ $RC -ne 0 ]
  then
    printf "Database %s does not exist" "$DBT"
  fi
  rm -rf  "$CONT"/tablespace/"$DBT"/*
  rm -rf  "$CONT"/TS_U_SPACE/"$DBT"/*
  rm -rf  "$CONT"/TS_M_SPACE/"$DBT"/*
  rm -rf  "$CONT"/TS_B_SPACE/"$DBT"/*
  rm -rf  "$CONT"/TS_N_SPACE/"$DBT"/*
  rm -rf  "$CONT"/metadata/"$DBT"/*
  rm -rf  "$CONT"/log/"$DBT"/*
  rm -rf  "$PWD"/logretain/*

  mkdir -p "$CONT"/tablespace/"$DBT"
  mkdir -p "$CONT"/TS_U_SPACE/"$DBT"
  mkdir -p "$CONT"/TS_M_SPACE/"$DBT"
  mkdir -p "$CONT"/TS_B_SPACE/"$DBT"
  mkdir -p "$CONT"/TS_N_SPACE/"$DBT"
  mkdir -p "$CONT"/metadata/"$DBT"
  mkdir -p "$CONT"/log/"$DBT"
  mkdir -p "$PWD"/logretain
}
#-------------------------------------------------------
# Backup database
#-------------------------------------------------------
function backup ()
{
  DBT=$1
  pg_basebackup --xlog --format=t -D $BACKUPPATH/$DBT`date +%Y%m%d`
}
#-------------------------------------------------------
# Create tables generated
#-------------------------------------------------------
function create_TNS_table ()
{
  DBT=$1
  TABLESPACE=$(echo $2| tr '[:upper:]' '[:lower:]')
  cat << EOF | psql -d $DBT
BEGIN;
  create table TNS_TABLE (
     tnsname varchar(40) NOT NULL,
     username varchar (40),
     password varchar (40),
     primary key (tnsname)
   ) TABLESPACE $TABLESPACE;
END;
EOF
}

#-------------------------------------------------------
# Create tables generated
#-------------------------------------------------------
function create_table ()
{
  DBT=$1
  TABLENAME=$(echo $2| tr '[:upper:]' '[:lower:]' )
  TABLESPACE=$(echo $3| tr '[:upper:]' '[:lower:]')
  psql -d $DBT -c "create table $TABLENAME ( ind SERIAL, pid integer default 1, crtime timestamp without time zone DEFAULT now(), uptime timestamp without time zone DEFAULT now(), object character varying(255), primary key (ind,crtime)) TABLESPACE $TABLESPACE"
  psql -d $DBT -c "ALTER TABLE $TABLENAME OWNER TO postgres1"

}
#-------------------------------------------------------------------
# Update der Tabellen   
#-------------------------------------------------------------------
update_table ()
{
  DBT=$1
  tablename=$2
  short=${random_string(100):0:1}
  psql -d $DBT -c "update $tablename set object='$obj' where object like '$short%'"
}
#-------------------------------------------------------------------
# Befuellen der Tabellen
#-------------------------------------------------------------------
insert_into_table ()
{
  DBT=$1
  tablename=$(echo $2| tr '[:upper:]' '[:lower:]' )
  TEMPFILE=/tmp/"$USER"_"$tablename"_insert_into_table.sql
  maxc=$3
  ccnt=0
  pid=$$
  > $TEMPFILE
  echo "\\set AUTOCOMMIT off" >> $TEMPFILE
  echo "BEGIN;" >> $TEMPFILE
  while [ $ccnt -lt "$maxc" ]; do
    let ccnt++
    echo "insert into $tablename (pid,object) values($pid,random_string(100));" >> $TEMPFILE
  done
  echo "COMMIT;" >> $TEMPFILE
  execute_sql_from_file $DBT $TEMPFILE
}
#-------------------------------------------------------------------
# Execute statements from file and delte file
#-------------------------------------------------------------------
#    --echo-all \
execute_sql_from_file ()
{
  DBT=$1
  FILE=$2
#  set -e
#  set -u
  if [ $# != 2 ]; then
    echo "please enter a db host and a table suffix"
    exit 1
  fi

  psql \
    -q \
    -X \
    -f $FILE \
    --set AUTOCOMMIT=off \
    --set ON_ERROR_STOP=on \
    $DBT

  psql_exit_status=$?

  if [ $psql_exit_status != 0 ]; then
    echo "psql failed while trying to run this sql script" 1>&2
    exit $psql_exit_status
  fi

  echo "sql script successful"
  rm -f $FILE
}
#-------------------------------------------------------
# Monitoring Table content
#-------------------------------------------------------
function mon_table ()
{
  DBT=$1
  TEMPFILE=/tmp/"$USER"_mon_table.sql
  printf "Table Content\n"
  > $TEMPFILE
  echo "select 'TABLEA Count: ' || count(*) from TABLEA; " >> $TEMPFILE
  echo "select 'TABLEB Count: ' || count(*) from TABLEB; " >> $TEMPFILE
  echo "select 'TABLEC Count: ' || count(*) from TABLEC; " >> $TEMPFILE
  echo "select 'TABLEG Count: ' || count(*) from TABLEG; " >> $TEMPFILE
  echo "select 'TABLEM Count: ' || count(*) from TABLEM; " >> $TEMPFILE
  echo "select 'TABLEN Count: ' || count(*) from TABLEN; " >> $TEMPFILE
  echo "select 'TABLEA Max:   ' || max(uptime) from TABLEA; " >> $TEMPFILE
  echo "select 'TABLEB Max:   ' || max(uptime) from TABLEB; " >> $TEMPFILE
  echo "select 'TABLEC Max:   ' || max(uptime) from TABLEC; " >> $TEMPFILE
  echo "select 'TABLEG Max:   ' || max(uptime) from TABLEG; " >> $TEMPFILE
  echo "select 'TABLEM Max:   ' || max(uptime) from TABLEM; " >> $TEMPFILE
  echo "select 'TABLEN Max:   ' || max(uptime) from TABLEN; " >> $TEMPFILE
  psql -d $DBT -x -q -A -f $TEMPFILE
}
