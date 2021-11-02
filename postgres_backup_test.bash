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


#Die folgenden Szenarien sollen mit diesem Skript nachgestellt werden können.
#Es gibt eine Datenbank in der zwei Tablespaces alte Daten enthalten. Diese Archived - Data sind sehr grosz und werden nicht mehr verändert und stehen für die laufenden Transaktionen nur mehr lesend zur Verfügung.
#1.	In der Datenbank wird eine Tabelle zerstört
#  a.	Restore des Tablespaces welcher die Tabelle enthält in die active Datenbank to point in time RESTOREINTOEXIST
#  b.	Restore des Tablespaces welcher die zerstörte Tabelle enthält in eine neue Datenbank (REDIRECT)
#2.	Datenbank ist zerstört
#  a.	Archive Logs sind noch vorhanden RESTOREWITHARCHLOGS
#  b.	Archive logs sind nicht vorhanden. Dadurch kann nicht vollständig recovered werden. RESTOREWITHOUTARCHLOGS




BACKUPPATH=$PGDATA/../backup
CONTAINERPATH=$PGDATA/../tablespace_PGTST1
LOGPATH=$PGLOG
SYN=PT
source util.bash

#-------------------------------------------------------
# HELP Message
# ------------------------------------------------------
print_help ()
{
  printf "Usage: test_postgres.bash -m <MODE> -d <Databasename Source> \n"
  printf " -m <MODE>\n"
  printf "   MODE can be:\n"
  printf "       INITDB:                               Initialisieren, befuellen und Backup der Datenbank\n"
  printf "       CRTNS:                                Create TNS Table\n"
  printf "       DROPDB:                               Loeschen der Datenbank\n"
  printf "       WORK:                                 Make additional work  and backup\n"
  printf "       CHECK                                 Check records of Database and tablespace State\n"
  printf " -d    Database name\n"
  printf "Please add the name of the Databases\n"
}
#-------------------------------------------------------
# MAIN
# ------------------------------------------------------
while [[ $# -gt 1 ]]
do
key="$1"

case $key in
  -m|--mode)
    MODE="$2"
    shift # past argument
  ;;
  -d|--database)
    DB="$2"
    shift # past argument
  ;;
  -h|--help)
    print_help
    exit 4
  ;;
  *)
      print_help
      exit 4
  ;;
esac
countbig=30000
count=300
shift # past argument or value
done
if [ "$DB" == "" ]
then
  print_help
  exit 8
fi

case $MODE in
  INITDB)
    rm -f $BACKUPPATH/*
    smooth_drop "$DB" $CONTAINERPATH 
    create_db "$DB" $CONTAINERPATH
    create_table "$DB" TABLEN NSPACE
    create_table "$DB" TABLEB BSPACE
    insert_into_table "$DB" TABLEB $countbig &
    insert_into_table "$DB" TABLEN $countbig &
    wait
    create_table "$DB" TABLEA META
    create_table "$DB" TABLEC USPACE
    create_table "$DB" TABLEM MSPACE
    create_table "$DB" TABLEG META
    insert_into_table "$DB" TABLEC $count &
    insert_into_table "$DB" TABLEM $count &
    insert_into_table "$DB" TABLEG $count &
    insert_into_table "$DB" TABLEM $count &
    insert_into_table "$DB" TABLEA $count &
    insert_into_table "$DB" TABLEG $count &
    insert_into_table "$DB" TABLEM $count &
    insert_into_table "$DB" TABLEC $count &
    insert_into_table "$DB" TABLEA $count &
    insert_into_table "$DB" TABLEG $count &
    wait
  ;;
  CRTNS)
    create_TNS_table "$DB" USPACE
  ;;
  DROPDB)
    rm -f $BACKUPPATH/"$DB".*.001
    rm -f $BACKUPPATH/"$DB".ONLINE*.out
    rm -f $BACKUPPATH/"$DB".LOAD*.out
    smooth_drop "$DB" $CONTAINERPATH 
  ;;
  WORK)
    insert_into_table "$DB" TABLEM $count &
    insert_into_table "$DB" TABLEC $count &
    insert_into_table "$DB" TABLEA $count &
    insert_into_table "$DB" TABLEG $count &
    update_table "$DB" TABLEM &
    update_table "$DB" TABLEC &
    update_table "$DB" TABLEA &
    update_table "$DB" TABLEG &
    wait
    insert_into_table "$DB" TABLEM $count &
    insert_into_table "$DB" TABLEC $count &
    insert_into_table "$DB" TABLEA $count &
    insert_into_table "$DB" TABLEG $count &
    update_table "$DB" TABLEM &
    update_table "$DB" TABLEC &
    update_table "$DB" TABLEA &
    update_table "$DB" TABLEG &
    mon_table "$DB"
    insert_into_table "$DB" TABLEM $count &
    insert_into_table "$DB" TABLEC $count &
    insert_into_table "$DB" TABLEA $count &
    insert_into_table "$DB" TABLEG $count &
    update_table "$DB" TABLEM &
    update_table "$DB" TABLEC &
    update_table "$DB" TABLEA &
    update_table "$DB" TABLEG &
    wait
  ;;
  CHECK)
    mon_table "$DB"
  ;;
  *)
    echo wrong mode
    exit 8
  ;;
esac
mon_table $DB
