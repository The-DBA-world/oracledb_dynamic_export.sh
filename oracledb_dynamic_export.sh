# ###################################################################################################################################################
# Ver: 3.4
# EXPORT DATABASE | SCHEMA | TABLE.
# To be run by ORACLE user		
#                                       #   #     #
# Author:       Mahmmoud ADEL         # # # #   ###
#                                   #   #   # #   #
# Created:      03-02-2014          
# Modified:	26-05-2014 Hashed METADATA export lines to clear the confusion.
#		21-08-2014 Added DEGREE OF PARALLELISM calculation.
#               22-01-2020 Passing the export DataPump parameters to a Par file.
#               22-01-2020 Convert the execution of the export in the background NOHUP mode.
#		23-01-2020 Added the option of providing multiple schemas to export.
#               23-01-2020 Added the option of providing multiple tables to export.
#               23-01-2020 Added the option of excluding specific schemas and tables from the Full DB export mode.
#               23-01-2020 Added the option of excluding specific tables from the SCHEMA mode export.
#               28-01-2020 Added the option of COMPRESSING the legacy dump file on the fly for all LEGACY export modes.
#		29-01-2020 Redesigned the parallelism option section to pop-up only when database edition support parallelism.
#		02-02-2020 Added Email Notification option.
#		17-08-2020 Fix a directory creation bug.
# 		03-01-2020 Translation of user input . & ~
#		10-11-2021 Fixed the bug of script hung when entering a blank value for Parallelism degree.
#		30-05-2022 Adding CONTENT mode to allow the user export DDL or DATA ONLY.
#		30-05-2022 Adding the final Par file review before the start of the export job.
#		01-09-2022 Set a Warning message if the Exporter DB USER DBA_BUNDLEEXP7 is already exist and forcefully drop it if the user continue.
# ###################################################################################################################################################

# ###########
# Description:
# ###########
export SRV_NAME="`uname -n`"

echo
echo "=============================================="
echo "This script EXPORTS DATABASE | SCHEMA | TABLE."
echo "=============================================="
echo
sleep 1

# #######################################
# Excluded INSTANCES:
# #######################################
# Here you can mention the instances the script will IGNORE and will NOT run against:
# Use pipe "|" as a separator between each instance name.
# e.g. Excluding: -MGMTDB, ASM instances:

EXL_DB="\-MGMTDB|ASM|APX"                           #Excluded INSTANCES [Will not get reported offline].

# ###########################
# Listing Available Databases:
# ###########################

# Count Instance Numbers:
INS_COUNT=$( ps -ef|grep pmon|grep -v grep|egrep -v ${EXL_DB}|wc -l )

# Exit if No DBs are running:
if [[ $INS_COUNT -eq 0 ]]
 then
   echo "No Database is Running !"
   echo
   return
fi

# If there is ONLY one DB set it as default without prompt for selection:
if [[ $INS_COUNT -eq 1 ]]
 then
   export ORACLE_SID=$( ps -ef|grep pmon|grep -v grep|egrep -v ${EXL_DB}|awk '{print $NF}'|sed -e 's/ora_pmon_//g'|grep -v sed|grep -v "s///g" )

# If there is more than one DB ASK the user to select:
elif [[ $INS_COUNT -gt 1 ]]
 then
    echo
    echo "Select the ORACLE_SID:[Enter the number]"
    echo "---------------------"
    select DB_ID in $( ps -ef|grep pmon|grep -v grep|egrep -v ${EXL_DB}|awk '{print $NF}'|sed -e 's/ora_pmon_//g'|grep -v sed|grep -v "s///g" )
     do
                integ='^[0-9]+$'
                if ! [[ ${REPLY} =~ ${integ} ]] || [ ${REPLY} -gt ${INS_COUNT} ] || [ ${REPLY} -eq 0 ]
                        then
                        echo
                        echo "Error: Not a valid number!"
                        echo
                        echo "Enter a valid NUMBER from the displayed list !: i.e. Enter a number from [1 to ${INS_COUNT}]"
                        echo "----------------------------------------------"
                else
                        export ORACLE_SID=$DB_ID
                        echo 
                        printf "`echo "Selected Instance: ["` `echo -e "\033[33;5m${DB_ID}\033[0m"` `echo "]"`\n"
                        echo
                        break
                fi
     done

fi
# Exit if the user selected a Non Listed Number:
        if [[ -z "${ORACLE_SID}" ]]
         then
          echo "You've Entered An INVALID ORACLE_SID"
          exit
        fi



# #########################
# Getting ORACLE_HOME
# #########################
  ORA_USER=`ps -ef|grep ${ORACLE_SID}|grep pmon|grep -v grep|egrep -v ${EXL_DB}|grep -v "\-MGMTDB"|awk '{print $1}'|tail -1`
  USR_ORA_HOME=`grep -i "^${ORA_USER}:" /etc/passwd| cut -f6 -d ':'|tail -1`

# SETTING ORATAB:
if [[ -f /etc/oratab ]]
  then
ORATAB=/etc/oratab
export ORATAB
## If OS is Solaris:
elif [[ -f /var/opt/oracle/oratab ]]
  then
ORATAB=/var/opt/oracle/oratab
export ORATAB
fi

# ATTEMPT1: Get ORACLE_HOME using pwdx command:
export PGREP=`which pgrep`
export PWDX=`which pwdx`
if [[ -x ${PGREP} ]] && [[ -x ${PWDX} ]]
then
PMON_PID=`pgrep  -lf _pmon_${ORACLE_SID}|awk '{print $1}'`
export PMON_PID
ORACLE_HOME=`pwdx ${PMON_PID} 2>/dev/null|awk '{print $NF}'|sed -e 's/\/dbs//g'`
export ORACLE_HOME
fi

# ATTEMPT2: If ORACLE_HOME not found get it from oratab file:
if [[ ! -f ${ORACLE_HOME}/bin/sqlplus ]]
 then
## If OS is Linux:
if [[ -f /etc/oratab ]]
  then
ORATAB=/etc/oratab
ORACLE_HOME=`grep -v '^\#' ${ORATAB} | grep -v '^$'| grep -i "^${ORACLE_SID}:" | perl -lpe'$_ = reverse' | cut -f3 | perl -lpe'$_ = reverse' |cut -f2 -d':'`
export ORACLE_HOME

## If OS is Solaris:
elif [[ -f /var/opt/oracle/oratab ]]
  then
ORATAB=/var/opt/oracle/oratab
ORACLE_HOME=`grep -v '^\#' ${ORATAB} | grep -v '^$'| grep -i "^${ORACLE_SID}:" | perl -lpe'$_ = reverse' | cut -f3 | perl -lpe'$_ = reverse' |cut -f2 -d':'`
export ORACLE_HOME
fi
fi

# ATTEMPT3: If ORACLE_HOME is in /etc/oratab, use dbhome command:
if [[ ! -f ${ORACLE_HOME}/bin/sqlplus ]]
 then
ORACLE_HOME=`dbhome "${ORACLE_SID}"`
export ORACLE_HOME
fi

# ATTEMPT4: If ORACLE_HOME is still not found, search for the environment variable: [Less accurate]
if [[ ! -f ${ORACLE_HOME}/bin/sqlplus ]]
 then
ORACLE_HOME=`env|grep -i ORACLE_HOME|sed -e 's/ORACLE_HOME=//g'`
export ORACLE_HOME
fi

# ATTEMPT5: If ORACLE_HOME is not found in the environment search user's profile: [Less accurate]
if [[ ! -f ${ORACLE_HOME}/bin/sqlplus ]]
 then
ORACLE_HOME=`grep -h 'ORACLE_HOME=\/' ${USR_ORA_HOME}/.bash_profile ${USR_ORA_HOME}/.*profile | perl -lpe'$_ = reverse' |cut -f1 -d'=' | perl -lpe'$_ = reverse'|tail -1`
export ORACLE_HOME
fi

# ATTEMPT6: If ORACLE_HOME is still not found, search for orapipe: [Least accurate]
if [[ ! -f ${ORACLE_HOME}/bin/sqlplus ]]
 then
	if [[ -x /usr/bin/locate ]]
 	 then
ORACLE_HOME=`locate -i orapipe|head -1|sed -e 's/\/bin\/orapipe//g'`
export ORACLE_HOME
	fi
fi

# TERMINATE: If all above attempts failed to get ORACLE_HOME location, EXIT the script:
if [[ ! -f ${ORACLE_HOME}/bin/sqlplus ]]
 then
  echo "Please export ORACLE_HOME variable in your .bash_profile file under oracle user home directory in order to get this script to run properly"
  echo "e.g."
  echo "export ORACLE_HOME=/u01/app/oracle/product/11.2.0/db_1"
exit
fi

export LD_LIBRARY_PATH=${ORACLE_HOME}/lib

# ########################################
# Exit if the user is not the Oracle Owner:
# ########################################
CURR_USER=`whoami`
	if [[ ${ORA_USER} != ${CURR_USER} ]]; then
	  echo ""
	  echo "You're Running This Sctipt with User: \"${CURR_USER}\" !!!"
	  echo "Please Run This Script With The Right OS User: \"${ORA_USER}\""
	  echo "Script Terminated!"
	  exit
	fi


# ########################
# Getting ORACLE_BASE:
# ########################
# Get ORACLE_BASE from user's profile if not set:

if [[ -z "${ORACLE_BASE}" ]]
 then
  ORACLE_BASE=`grep -h 'ORACLE_BASE=\/' ${USR_ORA_HOME}/.bash* ${USR_ORA_HOME}/.*profile | perl -lpe'$_ = reverse' |cut -f1 -d'=' | perl -lpe'$_ = reverse'|tail -1`
   export ORACLE_BASE
fi


# #########################
# EXPORT Section:
# #########################
# VARIABLES:
# #########
# Date Stamp:
DUMPDATE=`date +%d-%b-%Y`
#PASSHALF=`echo $((RANDOM % 999+7000))`
PASSHALF=`date '+%s'`

# If expdp version is 10g don't use REUSE_DUMPFILES parameter in the script:
VERSION=`strings ${ORACLE_HOME}/bin/expdp|grep Release|awk '{print $3}'`

	case ${VERSION} in
	 10g) REUSE_DUMP='';;
	   *) REUSE_DUMP='REUSE_DUMPFILES=Y';;
#	   *) REUSE_DUMP='REUSE_DUMPFILES=Y COMPRESSION=ALL';;
	esac


# Capturing the CURRENT_SCN to use it for a consistent DATA PUMP export:
#CURRENT_SCN_RAW=$(${ORACLE_HOME}/bin/sqlplus -s '/ as sysdba' << EOF
#set pages 0 lines 1000 feedback off;
#col current_scn for 99999999999999999999999999999999999
#select current_scn from v\$database;
#EOF
#)
#CURRENT_SCN=`echo ${CURRENT_SCN_RAW}| awk '{print $NF}'`
#		case ${CURRENT_SCN} in
#		*[0-9]*) export EXPORTSCN="FLASHBACK_SCN=${CURRENT_SCN}";;
#		*)       export EXPORTSCN="";;
#		esac

VAL33=$(${ORACLE_HOME}/bin/sqlplus -s '/ as sysdba' << EOF
set pages 0 feedback off;
SELECT STATUS FROM V\$INSTANCE;
EOF
)
VAL44=`echo ${VAL33}| awk '{print $NF}'`
		case ${VAL44} in
		"OPEN") echo ;;
		*) echo;echo "ERROR: INSTANCE [${ORACLE_SID}] IS IN STATUS: ${VAL44} !"
		   echo; echo "PLEASE OPEN INSTANCE [${ORACLE_SID}] AND RE-RUN THIS SCRIPT.";echo; exit ;;
		esac

USER_OBJECTS_COUNT_RAW=$(${ORACLE_HOME}/bin/sqlplus -s '/ as sysdba' << EOF
set pages 0 feedback off;
SELECT COUNT(*) FROM DBA_OBJECTS WHERE OWNER='DBA_BUNDLEEXP7';
EOF
)
USER_OBJECTS_COUNT=`echo ${USER_OBJECTS_COUNT_RAW}| awk '{print $NF}'`
		if [ ${USER_OBJECTS_COUNT} -gt 0 ]
		then
		echo
		printf "`echo "The Exporter User [DBA_BUNDLEEXP7] is already EXIST in the database and has [${USER_OBJECTS_COUNT}] objects and "` `echo -e "\033[33;5mwill be DROPPED\033[0m"` `echo " by this script."`\n"
		echo
		fi

# ############################################
# Checking if PARALLELISM option is available:
# ############################################

# Computing the default PARALLEL DEGREE based on CPU count:
        case `uname` in
        Linux ) export PARALLEL_DEGREE=`cat /proc/cpuinfo| grep processor|wc -l`;;
        AIX )   export PARALLEL_DEGREE=`lsdev -C|grep Process|wc -l`;;
        SunOS ) export PARALLEL_DEGREE=`kstat cpu_info|grep core_id|sort -u|wc -l`;;
        HP-UX)  export PARALLEL_DEGREE=`lsdev -C|grep Process|wc -l`;;
        esac

        if [[ ! -z "${PARALLEL_DEGREE##[0-9]*}" ]]
                 then
                 export PARALLEL_DEGREE=1
        fi

CHK_PARALLELISM_OPTION_RAW=$(${ORACLE_HOME}/bin/sqlplus -S "/ as sysdba" << EOF
set pages 0 feedback off echo off;
SELECT count(*) from v\$option where parameter='Parallel execution' and value='TRUE';
exit;
EOF
)
export CHK_PARALLELISM_OPTION=`echo ${CHK_PARALLELISM_OPTION_RAW} | awk '{print $NF}'`


# ##############################
# Prompt for EMAIL Confirmation:
# ##############################

echo "Enter your EMAIL to receive a notification upon the completion of the Export job: [Leave it BLANK or Enter N to Skip the notification]"
echo "================================================================================="
while read EMAILANS
 do
 case ${EMAILANS} in
 ""|"N"|"n"|"NO"|"No"|"no")export EMAILANS=""; export SENDEMAIL=""; echo; break;;
 	*@*.*) export SENDEMAIL="mail -s \"\${JOBSTATUS} on Server ${SRV_NAME}\" \${EMAILID} < \${LOGFILE}"; echo; break;;
 	*)echo ""
   	echo -e "\033[32;5mThis doesn't sound like a valid Email? ${EMAILANS}\033[0m"
   	echo ""
   	echo "Please Enter your Email: [Leave it BLANK or Enter N to Skip this!]"
   	echo "------------------------"
   	echo "i.e. john.smith@xyzcompany.com"
   	echo "";;
 esac
 done

echo "Enter the FULL LOCATION PATH where the EXPORT FILE will be saved under: [e.g. /backup/export]" 
echo "======================================================================"
while read LOC1
do
        case ${LOC1} in
         '') export LOC1=`pwd`;   echo; echo "DIRECTORY TRANSLATED TO: ${LOC1}";; 
        '.') export LOC1=`pwd`;   echo; echo "DIRECTORY TRANSLATED TO: ${LOC1}";;
        '~') export LOC1=${HOME}; echo; echo "DIRECTORY TRANSLATED TO: ${LOC1}";;
        esac
        if [[ -d "${LOC1}" ]] && [[ -r "${LOC1}" ]] && [[ -w "${LOC1}" ]]
        then
        echo "Export File will be saved under: ${LOC1}"; break
        else
        echo; printf "`echo "Please make sure that oracle user has"` `echo -e "\033[33;5mREAD/WRITE\033[0m"` `echo "permissions on the provided directory."`\n"; echo; echo "Enter the complete PATH where the dump file will be saved: [e.g. /backup/export]"
	echo "----------------------------------------------------------"
        fi

done

# ##############################
# Prompt for EMAIL Confirmation:
# ##############################

echo
echo "Do you want to Enable FLASHBACK SCN? [Y|N] [AKA: Export the data in CONSISTENT mode | Default [Y]]"
echo "===================================="
while read FLASCN
 do
 	case ${FLASCN} in
	""|"Y"|"y"|"YES"|"Yes"|"yes")
# Capturing the CURRENT_SCN to use it for a consistent DATA PUMP export:
CURRENT_SCN_RAW=$(${ORACLE_HOME}/bin/sqlplus -s '/ as sysdba' << EOF
set pages 0 lines 1000 feedback off;
col current_scn for 99999999999999999999999999999999999
select current_scn from v\$database;
EOF
)
CURRENT_SCN=`echo ${CURRENT_SCN_RAW}| awk '{print $NF}'`
	export EXPORTSCN="FLASHBACK_SCN=${CURRENT_SCN}"
	echo 
	echo "Data will be exported at the current SCN: [${CURRENT_SCN}]"
	echo
	echo "[Note: If the exported data is too big; make sure the UNDO_RETENTION & UNDO tablespace are big enough.]"
	echo
	break ;;
        *) 
	echo
	echo "FLASHBACK_SCN is DISABLED."
	echo
	export EXPORTSCN=""
	break ;;
 	esac
 done

# ######################
# Export Options:
# ######################
echo
echo "Please Select the EXPORT MODE: [Enter a number]"
echo "=============================="
echo "1. EXPORT FULL DATABASE"
echo "2. EXPORT SCHEMAS"
echo "3. EXPORT TABLES"
echo "[Enter a number from 1 to 3]"
echo ""
while read ANS
 do
 case $ANS in
 1|"EXPORT FULL DATABASE"|"database"|"DATABASE"|"full"|"FULL")echo;echo "Entering EXPORT FULL DATABASE MODE ...";sleep 1

# #######################
# EXPORT DATABASE SECTION:
# #######################
 echo
 echo "WHICH EXPORT UTILITY YOU WANT TO USE: [DEFAULT IS DATAPUMP EXPDP]"
 echo "===================================="
 echo "1) DATAPUMP [EXPDP]    |Pros: Faster when import, Cloud/PARALLELISM compatible, can Exclude schema/tables |Cons: COMPRESSION requires license"
 echo "2) LEGACY EXPORT [EXP] |Pros: COMPRESSION can happen on the fly without license |Cons: Slower when import, No Cloud/PARALLELISM compatibility"
		 while read EXP_TOOL
			do
			case $EXP_TOOL in
			""|"1"|"DATAPUMP"|"datapump"|"DATAPUMP [EXPDP]"|"[EXPDP]"|"EXPDP"|"expdp")


# Prompt the user the PARALLELISM option only if it's available in the DB Edition:
export INT='^[0-9]+$'
if  [[ ${CHK_PARALLELISM_OPTION} =~ ${INT} ]]
then 
	if [ ${CHK_PARALLELISM_OPTION} -eq 1 ]
	then
	echo
	echo "Enter the PARALLEL DEGREE you want to perform the export with PARALLELISM? [If used, The final dump file will be divided into multiple files!]"
	echo "========================================================================="
	echo "[Current CPU Count on this Server is: ${PARALLEL_DEGREE}]"
	echo "Enter a number bigger than 1 to utilize PARALLELISM or enter 0 to disable PARALLELISM"
	echo ""
	while read PARALLEL_ANS
	 do
                # Check if the input is an integer:
                if [[ -z ${PARALLEL_ANS} ]]; then
                export PARALLEL_ANS=0
                fi

		if  [[ ${PARALLEL_ANS} =~ ${INT} ]]
		then
			# Check if the input is greater than 1:
			if [ "${PARALLEL_ANS}" -gt 1 ]
			then
	                 export PARALLEL="PARALLEL=${PARALLEL_ANS}"
			 export PARA="_%u"
			 echo -e "\033[32;5mPARALLELISM ENABLED | The final dump file will be divided into multiple files based on the degree of parallelism you used.\033[0m"
			 echo
			else
			 echo "PARALLELISM DISABLED.";echo ""
			fi
		break
		fi
	 done
	else
	 echo;echo -e "\033[32;5mPARALLELISM option is not available in the current Database Edition.\033[0m"
	fi
fi

# PARAMETER FILE CREATION:
export DUMPFILENAME="EXPORT_FULL_DB_${ORACLE_SID}_${DUMPDATE}${PARA}.dmp"
export LOGFILE="${LOC1}/EXPORT_FULL_DB_${ORACLE_SID}_${DUMPDATE}.log"

PARFILE=${LOC1}/EXPORT_FULL_DB_${ORACLE_SID}.par
echo "# FULL DATABASE EXPORT PARAMETER FILE CREATED BY export_data.sh SCRIPT on [${DUMPDATE}]: [${ORACLE_SID}]" >  ${PARFILE}
echo "FULL=Y"                                                                                   >> ${PARFILE}
echo "DIRECTORY=EXPORT_FILES_DBA_BUNDLE"                                                        >> ${PARFILE}
echo "DUMPFILE=${DUMPFILENAME}"                                                                 >> ${PARFILE}
echo "LOGFILE=EXPORT_FULL_DB_${ORACLE_SID}_${DUMPDATE}.log"                                     >> ${PARFILE}
echo "${EXPORTSCN}"                                                                             >> ${PARFILE}
echo "${REUSE_DUMP}"                                                                            >> ${PARFILE}
echo "${PARALLEL}"                                                                              >> ${PARFILE}


printf "`echo "Do you want to enable the COMPRESSION [Y|N] [N] [Do NOT answer with YES unless you already acquired the"` `echo -e "\033[33;5mAdvanced Compression License\033[0m"` `echo "]"`\n"
         echo "====================================="
while read COMP_ANS
 do
                 case $COMP_ANS in
                 y|Y|yes|YES|Yes) echo;echo "COMPRESSION=ALL" >> ${PARFILE};echo -e "\033[32;5mCompression Enabled.\033[0m";echo; break ;;
		 ""|n|N|no|NO|No) echo; echo "COMPRESSION DISABLED."; echo; break ;;
		 *)               echo;echo "Please Enter a Valid Answer [Y|N]"
                                       echo "---------------------------------";;
		esac
 done

echo
echo "Enter the SCHEMAS you want to EXCLUDE from the export, separating them by comma:"
echo "==============================================================================="
echo "i.e. ANONYMOUS,APPQOSSYS,AUDSYS,BI,CTXSYS,DBSNMP,DIP,DMSYS,DVF,DVSYS,EXDSYS,EXFSYS,GSMADMIN_INTERNAL,GSMCATUSER,GSMUSER,LBACSYS,MDSYS,MGMT_VIEW,MDDATA,MTSSYS,ODM,ODM_MTR,OJVMSYS,OLAPSYS,ORACLE_OCM,ORDDATA,ORDPLUGINS,ORDSYS,OUTLN,SI_INFORMTN_SCHEMA,SPATIAL_CSW_ADMIN,SPATIAL_CSW_ADMIN_USR,SPATIAL_WFS_ADMIN,SPATIAL_WFS_ADMIN_USR,SYS,SYSBACKUP,SYSDG,SYSKM,SYSMAN,SYSTEM,TSMSYS,WKPROXY,WKSYS,WK_TEST,WMSYS,XDB,XTISYS,DSSYS,PERFSTAT,REPADMIN,OEM_ADVISOR,OEM_MONITOR,OLAP_DBA,OLAP_USER,OWBSYS,OWBSYS_AUDIT,APEX_030200"
echo "[Leave it BLANK and hit Enter if you do NOT want to exclude any SCHEMAS]"
echo ""
while read EXCLUDESCHEMAVAR
 do
                 case ${EXCLUDESCHEMAVAR} in
                 "") echo; export EXCLUDESCHEMA=""; break ;;
                  *) echo; export EXCLUDESCHEMA="EXCLUDE=SCHEMA:\"IN('$(sed s/,/\',\'/g <<<${EXCLUDESCHEMAVAR}| tr '[:lower:]' '[:upper:]')')\""
                           echo ${EXCLUDESCHEMA} >> ${PARFILE}; break ;;
                 esac
 done

echo "Enter the TABLES you want to EXCLUDE from the export, separating them by comma:"
echo "=============================================================================="
echo "i.e. EMP,DEPT"
echo "[Leave it BLANK and hit Enter if you do NOT want to exclude any TABLES]"
echo ""
while read EXCLUDETABLEVAR
 do
                 case ${EXCLUDETABLEVAR} in
                 "") echo; export EXCLUDETABLE=""; break ;;
                  *) echo; export EXCLUDETABLE="EXCLUDE=TABLE:\"IN('$(sed s/,/\',\'/g <<<${EXCLUDETABLEVAR}| tr '[:lower:]' '[:upper:]')')\""
                           echo ${EXCLUDETABLE} >> ${PARFILE}; break ;;
                 esac
 done

echo
echo "Enter the CONTENT of data you want to Export:"
echo "============================================="
echo "1. DATA+METADATA [DEFAULT]"
echo "2. METADATA_ONLY [DDL]"
echo "3. DATA_ONLY"
echo ""
while read CONTENTVAR
 do
                 case ${CONTENTVAR} in
                 ""|"DATA+METADATA"|1) echo; echo "EXPORT MODE IS SET TO: [DATA + METADATA]"; echo; break ;;
                 "METADATA_ONLY"|"metadata_only"|"METADATA"|"metadata"|"DDL"|"ddl"|2) echo; export CONTENTVAR="CONTENT=METADATA_ONLY"; echo ${CONTENTVAR} >> ${PARFILE}; echo "EXPORT MODE IS SET TO: [METADATA_ONLY]"; echo; break ;;
		 "DATA_ONLY"|"data_only"|"DATA"|"data"|3)  echo; export CONTENTVAR="CONTENT=DATA_ONLY"; echo ${CONTENTVAR} >> ${PARFILE}; echo "EXPORT MODE IS SET TO: [DATA_ONLY]"; echo; break ;;
		 *) echo; echo "Enter a correct option number between 1 to 3:"
			  echo "--------------------------------------------";;
		esac
 done

echo
echo "Enter the VERSION: [In case you want to import this dump later on a DB with LOWER version] | [Allowed value start from 9.2 and above] "
echo "================="
echo "e.g. If you will import this dump on a 10g DB then enter 10"
echo "For DEFAULT compatibility leave it BLANK."
echo ""
while read VERSION
 do
                 case ${VERSION} in
                 ""|"COMPATIBLE"|"compatible") echo; echo "DUMPFILE COMPATIBILITY version is set to the current DB compatibility level."; echo; break ;;
                 [0-9]) echo; echo "Wrong version number, this value cannot be set lower than 9.2!"
                        echo; echo "Enter a correct version higher than 9.2:"
                              echo "----------------------------------------";;
		  *) echo; VERSION="VERSION=${VERSION}"; echo ${VERSION} >> ${PARFILE}; echo "DUMPFILE COMPATIBILITY version is set to ${VERSION}."; echo; break ;;
                esac
 done


echo
echo "You are almost done!"; echo
sleep 1

echo "Please verify the export settings summary:"
echo "------------------------------------------"
cat ${PARFILE}
echo
sleep 1
echo "Shall we start the EXPORT job now? [[YES] | NO]"
echo "=================================="
while read STARTNOW
do
 case ${STARTNOW} in
      N|n|NO|no) echo; echo "SCRIPT TERMINATED! "; echo; exit;;
 ""|Y|y|YES|yes) echo; echo "STARTING THE EXPORT ..."; echo; break;;
            *) echo "Please enter a valid answer: [YES|NO]";;
 esac
done

cd ${LOC1}
SPOOLFILE2=${LOC1}/AFTER_IMPORT_DATABASE_${ORACLE_SID}_${DUMPDATE}.sql
echo "Creating the Exporter User DBA_BUNDLEEXP7 ..."
echo "Preparing the BEFORE and AFTER import script which will help you import the dump file later ..."

VAL11=$(${ORACLE_HOME}/bin/sqlplus -s '/ as sysdba' << EOF
PROMPT CREATE USER DBA_BUNDLEEXP7 [EXPORTER USER] (WILL BE DROPPED AFTER THE EXPORT) ...
CREATE USER DBA_BUNDLEEXP7 IDENTIFIED BY "BUNdle_#-^${PASSHALF}";
ALTER USER DBA_BUNDLEEXP7 IDENTIFIED BY "BUNdle_#-^${PASSHALF}" ACCOUNT UNLOCK;
GRANT CREATE SESSION TO DBA_BUNDLEEXP7;
GRANT DBA TO DBA_BUNDLEEXP7;
-- The following privileges to workaround Bug 6392040:
GRANT EXECUTE ON SYS.DBMS_DEFER_IMPORT_INTERNAL TO DBA_BUNDLEEXP7;
GRANT EXECUTE ON SYS.DBMS_EXPORT_EXTENSION TO DBA_BUNDLEEXP7;
PROMPT
PROMPT CREATING DIRECTORY EXPORT_FILES_DBA_BUNDLE POINTING TO ${LOC1} ...
CREATE OR REPLACE DIRECTORY EXPORT_FILES_DBA_BUNDLE AS '${LOC1}';
PROMPT
PROMPT CREATING AFTER DATABASE IMPORT SCRIPT ...
PROMPT
SET PAGES 0 TERMOUT OFF LINESIZE 157 ECHO OFF FEEDBACK OFF
SPOOL ${SPOOLFILE2}
SELECT 'PROMPT ' FROM DUAL;
SELECT 'PROMPT COMPILING DATABASE INVALID OBJECTS ...' FROM DUAL;
SELECT '@?/rdbms/admin/utlrp' FROM DUAL;
SELECT '@?/rdbms/admin/utlrp' FROM DUAL;
SELECT 'PROMPT ' FROM DUAL;
SELECT 'PROMPT THE FOLLOWING TRIGGERS ARE OWNED BY SYS SCHEMA AND MAY NOT BE EXIST AFTER THE IMPORT' FROM DUAL;
SELECT 'PROMPT YOU MAY CONSIDER CREATING THE NON EXIST TRIGGERS IF YOU NEED SO:' FROM DUAL;
SELECT 'PROMPT ***************************************************************' FROM DUAL;
SELECT 'PROMPT '||TRIGGER_TYPE||' TRIGGER:  '||TRIGGER_NAME FROM DBA_TRIGGERS WHERE OWNER=UPPER('SYS') ORDER BY 1;
SELECT 'PROMPT ' FROM DUAL;
SELECT 'PROMPT CHECK IF THESE DIRECTORIES ARE POINTING TO THE RIGHT PATHS? ' FROM DUAL;
SELECT 'PROMPT *********************************************************** ' FROM DUAL;
COL DIRECTORY FOR A50
COL DIRECTORY_PATH FOR A100
SELECT 'PROMPT '||OWNER||'.'||DIRECTORY_NAME||':  '||DIRECTORY_PATH FROM DBA_DIRECTORIES;
SELECT 'PROMPT ' FROM DUAL;
SPOOL OFF
EOF
)

echo
# Creation of the Export Script:
export EXPORTSCRIPT=${LOC1}/EXPORTSCRIPT.sh
export EXPORTSCRIPTRUNNER=${LOC1}/EXPORTSCRIPTRUNNER.sh

echo "# Export Script: [Created By DBA_BUNDLE]"							> ${EXPORTSCRIPT}
echo "echo ''"                                                                                  >>${EXPORTSCRIPT}
echo "echo \"While the Export job is running, you can check the STATUS using:\""		>>${EXPORTSCRIPT}
echo "echo \"--------------------------------------------------------------- \""                >>${EXPORTSCRIPT}
echo "echo \"SELECT job_name, operation, job_mode, DEGREE, state FROM dba_datapump_jobs where OPERATION='EXPORT' and state='EXECUTING' and owner_name='DBA_BUNDLEEXP7';\""								                 >>${EXPORTSCRIPT}
echo "echo ''"                                                                                  >>${EXPORTSCRIPT}
echo "echo \"Then you can ATTACH to the export job and control it using:\""  			>>${EXPORTSCRIPT}
echo "echo \"---------------------------------------------------------- \""                     >>${EXPORTSCRIPT}
echo "echo \"expdp DBA_BUNDLEEXP7/\"BUNdle_#-^${PASSHALF}\" ATTACH=<JOB_NAME_FROM_ABOVE_COMMAND>\""   	>>${EXPORTSCRIPT}
echo "echo \"i.e.\""										>>${EXPORTSCRIPT}
echo "echo \"expdp DBA_BUNDLEEXP7/\"BUNdle_#-^${PASSHALF}\" ATTACH=SYS_EXPORT_FULL_01\""	>>${EXPORTSCRIPT}
echo "echo \"To Show the STATUS:....... STATUS\""						>>${EXPORTSCRIPT}
echo "echo \"To KILL the export:....... KILL_JOB\""                                             >>${EXPORTSCRIPT}
echo "echo \"To PAUSE the export:...... STOP_JOB\""                                             >>${EXPORTSCRIPT}
echo "echo \"To RESUME a paused export: START_JOB\""                                            >>${EXPORTSCRIPT}
echo "export ORACLE_SID=${ORACLE_SID}"                                                          >>${EXPORTSCRIPT}
echo "echo ''"                                                                                  >>${EXPORTSCRIPT}
echo "echo 'Running The Export Job Now ...'"                                                    >>${EXPORTSCRIPT}
echo "${ORACLE_HOME}/bin/expdp DBA_BUNDLEEXP7/\"BUNdle_#-^${PASSHALF}\" PARFILE=${PARFILE}"     >>${EXPORTSCRIPT}
echo "echo ''"                                                                                  >>${EXPORTSCRIPT}
echo "echo 'Running Post Export Steps ...'"							>>${EXPORTSCRIPT}
echo "echo ''"											>>${EXPORTSCRIPT}
echo "${ORACLE_HOME}/bin/sqlplus -s '/ as sysdba' << EOF"					>>${EXPORTSCRIPT}
echo "PROMPT"											>>${EXPORTSCRIPT}
echo "PROMPT DROPPING THE EXPORTER USER DBA_BUNDLEEXP7  ..."				>>${EXPORTSCRIPT}
echo "DROP USER DBA_BUNDLEEXP7 CASCADE;"							>>${EXPORTSCRIPT}
echo "EOF"											>>${EXPORTSCRIPT}
echo "echo \"*****************\""								>>${EXPORTSCRIPT}
echo "echo \"IMPORT GUIDELINES:\""								>>${EXPORTSCRIPT}
echo "echo \"*****************\""								>>${EXPORTSCRIPT}
echo "echo \"FLASHBACK SCN used for this export is: ${CURRENT_SCN}\""                           >>${EXPORTSCRIPT}
echo "echo ''"                                                                                  >>${EXPORTSCRIPT}
echo "echo \"Later, AFTER IMPORTING THE DUMPFILE, RUN THIS SQL SCRIPT: ${SPOOLFILE2}\""		>>${EXPORTSCRIPT}
echo "echo \" => IT INCLUDES (HINT FOR TRIGGERS OWNED BY SYS) WHICH WILL NOT BE CREATED BY THE IMPORT PROCESS + COMPILING INVALID OBJECTS.\""  >>${EXPORTSCRIPT}
echo "echo ''"											>>${EXPORTSCRIPT}
echo "echo \"*************************\""							>>${EXPORTSCRIPT}
echo "echo \"EXPORT DUMP FILE LOCATION: ${LOC1}/${DUMPFILENAME}\""				>>${EXPORTSCRIPT}
echo "echo \"*************************\""							>>${EXPORTSCRIPT}
echo "export JOBSTATUS=\`grep \"successfully\\|stopped\\|completed\" ${LOGFILE}|tail -1\`"      >>${EXPORTSCRIPT}
echo "export LOGFILE=${LOGFILE}"                                                                >>${EXPORTSCRIPT}
echo "export EMAILID=\"${EMAILANS}\""                                                           >>${EXPORTSCRIPT}
echo "${SENDEMAIL}"                                                                             >>${EXPORTSCRIPT}

chmod 740 ${EXPORTSCRIPT}

echo
echo "#!/bin/bash"   										> ${EXPORTSCRIPTRUNNER}
echo "nohup sh ${EXPORTSCRIPT}| tee ${LOGFILE} 2>&1 &"  					>>${EXPORTSCRIPTRUNNER}
chmod 740 ${EXPORTSCRIPTRUNNER}
echo -e "\033[32;5mFeel free to EXIT from this session as the EXPORT SCRIPT is running in the BACKGROUND.\033[0m"
source ${EXPORTSCRIPTRUNNER}


## Export METADATA ONLY: <using Legacy EXP because it's more reliable than EXPDP in exporting DDLs>
#echo;echo "CREATING A FILE CONTAINS ALL CREATION [DDL] STATEMENT OF ALL USERS|OBJECTS ...";sleep 1
#${ORACLE_HOME}/bin/exp DBA_BUNDLEEXP7/"BUNdle_#-^${PASSHALF}" FULL=y ROWS=N STATISTICS=NONE FILE=${LOC1}/${ORACLE_SID}_METADATA_${DUMPDATE}.dmp log=${LOC1}/${ORACLE_SID}_METADATA_${DUMPDATE}.log

## Getting READABLE export script: [DUMP REFINING]
#/usr/bin/strings ${LOC1}/${ORACLE_SID}_METADATA_${DUMPDATE}.dmp > ${LOC1}/${ORACLE_SID}_METADATA_REFINED_${DUMPDATE}.trc

			echo; exit ;;
# In case the user will export the FULL database using EXP legacy tool:
			"2"|"LEGACY EXPORT"|"LEGACY"|"EXPORT"|"LEGACY EXPORT [EXP]"|"EXP"|"[EXP]"|"exp"|"legacy export"|"legacy"|"export")
echo
printf "`echo "Do you want to enable the COMPRESSION [Y|N] [N] [COMPRESSION will happen on the fly using mknod] | "` `echo -e "\033[33;5mNo License required\033[0m"` `echo "]"`\n"
         echo "====================================="
while read COMP_ANS
 do
                 case $COMP_ANS in
                 y|Y|yes|YES|Yes) echo;export EXPORTDUMP="${LOC1}/EXPORT_FULL_DB_${ORACLE_SID}_${DUMPDATE}_pipe.dmp"
				       export MKNOD="rm -f ${EXPORTDUMP}; mknod ${EXPORTDUMP} p"
                                       export ZIP="nohup bzip2 -fz < ${EXPORTDUMP} > ${LOC1}/EXPORT_FULL_DB_${ORACLE_SID}_${DUMPDATE}.dmp.bz2 &" 
                                       export EXPORTDUMPOUTPUT="${LOC1}/EXPORT_FULL_DB_${ORACLE_SID}_${DUMPDATE}.dmp.bz2"
				       export REMOVEMKDON="rm -f ${EXPORTDUMP}"
				       export UNZIPMESSAGE="First DE-COMPRESS the file using this command: bunzip2 -f ${EXPORTDUMPOUTPUT}"
                                  echo -e "\033[32;5mCompression Enabled.\033[0m";echo; break ;;
		 ""|n|N|no|NO|No) echo;export MKNOD=""
                                       export ZIP=""
                                       export EXPORTDUMP="${LOC1}/EXPORT_FULL_DB_${ORACLE_SID}_${DUMPDATE}.dmp"
                                       export EXPORTDUMPOUTPUT="${LOC1}/EXPORT_FULL_DB_${ORACLE_SID}_${DUMPDATE}.dmp";break ;;
		 *)               echo;echo "Please Enter a Valid Answer [Y|N]"
                                       echo "---------------------------------";;
		esac
 done

echo
echo "EXPORTING DATABASE $ORACLE_SID [USING LEGACY EXP] ..."
sleep 1
cd ${LOC1}
SPOOLFILE2=${LOC1}/AFTER_IMPORT_DATABASE_${ORACLE_SID}_${DUMPDATE}.sql
echo "Creating the Exporter User DBA_BUNDLEEXP7 ..."
echo "Preparing the BEFORE and AFTER import script which will help you import the dump file later ..."

VAL11=$(${ORACLE_HOME}/bin/sqlplus -s '/ as sysdba' << EOF
PROMPT CREATE USER DBA_BUNDLEEXP7 [EXPORTER USER] (WILL BE DROPPED AFTER THE EXPORT) ...
CREATE USER DBA_BUNDLEEXP7 IDENTIFIED BY "BUNdle_#-^${PASSHALF}" ACCOUNT UNLOCK;
ALTER USER DBA_BUNDLEEXP7 IDENTIFIED BY "BUNdle_#-^${PASSHALF}"  ACCOUNT UNLOCK;
GRANT CREATE SESSION 				TO DBA_BUNDLEEXP7;
GRANT EXP_FULL_DATABASE 			TO DBA_BUNDLEEXP7;
GRANT EXECUTE ON SYS.DBMS_FLASHBACK             TO DBA_BUNDLEEXP7;
-- The following privileges to workaround Bug 6392040:
GRANT EXECUTE ON SYS.DBMS_DEFER_IMPORT_INTERNAL TO DBA_BUNDLEEXP7;
GRANT EXECUTE ON SYS.DBMS_EXPORT_EXTENSION 	TO DBA_BUNDLEEXP7;
PROMPT
PROMPT CREATING DIRECTORY EXPORT_FILES_DBA_BUNDLE POINTING TO ${LOC1} ...
CREATE OR REPLACE DIRECTORY EXPORT_FILES_DBA_BUNDLE AS '${LOC1}';
PROMPT
PROMPT CREATING AFTER DATABASE IMPORT SCRIPT ...
PROMPT
SET PAGES 0 TERMOUT OFF LINESIZE 157 ECHO OFF FEEDBACK OFF
SPOOL ${SPOOLFILE2}
SELECT 'PROMPT COMPILING DATABASE INVALID OBJECTS ...' FROM DUAL;
SELECT '@?/rdbms/admin/utlrp' FROM DUAL;
SELECT '@?/rdbms/admin/utlrp' FROM DUAL;
SELECT 'PROMPT ' FROM DUAL;
SELECT 'PROMPT THE FOLLOWING TRIGGERS ARE OWNED BY SYS SCHEMA AND MAY NOT BE EXIST AFTER THE IMPORT' FROM DUAL;
SELECT 'PROMPT YOU MAY CONSIDER CREATING THE NON EXIST TRIGGERS IF YOU NEED SO:' FROM DUAL;
SELECT 'PROMPT ***************************************************************' FROM DUAL;
SELECT 'PROMPT '||TRIGGER_TYPE||' TRIGGER:  '||TRIGGER_NAME FROM DBA_TRIGGERS WHERE OWNER=UPPER('SYS') ORDER BY 1;
SELECT 'PROMPT ARE THESE DIRECTORIES POINTING TO THE RIGHT PATHS? ' FROM DUAL;
COL DIRECTORY FOR A50
COL DIRECTORY_PATH FOR A100
SELECT 'PROMPT '||OWNER||'.'||DIRECTORY_NAME||':  '||DIRECTORY_PATH FROM DBA_DIRECTORIES;
SPOOL OFF
EOF
)

# Creation of the Post Export Script:
export DUMPFILENAME="EXPORT_FULL_DB_${ORACLE_SID}_${DUMPDATE}${PARA}.dmp"
export LOGFILE="${LOC1}/EXPORT_FULL_DB_${ORACLE_SID}_${DUMPDATE}.log"

export EXPORTSCRIPT=${LOC1}/EXPORTSCRIPT.sh
export EXPORTSCRIPTRUNNER=${LOC1}/EXPORTSCRIPTRUNNER.sh

echo "# Export Script: [Created By DBA_BUNDLE]"							> ${EXPORTSCRIPT}
echo "export ORACLE_SID=${ORACLE_SID}"								>>${EXPORTSCRIPT}
echo "echo 'Running The Export Job Now ...'"							>>${EXPORTSCRIPT}
echo "${MKNOD}"											>>${EXPORTSCRIPT}
echo "sleep 1"											>>${EXPORTSCRIPT}
echo "${ZIP}"	  										>>${EXPORTSCRIPT}
echo "${ORACLE_HOME}/bin/exp DBA_BUNDLEEXP7/\"BUNdle_#-^${PASSHALF}\" FULL=y DIRECT=y CONSISTENT=y STATISTICS=NONE FEEDBACK=100000 ${EXPORTSCN} RESUMABLE=y RESUMABLE_NAME=DBA_BUNDLE_EXPORT RESUMABLE_TIMEOUT=86400 FILE=${EXPORTDUMP} log=${LOC1}/EXPORT_FULL_DB_${ORACLE_SID}_${DUMPDATE}.log"  >>${EXPORTSCRIPT}

echo "echo ''"                                                                                  >>${EXPORTSCRIPT}
echo "echo 'Running Post Export Steps ...'"                                                     >>${EXPORTSCRIPT}
echo "echo ''"                                                                                  >>${EXPORTSCRIPT}
echo "${ORACLE_HOME}/bin/sqlplus -s '/ as sysdba' << EOF"                                       >>${EXPORTSCRIPT}
echo "PROMPT"                                                                                   >>${EXPORTSCRIPT}
echo "PROMPT DROPPING THE EXPORTER USER DBA_BUNDLEEXP7  ..."                            >>${EXPORTSCRIPT}
echo "DROP USER DBA_BUNDLEEXP7 CASCADE;"                                                        >>${EXPORTSCRIPT}
echo "EOF"                                                                                      >>${EXPORTSCRIPT}
echo "sleep 3"											>>${EXPORTSCRIPT}
echo "${REMOVEMKDON}"										>>${EXPORTSCRIPT}
echo "echo \"*****************\""                                                               >>${EXPORTSCRIPT}
echo "echo \"IMPORT GUIDELINES:\""                                                              >>${EXPORTSCRIPT}
echo "echo \"*****************\""                                                               >>${EXPORTSCRIPT}
echo "echo \"FLASHBACK SCN used for this export is: ${CURRENT_SCN}\""                           >>${EXPORTSCRIPT}
echo "echo ''"                                                                                  >>${EXPORTSCRIPT}
echo "echo \"${UNZIPMESSAGE}\""                                                                 >>${EXPORTSCRIPT}
echo "echo \"Later, AFTER IMPORTING THE DUMPFILE, RUN THIS SQL SCRIPT: ${SPOOLFILE2}\""   	>>${EXPORTSCRIPT}
echo "echo \" => IT INCLUDES (HINT FOR TRIGGERS OWNED BY SYS) WHICH WILL NOT BE CREATED BY THE IMPORT PROCESS + COMPILING INVALID OBJECTS.\""   >>${EXPORTSCRIPT}
echo "echo ''"                                                                                  >>${EXPORTSCRIPT}
echo "echo \"**************************\""                                                      >>${EXPORTSCRIPT}
echo "echo \"EXPORT DUMP FILE LOCATION: ${EXPORTDUMPOUTPUT}\""                                  >>${EXPORTSCRIPT}
echo "echo \"**************************\""                                                      >>${EXPORTSCRIPT}
echo "export JOBSTATUS=\`grep \"successfully\\|stopped\\|completed\" ${LOGFILE}|tail -1\`"      >>${EXPORTSCRIPT}
echo "export LOGFILE=${LOGFILE}"                                                                >>${EXPORTSCRIPT}
echo "export EMAILID=\"${EMAILANS}\""                                                           >>${EXPORTSCRIPT}
echo "${SENDEMAIL}"                                                                             >>${EXPORTSCRIPT}


chmod 740 ${EXPORTSCRIPT}

echo
echo "#!/bin/bash"                                                                              > ${EXPORTSCRIPTRUNNER}
echo "nohup sh ${EXPORTSCRIPT}| tee ${LOGFILE} 2>&1 &"   					>>${EXPORTSCRIPTRUNNER}
chmod 740 ${EXPORTSCRIPTRUNNER}
echo -e "\033[32;5mFeel free to EXIT from this session as the EXPORT SCRIPT is running in the BACKGROUND.\033[0m"
source ${EXPORTSCRIPTRUNNER}

## Export METADATA ONLY: <using Legacy EXP because it's more reliable than EXPDP in exporting DDLs>
#echo
#echo "CREATING A FILE CONTAINS ALL CREATION [DDL] STATEMENT OF ALL USERS|OBJECTS ..."
#sleep 1
#${ORACLE_HOME}/bin/exp DBA_BUNDLEEXP7/"BUNdle_#-^${PASSHALF}" FULL=y ROWS=N STATISTICS=NONE FILE=${LOC1}/${ORACLE_SID}_METADATA_${DUMPDATE}.dmp log=${LOC1}/${ORACLE_SID}_METADATA_${DUMPDATE}.log
## Removing Extra Bad characters: [DUMP REFINING]
#/usr/bin/strings ${LOC1}/${ORACLE_SID}_METADATA_${DUMPDATE}.dmp > ${LOC1}/${ORACLE_SID}_METADATA_REFINED_${DUMPDATE}.trc

#echo
#echo "EXTRA FILES:"
#echo "-----------"
#echo "METADATA ONLY DUMP FILE <IMPORTABLE with [legacy exp utility]>: ${LOC1}/${ORACLE_SID}_METADATA_${DUMPDATE}.dmp"
#echo "DDL Script FILE <READABLE | Cannot be Imported>: ${LOC1}/${ORACLE_SID}_METADATA_REFINED_${DUMPDATE}.trc"
#echo "*****************************************************************"
                        echo; exit ;;
			*) echo "Enter a valid number:"
			   echo "====================="
			   echo "i.e."
			   echo "1 for expdp tool"
			   echo "2 for exp tool"
			   echo ;;
			esac
			done
 break;;
 2|"EXPORT SCHEMAS"|"database"|"DATABASE"|"schema"|"schemas"|"SCHEMA"|"SCHEMAS")
 echo
 echo "Entering EXPORT SCHEMA MODE ..."
 sleep 1

# ######################
# EXPORT SCHEMA SECTION:
# ######################

 echo
 echo "WHICH EXPORT UTILITY YOU WANT TO USE: [1) DATAPUMP [EXPDP]]"
 echo "===================================="
 echo "1) DATAPUMP [EXPDP]    |Pros: Faster when import, Cloud/PARALLELISM compatible, can Exclude schema/tables |Cons: COMPRESSION requires license"
 echo "2) LEGACY EXPORT [EXP] |Pros: COMPRESSION can happen on the fly without license |Cons: Slower when import, No Cloud/PARALLELISM compatibility"
		 	while read EXP_TOOL
			do
			case $EXP_TOOL in
			""|"1"|"DATAPUMP"|"datapump"|"DATAPUMP [EXPDP]"|"[EXPDP]"|"EXPDP"|"expdp")

if  [[ ${CHK_PARALLELISM_OPTION} =~ ${INT} ]]
then
        if [ ${CHK_PARALLELISM_OPTION} -eq 1 ]
        then
        echo
        echo "Enter the PARALLEL DEGREE you want to perform the export with PARALLELISM? [If used, The final dump file will be divided into multiple files!]"
        echo "========================================================================="
        echo "[Current CPU Count on this Server is: ${PARALLEL_DEGREE}]"
        echo "Enter a number bigger than 1 to utilize PARALLELISM or enter 0 to disable PARALLELISM"
        echo ""
        while read PARALLEL_ANS
         do
                # Check if the input is an integer:
		if [[ -z ${PARALLEL_ANS} ]]; then
		export PARALLEL_ANS=0
		fi

                if  [[ ${PARALLEL_ANS} =~ ${INT} ]]
                then
                        # Check if the input is greater than 1:
                        if [ "${PARALLEL_ANS}" -gt 1 ]
                        then
                         export PARALLEL="PARALLEL=${PARALLEL_ANS}"
                         export PARA="_%u"
                         echo -e "\033[32;5mPARALLELISM ENABLED | The final dump file will be divided into multiple files based on the degree of parallelism you used.\033[0m"
			 echo
                        else
                         echo "PARALLELISM DISABLED.";echo ""
                        fi
                break
                fi
         done
        else
         echo;echo -e "\033[32;5mPARALLELISM option is not available in the current Database Edition.\033[0m"
        fi
fi

# PARAMETER FILE CREATION:
export DUMPFILENAME="EXPORT_SCHEMA_${ORACLE_SID}_${DUMPDATE}${PARA}.dmp"
export LOGFILE="${LOC1}/EXPORT_SCHEMA_${ORACLE_SID}_${DUMPDATE}.log"

# PARAMETER FILE CREATION:
PARFILE=${LOC1}/EXPORT_SCHEMA_DB_${ORACLE_SID}.par
echo "# SCHEMA EXPORT PARAMETER FILE CREATED BY export_data.sh SCRIPT on [${DUMPDATE}]: [${ORACLE_SID}]" > ${PARFILE}
echo "DIRECTORY=EXPORT_FILES_DBA_BUNDLE"                        >> ${PARFILE}
echo "DUMPFILE=${DUMPFILENAME}"                                 >> ${PARFILE}
echo "LOGFILE=EXPORT_SCHEMA_${ORACLE_SID}_${DUMPDATE}.log"      >> ${PARFILE}
echo "${EXPORTSCN}"                                             >> ${PARFILE}
echo "${REUSE_DUMP}"                                            >> ${PARFILE}
echo "${PARALLEL}"                                              >> ${PARFILE}

echo
echo "Enter the SCHEMAS you want to export, separating them by comma:"
echo "=============================================================="
echo "i.e. HR,SCOTT,OE"
echo ""
while read SCHEMASVAR
 do
                 case ${SCHEMASVAR} in
                 "") echo; echo "Please Enter the Schema Name you want to export:"
                           echo "-----------------------------------------------"
			   echo "i.e. SCOTT,HR,OE"
			   echo "";;
                  *) 	   echo
                           # Convert User's input into UPPERCASE:
                           export SCHEMASVAR="$(echo ${SCHEMASVAR}| tr [:lower:] [:upper:])"
		           export SCHEMA="SCHEMAS=${SCHEMASVAR}"
                           echo ${SCHEMA} >> ${PARFILE}
                           export SCHEMALIST="'$(sed s/,/\',\'/g <<<${SCHEMASVAR}| tr '[:lower:]' '[:upper:]')'"; break ;;
                 esac
 done


			echo ""
			echo "Enter the TABLES you want to EXCLUDE from the export, separating them by comma:"
			echo "==============================================================================="
			echo "i.e. EMP,DEPT"
			echo "[Leave it BLANK and hit Enter if you do NOT want to exclude any TABLES]"
			echo ""
			while read EXCLUDETABLEVAR
			 do
                 		case ${EXCLUDETABLEVAR} in
                 		"") echo; export EXCLUDETABLE=""; break ;;
                  		*) echo; export EXCLUDETABLE="EXCLUDE=TABLE:\"IN('$(sed s/,/\',\'/g <<<${EXCLUDETABLEVAR}| tr '[:lower:]' '[:upper:]')')\""
                           	echo ${EXCLUDETABLE} >> ${PARFILE}; break ;;
                 		esac
 			 done

echo
printf "`echo "Do you want to enable the COMPRESSION [Y|N] [N] [Do NOT answer with YES unless you already acquired the"` `echo -e "\033[33;5mAdvanced Compression License\033[0m"` `echo "]"`\n"
         echo "====================================="
while read COMP_ANS
 do
                 case $COMP_ANS in
                 y|Y|yes|YES|Yes) echo;echo "COMPRESSION=ALL" >> ${PARFILE};echo -e "\033[32;5mCompression Enabled.\033[0m";echo; break ;;
                 ""|n|N|no|NO|No) echo; echo "COMPRESSION DISABLED."; echo; break ;;
                 *)               echo;echo "Please Enter a Valid Answer: [Y|N]"
                                       echo "----------------------------";;
                esac
 done

echo
echo "Enter the CONTENT of data you want to Export:"
echo "============================================="
echo "1. DATA+METADATA [DEFAULT]"
echo "2. METADATA_ONLY [DDL]"
echo "3. DATA_ONLY"
echo ""
while read CONTENTVAR
 do
                 case ${CONTENTVAR} in
                 ""|"DATA+METADATA"|1) echo; echo "EXPORT MODE IS SET TO: [DATA + METADATA]"; echo; break ;;
                 "METADATA_ONLY"|"metadata_only"|"METADATA"|"metadata"|"DDL"|"ddl"|2) echo; export CONTENTVAR="CONTENT=METADATA_ONLY"; echo ${CONTENTVAR} >> ${PARFILE}; echo "EXPORT MODE IS SET TO: [METADATA_ONLY]"; echo; break ;;
                 "DATA_ONLY"|"data_only"|"DATA"|"data"|3)  echo; export CONTENTVAR="CONTENT=DATA_ONLY"; echo ${CONTENTVAR} >> ${PARFILE}; echo "EXPORT MODE IS SET TO: [DATA_ONLY]"; echo; break ;;
                 *) echo; echo "Enter a correct option number between 1 to 3:"
                          echo "--------------------------------------------";;
                esac
 done

echo
echo "Enter the VERSION: [In case you want to import this dump later on a DB with LOWER version] | [Allowed value start from 9.2 and above] "
echo "================="
echo "e.g. If you will import this dump on a 10g DB then enter 10"
echo "For DEFAULT compatibility leave it BLANK."
echo ""
while read VERSION
 do
                 case ${VERSION} in
                 ""|"COMPATIBLE"|"compatible") echo; echo "DUMPFILE COMPATIBILITY version is set to the current DB compatibility level."; echo; break ;;
                 [0-9]) echo; echo "Wrong version number, this value cannot be set lower than 9.2!"
                        echo; echo "Enter a correct version higher than 9.2:"
                              echo "----------------------------------------";;
                  *) echo; VERSION="VERSION=${VERSION}"; echo ${VERSION} >> ${PARFILE}; echo "DUMPFILE COMPATIBILITY version is set to ${VERSION}."; echo; break ;;
                esac
 done


echo
echo "You are almost done!"; echo
sleep 1

echo "Please verify the export settings summary:"
echo "------------------------------------------"
cat ${PARFILE}
echo
sleep 1
echo "Shall we start the EXPORT job now? [[YES] | NO]"
echo "=================================="
while read STARTNOW
do
 case ${STARTNOW} in
      N|n|NO|no) echo; echo "SCRIPT TERMINATED! "; echo; exit;;
 ""|Y|y|YES|yes) echo; echo "STARTING THE EXPORT ..."; echo; break;;
            *) echo "Please enter a valid answer: [YES|NO]";;
 esac
done



cd ${LOC1}
SPOOLFILE1=${LOC1}/BEFORE_IMPORT_SCHEMA_${ORACLE_SID}_${DUMPDATE}.sql
SPOOLFILE2=${LOC1}/AFTER_IMPORT_SCHEMA_${ORACLE_SID}_${DUMPDATE}.sql

echo "Creating the Exporter User DBA_BUNDLEEXP7 ..."
echo "Preparing the BEFORE and AFTER import script which will help you import the dump file later ..."

VAL11=$(${ORACLE_HOME}/bin/sqlplus -s '/ as sysdba' << EOF
PROMPT CREATE USER DBA_BUNDLEEXP7 [EXPORTER USER] (WILL BE DROPPED AFTER THE EXPORT) ...
CREATE USER DBA_BUNDLEEXP7 IDENTIFIED BY "BUNdle_#-^${PASSHALF}";
ALTER USER DBA_BUNDLEEXP7 IDENTIFIED BY "BUNdle_#-^${PASSHALF}"  ACCOUNT UNLOCK;
GRANT CREATE SESSION TO DBA_BUNDLEEXP7;
GRANT DBA TO DBA_BUNDLEEXP7;
-- The following privileges to workaround Bug 6392040:
GRANT EXECUTE ON SYS.DBMS_DEFER_IMPORT_INTERNAL TO DBA_BUNDLEEXP7;
GRANT EXECUTE ON SYS.DBMS_EXPORT_EXTENSION TO DBA_BUNDLEEXP7;
PROMPT
PROMPT CREATING DIRECTORY EXPORT_FILES_DBA_BUNDLE POINTING TO ${LOC1} ...
CREATE OR REPLACE DIRECTORY EXPORT_FILES_DBA_BUNDLE AS '${LOC1}';
PROMPT
PROMPT CREATING BEFORE SCHEMA IMPORT SCRIPT ...
PROMPT
SET PAGES 0 TERMOUT OFF LINESIZE 157 ECHO OFF FEEDBACK OFF
SPOOL ${SPOOLFILE1}
SELECT 'CREATE USER ' || u.username ||' IDENTIFIED ' ||' BY VALUES ''' || c.password || ''' DEFAULT TABLESPACE ' || u.default_tablespace ||' TEMPORARY TABLESPACE ' || u.temporary_tablespace ||' PROFILE ' || u.profile || case when account_status= 'OPEN' then ';' else ' Account LOCK;' end "--Creation Statement"
FROM dba_users u,user$ c where u.username=c.name and u.username in (${SCHEMALIST})
UNION
SELECT 'CREATE ROLE '||GRANTED_ROLE||';' FROM DBA_ROLE_PRIVS WHERE GRANTEE in (${SCHEMALIST})
UNION
select 'GRANT '||GRANTED_ROLE||' TO '||GRANTEE|| case when ADMIN_OPTION='YES' then ' WITH ADMIN OPTION;' else ';' end "Granted Roles"
from dba_role_privs where grantee in (${SCHEMALIST})
UNION
select 'GRANT '||PRIVILEGE||' TO '||GRANTEE|| case when ADMIN_OPTION='YES' then ' WITH ADMIN OPTION;' else ';' end "Granted System Privileges"
from dba_sys_privs where grantee in (${SCHEMALIST})
UNION
select 'GRANT '||PRIVILEGE||' ON '||OWNER||'.'||TABLE_NAME||' TO '||GRANTEE||case when GRANTABLE='YES' then ' WITH GRANT OPTION;' else ';' end "Granted Object Privileges" from DBA_TAB_PRIVS where GRANTEE in (${SCHEMALIST});
SPOOL OFF
PROMPT CREATING AFTER SCHEMA IMPORT SCRIPT ...
PROMPT
SPOOL ${SPOOLFILE2}
select 'GRANT '||PRIVILEGE||' ON '||OWNER||'.'||TABLE_NAME||' TO '||GRANTEE||case when GRANTABLE='YES' then ' WITH GRANT OPTION;' else ';' end "Granted Object Privileges" from DBA_TAB_PRIVS where OWNER in (${SCHEMALIST})
UNION
SELECT 'CREATE PUBLIC SYNONYM '||SYNONYM_NAME||' FOR '||TABLE_OWNER||'.'||TABLE_NAME||';' FROM DBA_SYNONYMS WHERE TABLE_OWNER in (${SCHEMALIST}) AND OWNER=UPPER('PUBLIC');
PROMPT
SELECT 'PROMPT COMPILING DATABASE INVALID OBJECTS ...' FROM DUAL;
SELECT '@?/rdbms/admin/utlrp' FROM DUAL;
SELECT '@?/rdbms/admin/utlrp' FROM DUAL;
SELECT 'PROMPT ' FROM DUAL;
SELECT 'PROMPT THE FOLLOWING TRIGGERS ARE OWNED BY OTHER USERS BUT ARE DEPENDANT ON THE EXPORTED SCHEMAS OBJECTS' FROM DUAL;
SELECT 'PROMPT YOU MAY CONSIDER TO CREATE THEM AFTER THE SCHEMA IMPORT IF YOU NEED SO:' FROM DUAL;
SELECT 'PROMPT **********************************************************************' FROM DUAL;
SELECT 'PROMPT '||TRIGGER_TYPE||' TRIGGER:  '||OWNER||'.'||TRIGGER_NAME||'   =>ON TABLE:  '||TABLE_OWNER||'.'||TABLE_NAME FROM DBA_TRIGGERS WHERE TABLE_OWNER IN (${SCHEMALIST}) AND OWNER NOT IN (${SCHEMALIST}) ORDER BY 1;

SPOOL OFF
EOF
)

echo
# Creation of the Export Script:
export EXPORTSCRIPT=${LOC1}/EXPORTSCRIPT.sh
export EXPORTSCRIPTRUNNER=${LOC1}/EXPORTSCRIPTRUNNER.sh

echo "# Export Script: [Created By DBA_BUNDLE]"                                                 > ${EXPORTSCRIPT}
echo "echo ''"                                                                                  >>${EXPORTSCRIPT}
echo "echo \"While the Export job is running, you can check the STATUS using:\""                >>${EXPORTSCRIPT}
echo "echo \"--------------------------------------------------------------- \""                >>${EXPORTSCRIPT}
echo "echo \"SELECT job_name, operation, job_mode, DEGREE, state FROM dba_datapump_jobs where OPERATION='EXPORT' and state='EXECUTING' and owner_name='DBA_BUNDLEEXP7';\""                                                                      	     >>${EXPORTSCRIPT}
echo "echo ''"                                                                                  >>${EXPORTSCRIPT}
echo "echo \"Then you can ATTACH to the export job and control it using:\""                     >>${EXPORTSCRIPT}
echo "echo \"---------------------------------------------------------- \""                     >>${EXPORTSCRIPT}
echo "echo \"expdp DBA_BUNDLEEXP7/\"BUNdle_#-^${PASSHALF}\" ATTACH=<JOB_NAME_FROM_ABOVE_COMMAND>\""     >>${EXPORTSCRIPT}
echo "echo \"i.e.\""                                                                            >>${EXPORTSCRIPT}
echo "echo \"expdp DBA_BUNDLEEXP7/\"BUNdle_#-^${PASSHALF}\" ATTACH=SYS_EXPORT_SCHEMA_01\""      >>${EXPORTSCRIPT}
echo "echo \"To Show the STATUS:....... STATUS\""                                               >>${EXPORTSCRIPT}
echo "echo \"To KILL the export:....... KILL_JOB\""                                             >>${EXPORTSCRIPT}
echo "echo \"To PAUSE the export:...... STOP_JOB\""                                             >>${EXPORTSCRIPT}
echo "echo \"To RESUME a paused export: START_JOB\""                                            >>${EXPORTSCRIPT}
echo "export ORACLE_SID=${ORACLE_SID}"                                                          >>${EXPORTSCRIPT}
echo "echo ''"                                                                                  >>${EXPORTSCRIPT}
echo "echo 'Running The Export Job Now ...'"                                                    >>${EXPORTSCRIPT}
echo "${ORACLE_HOME}/bin/expdp DBA_BUNDLEEXP7/\"BUNdle_#-^${PASSHALF}\" PARFILE=${PARFILE}"     >>${EXPORTSCRIPT}
echo "echo ''"                                                                                  >>${EXPORTSCRIPT}
echo "echo 'Running Post Export Steps ...'"                                                     >>${EXPORTSCRIPT}
echo "echo ''"                                                                                  >>${EXPORTSCRIPT}
echo "${ORACLE_HOME}/bin/sqlplus -s '/ as sysdba' << EOF"                                       >>${EXPORTSCRIPT}
echo "PROMPT"                                                                                   >>${EXPORTSCRIPT}
echo "PROMPT DROPPING THE EXPORTER USER DBA_BUNDLEEXP7  ..."                            >>${EXPORTSCRIPT}
echo "DROP USER DBA_BUNDLEEXP7 CASCADE;"                                                        >>${EXPORTSCRIPT}
echo "EOF"                                                                                      >>${EXPORTSCRIPT}
echo "echo \"*****************\""                                                               >>${EXPORTSCRIPT}
echo "echo \"IMPORT GUIDELINES:\""                                                              >>${EXPORTSCRIPT}
echo "echo \"*****************\""                                                               >>${EXPORTSCRIPT}
echo "echo \"FLASHBACK SCN used for this export is: ${CURRENT_SCN}\""                           >>${EXPORTSCRIPT}
echo "echo ''"                                                                                  >>${EXPORTSCRIPT}
echo "echo \"BEFORE IMPORTING THE DUMPFILE IT'S RECOMMENDED TO RUN THIS SQL SCRIPT: ${SPOOLFILE1}\""  >>${EXPORTSCRIPT}
echo "echo \"It includes (USER|ROLES|GRANTED PRIVILEGES CREATION STATEMENTS), WHICH WILL NOT BE CREATED DURING THE IMPORT PROCESS.\"" >>${EXPORTSCRIPT}
echo "echo ''"                                                                                  >>${EXPORTSCRIPT}
echo "echo \"AFTER IMPORTING THE DUMPFILE, RUN THIS SQL SCRIPT: ${SPOOLFILE2}\""        	>>${EXPORTSCRIPT}
echo "echo \"It includes (Public Synonyms DDLs, Privileges granted to others, Hints for Triggers owned by others but depending on the exported schemas objects) + COMPILING INVALID OBJECTS, SUCH STUFF WILL NOT BE CARRIED OUT BY THE IMPORT PROCESS.\""    >>${EXPORTSCRIPT}
echo "echo ''"                                                                                  >>${EXPORTSCRIPT}
echo "echo \"**************************\""                                                      >>${EXPORTSCRIPT}
echo "echo \"EXPORT DUMP FILE LOCATION: ${LOC1}/${DUMPFILENAME}\"" 				>>${EXPORTSCRIPT}
echo "echo \"**************************\""                                                      >>${EXPORTSCRIPT}
echo "export JOBSTATUS=\`grep \"successfully\\|stopped\\|completed\" ${LOGFILE}|tail -1\`"      >>${EXPORTSCRIPT}
echo "export LOGFILE=${LOGFILE}"                                                                >>${EXPORTSCRIPT}
echo "export EMAILID=\"${EMAILANS}\""                                                           >>${EXPORTSCRIPT}
echo "${SENDEMAIL}"                                                                             >>${EXPORTSCRIPT}


chmod 740 ${EXPORTSCRIPT}

echo
echo "#!/bin/bash"                                                                              > ${EXPORTSCRIPTRUNNER}
echo "nohup sh ${EXPORTSCRIPT}| tee ${LOGFILE} 2>&1 &" 						>>${EXPORTSCRIPTRUNNER}
chmod 740 ${EXPORTSCRIPTRUNNER}
echo -e "\033[32;5mFeel free to EXIT from this session as the EXPORT SCRIPT is running in the BACKGROUND.\033[0m"
source ${EXPORTSCRIPTRUNNER}

## Export METADATA ONLY: <using Legacy EXP because it's more reliable than EXPDP in exporting DDLs>
#echo;echo "CREATING A FILE CONTAINS ALL CREATION [DDL] STATEMENT OF ALL USERS|OBJECTS ...";sleep 1
#${ORACLE_HOME}/bin/exp DBA_BUNDLEEXP7/"BUNdle_#-^${PASSHALF}" FULL=y ROWS=N STATISTICS=NONE FILE=${LOC1}/${ORACLE_SID}_METADATA_${DUMPDATE}.dmp log=${LOC1}/${ORACLE_SID}_METADATA_${DUMPDATE}.log

## Getting READABLE export script: [DUMP REFINING]
#/usr/bin/strings ${LOC1}/${ORACLE_SID}_METADATA_${DUMPDATE}.dmp > ${LOC1}/${ORACLE_SID}_METADATA_REFINED_${DUMPDATE}.trc

			echo; exit ;;
			"2"|"LEGACY EXPORT"|"LEGACY"|"EXPORT"|"LEGACY EXPORT [EXP]"|"EXP"|"[EXP]"|"exp"|"legacy export"|"legacy"|"export")

DUMPFILE="${LOC1}/EXPORT_SCHEMA_${ORACLE_SID}_${DUMPDATE}.dmp"
LOGFILE="${LOC1}/EXPORT_SCHEMA_${ORACLE_SID}_${DUMPDATE}.log"

echo
echo "Enter the SCHEMAS you want to export, separating them by comma:"
echo "=============================================================="
echo "i.e. HR,SCOTT,OE"
echo ""
while read SCHEMASVAR
 do
                 case ${SCHEMASVAR} in
                 "") echo; echo "Please Enter the Schema Name you want to export: [i.e. SCOTT,HR,OE]"
                           echo "-----------------------------------------------";;
                  *)       echo
                           # Convert User's input into UPPERCASE:
                           export SCHEMASVAR="$(echo ${SCHEMASVAR}| tr [:lower:] [:upper:])"
                           export SCHEMALIST="'$(sed s/,/\',\'/g <<<${SCHEMASVAR}| tr '[:lower:]' '[:upper:]')'"; break ;;
                 esac
 done

export EXPORTDUMP="${LOC1}/EXPORT_SCHEMA_${ORACLE_SID}_${DUMPDATE}.dmp"
export LOGFILE="${LOC1}/EXPORT_SCHEMA_${ORACLE_SID}_${DUMPDATE}.log"

echo
printf "`echo "Do you want to enable the COMPRESSION [Y|N] [N] [COMPRESSION will happen on the fly using mknod |"` `echo -e "\033[33;5mNo License required\033[0m"` `echo "]"`\n"
         echo "====================================="
while read COMP_ANS
 do
                 case $COMP_ANS in
                 y|Y|yes|YES|Yes) echo;export EXPORTDUMP="${LOC1}/EXPORT_SCHEMA_${ORACLE_SID}_${DUMPDATE}_pipe.dmp"
                                       export MKNOD="rm -f ${EXPORTDUMP}; mknod ${EXPORTDUMP} p"
                                       export ZIP="nohup bzip2 -fz < ${EXPORTDUMP} > ${LOC1}/EXPORT_SCHEMA_${ORACLE_SID}_${DUMPDATE}.dmp.bz2 &"
                                       export EXPORTDUMPOUTPUT="${LOC1}/EXPORT_SCHEMA_${ORACLE_SID}_${DUMPDATE}.dmp.bz2"
                                       export REMOVEMKDON="rm -f ${EXPORTDUMP}"
                                       export UNZIPMESSAGE="First DE-COMPRESS the file using this command: bunzip2 -f ${EXPORTDUMPOUTPUT}"
                                  echo -e "\033[32;5mCompression Enabled.\033[0m";echo; break ;;
                 ""|n|N|no|NO|No) echo;export MKNOD=""
                                       export ZIP=""
                                       export EXPORTDUMP="${LOC1}/EXPORT_SCHEMA_${ORACLE_SID}_${DUMPDATE}.dmp"
                                       export EXPORTDUMPOUTPUT="${LOC1}/EXPORT_SCHEMA_${ORACLE_SID}_${DUMPDATE}.dmp";break ;;
                 *)               echo;echo "Please Enter a Valid Answer [Y|N]"
                                       echo "---------------------------------";;
                esac
 done


cd ${LOC1}
SPOOLFILE1=${LOC1}/BEFORE_IMPORT_SCHEMA_${ORACLE_SID}_${DUMPDATE}.sql
SPOOLFILE2=${LOC1}/AFTER_IMPORT_SCHEMA_${ORACLE_SID}_${DUMPDATE}.sql

echo "Creating the Exporter User DBA_BUNDLEEXP7 ..."
echo "Preparing the BEFORE and AFTER import script which will help you import the dump file later ..."

VAL11=$(${ORACLE_HOME}/bin/sqlplus -s '/ as sysdba' << EOF
PROMPT CREATE USER DBA_BUNDLEEXP7 [EXPORTER USER] (WILL BE DROPPED AFTER THE EXPORT) ...
CREATE USER DBA_BUNDLEEXP7 IDENTIFIED BY "BUNdle_#-^${PASSHALF}";
ALTER USER DBA_BUNDLEEXP7 IDENTIFIED BY "BUNdle_#-^${PASSHALF}"  ACCOUNT UNLOCK;
GRANT CREATE SESSION TO DBA_BUNDLEEXP7;
GRANT DBA TO DBA_BUNDLEEXP7;
-- The following privileges to workaround Bug 6392040:
GRANT EXECUTE ON SYS.DBMS_DEFER_IMPORT_INTERNAL TO DBA_BUNDLEEXP7;
GRANT EXECUTE ON SYS.DBMS_EXPORT_EXTENSION TO DBA_BUNDLEEXP7;
PROMPT
PROMPT CREATING DIRECTORY EXPORT_FILES_DBA_BUNDLE POINTING TO ${LOC1} ...
CREATE OR REPLACE DIRECTORY EXPORT_FILES_DBA_BUNDLE AS '${LOC1}';
PROMPT
PROMPT CREATING BEFORE SCHEMA IMPORT SCRIPT ...
PROMPT
SET PAGES 0 TERMOUT OFF LINESIZE 157 ECHO OFF FEEDBACK OFF
SPOOL ${SPOOLFILE1}
SELECT 'CREATE USER ' || u.username ||' IDENTIFIED ' ||' BY VALUES ''' || c.password || ''' DEFAULT TABLESPACE ' || u.default_tablespace ||' TEMPORARY TABLESPACE ' || u.temporary_tablespace ||' PROFILE ' || u.profile || case when account_status= 'OPEN' then ';' else ' Account LOCK;' end "--Creation Statement"
FROM dba_users u,user$ c where u.username=c.name and u.username in (${SCHEMALIST})
UNION
SELECT 'CREATE ROLE '||GRANTED_ROLE||';' FROM DBA_ROLE_PRIVS WHERE GRANTEE in (${SCHEMALIST})
UNION
select 'GRANT '||GRANTED_ROLE||' TO '||GRANTEE|| case when ADMIN_OPTION='YES' then ' WITH ADMIN OPTION;' else ';' end "Granted Roles"
from dba_role_privs where grantee in (${SCHEMALIST})
UNION
select 'GRANT '||PRIVILEGE||' TO '||GRANTEE|| case when ADMIN_OPTION='YES' then ' WITH ADMIN OPTION;' else ';' end "Granted System Privileges"
from dba_sys_privs where grantee in (${SCHEMALIST})
UNION
select 'GRANT '||PRIVILEGE||' ON '||OWNER||'.'||TABLE_NAME||' TO '||GRANTEE||case when GRANTABLE='YES' then ' WITH GRANT OPTION;' else ';' end "Granted Object Privileges" from DBA_TAB_PRIVS where GRANTEE in (${SCHEMALIST});
SPOOL OFF
PROMPT CREATING AFTER SCHEMA IMPORT SCRIPT ...
PROMPT
SPOOL ${SPOOLFILE2}
select 'GRANT '||PRIVILEGE||' ON '||OWNER||'.'||TABLE_NAME||' TO '||GRANTEE||case when GRANTABLE='YES' then ' WITH GRANT OPTION;' else ';' end "Granted Object Privileges" from DBA_TAB_PRIVS where OWNER in (${SCHEMALIST})
UNION
SELECT 'CREATE PUBLIC SYNONYM '||SYNONYM_NAME||' FOR '||TABLE_OWNER||'.'||TABLE_NAME||';' FROM DBA_SYNONYMS WHERE TABLE_OWNER in (${SCHEMALIST}) AND OWNER=UPPER('PUBLIC');
PROMPT
SELECT 'PROMPT COMPILING DATABASE INVALID OBJECTS ...' FROM DUAL;
SELECT '@?/rdbms/admin/utlrp' FROM DUAL;
SELECT '@?/rdbms/admin/utlrp' FROM DUAL;
SELECT 'PROMPT ' FROM DUAL;
SELECT 'PROMPT THE FOLLOWING TRIGGERS ARE OWNED BY OTHER USERS BUT ARE DEPENDANT ON THE EXPORTED SCHEMA OBJECTS' FROM DUAL;
SELECT 'PROMPT YOU MAY CONSIDER TO CREATE THEM AFTER THE SCHEMA IMPORT IF YOU NEED SO:' FROM DUAL;
SELECT 'PROMPT **********************************************************************' FROM DUAL;
SELECT 'PROMPT '||TRIGGER_TYPE||' TRIGGER:  '||OWNER||'.'||TRIGGER_NAME||'   =>ON TABLE:  '||TABLE_OWNER||'.'||TABLE_NAME FROM DBA_TRIGGERS WHERE TABLE_OWNER in (${SCHEMALIST}) AND OWNER not in (${SCHEMALIST}) ORDER BY 1;
SPOOL OFF
EOF
)

# Creation of the Post Export Script:
export EXPORTSCRIPT=${LOC1}/EXPORTSCRIPT.sh
export EXPORTSCRIPTRUNNER=${LOC1}/EXPORTSCRIPTRUNNER.sh

echo "# Export Script: [Created By DBA_BUNDLE]"							> ${EXPORTSCRIPT}
echo "export ORACLE_SID=${ORACLE_SID}"								>>${EXPORTSCRIPT}
echo "echo ''"                                                                                  >>${EXPORTSCRIPT}
echo "echo 'Running The Export Job Now ...'"							>>${EXPORTSCRIPT}
echo "${MKNOD}"											>>${EXPORTSCRIPT}
echo "sleep 1"											>>${EXPORTSCRIPT}
echo "${ZIP}"	  										>>${EXPORTSCRIPT}
echo "${ORACLE_HOME}/bin/exp DBA_BUNDLEEXP7/\"BUNdle_#-^${PASSHALF}\" OWNER=${SCHEMASVAR} DIRECT=y CONSISTENT=y STATISTICS=NONE FEEDBACK=100000 ${EXPORTSCN} RESUMABLE=y RESUMABLE_NAME=DBA_BUNDLE_EXPORT RESUMABLE_TIMEOUT=86400 FILE=${EXPORTDUMP} log=${LOGFILE}">>${EXPORTSCRIPT}

echo "echo ''"                                                                                  >>${EXPORTSCRIPT}
echo "echo 'Running Post Export Steps ...'"                                                     >>${EXPORTSCRIPT}
echo "echo ''"                                                                                  >>${EXPORTSCRIPT}
echo "${ORACLE_HOME}/bin/sqlplus -s '/ as sysdba' << EOF"                                       >>${EXPORTSCRIPT}
echo "PROMPT"                                                                                   >>${EXPORTSCRIPT}
echo "PROMPT DROPPING THE EXPORTER USER DBA_BUNDLEEXP7  ..."                            >>${EXPORTSCRIPT}
echo "DROP USER DBA_BUNDLEEXP7 CASCADE;"                                                        >>${EXPORTSCRIPT}
echo "EOF"                                                                                      >>${EXPORTSCRIPT}
echo "echo ''"                                                                                  >>${EXPORTSCRIPT}
echo "sleep 3"											>>${EXPORTSCRIPT}
echo "${REMOVEMKDON}"										>>${EXPORTSCRIPT}
echo "echo \"*****************\""                                                               >>${EXPORTSCRIPT}
echo "echo \"IMPORT GUIDELINES:\""                                                              >>${EXPORTSCRIPT}
echo "echo \"*****************\""                                                               >>${EXPORTSCRIPT}
echo "echo \"FLASHBACK SCN used for this export is: ${CURRENT_SCN}\""                           >>${EXPORTSCRIPT}
echo "echo ''"                                                                                  >>${EXPORTSCRIPT}
echo "echo \"${UNZIPMESSAGE}\""                                                                 >>${EXPORTSCRIPT}
echo "echo ''"                                                                                  >>${EXPORTSCRIPT}
echo "echo \"BEFORE IMPORTING THE DUMPFILE IT'S RECOMMENDED TO RUN THIS SQL SCRIPT: ${SPOOLFILE1}\""  >>${EXPORTSCRIPT}
echo "echo \"It includes (USER|ROLES|GRANTED PRIVILEGES CREATION STATEMENTS), WHICH WILL NOT BE CREATED DURING THE IMPORT PROCESS.\"" >>${EXPORTSCRIPT}
echo "echo ''"                                                                                  >>${EXPORTSCRIPT}
echo "echo \"AFTER IMPORTING THE DUMPFILE, RUN THIS SQL SCRIPT: ${SPOOLFILE2}\""        	>>${EXPORTSCRIPT}
echo "echo \"It includes (Public Synonyms DDLs, Privileges granted to others, Hints for Triggers owned by others but depending on the exported schemas objects) + COMPILING INVALID OBJECTS, SUCH STUFF WILL NOT BE CARRIED OUT BY THE IMPORT PROCESS.\""    >>${EXPORTSCRIPT}
echo "echo ''"                                                                                  >>${EXPORTSCRIPT}
echo "echo \"**************************\""                                                      >>${EXPORTSCRIPT}
echo "echo \"EXPORT DUMP FILE LOCATION: ${EXPORTDUMPOUTPUT}\""                                  >>${EXPORTSCRIPT}
echo "echo \"**************************\""                                                      >>${EXPORTSCRIPT}
echo "export JOBSTATUS=\`grep \"successfully\\|stopped\\|completed\" ${LOGFILE}|tail -1\`"      >>${EXPORTSCRIPT}
echo "export LOGFILE=${LOGFILE}"                                                                >>${EXPORTSCRIPT}
echo "export EMAILID=\"${EMAILANS}\""                                                           >>${EXPORTSCRIPT}
echo "${SENDEMAIL}"                                                                             >>${EXPORTSCRIPT}


chmod 740 ${EXPORTSCRIPT}

echo
echo "#!/bin/bash"                                                                              > ${EXPORTSCRIPTRUNNER}
echo "nohup sh ${EXPORTSCRIPT}| tee ${LOGFILE} 2>&1 &" 						>>${EXPORTSCRIPTRUNNER}
chmod 740 ${EXPORTSCRIPTRUNNER}
echo -e "\033[32;5mFeel free to EXIT from this session as the EXPORT SCRIPT is running in the BACKGROUND.\033[0m"
source ${EXPORTSCRIPTRUNNER}


## Export METADATA ONLY: <using Legacy EXP because it's more reliable than EXPDP in exporting DDLs>
#echo
#echo "CREATING A FILE CONTAINS ALL CREATION [DDL] STATEMENT OF ALL USERS|OBJECTS ..."
#sleep 1
#${ORACLE_HOME}/bin/exp DBA_BUNDLEEXP7/"BUNdle_#-^${PASSHALF}" OWNER=${SCHEMA_NAME} ROWS=N STATISTICS=NONE FILE=${LOC1}/${SCHEMA_NAME}_${ORACLE_SID}_METADATA_${DUMPDATE}.dmp log=${LOC1}/${SCHEMA_NAME}_${ORACLE_SID}_METADATA_${DUMPDATE}.log

## Removing Extra Bad characters: [DUMP REFINING]
#/usr/bin/strings ${LOC1}/${SCHEMA_NAME}_${ORACLE_SID}_METADATA_${DUMPDATE}.dmp > ${LOC1}/${SCHEMA_NAME}_${ORACLE_SID}_METADATA_REFINED_${DUMPDATE}.trc

                        echo; exit ;;
                        *) echo "Enter a valid number:"
                           echo "====================="
                           echo "i.e."
                           echo "1 for expdp tool"
                           echo "2 for exp tool"
                           echo ;;
                        esac
                        done

 break;;
 3|"EXPORT TABLES"|"TABLES"|"tables"|"table") echo; echo "Entering EXPORT TABLE MODE ...";echo;sleep 1

# #####################
# EXPORT TABLE SECTION:
# #####################
echo
echo "Enter the TABLES you want to export, separating them by comma:"
echo "=============================================================="
echo "i.e. HR.EMPLOYEES,HR.DEPARTMENTS,SCOTT.BONUS"
echo ""
while read TABLESVAR
 do
                 case ${TABLESVAR} in
                 "") echo; echo "Please mention the tables you want to export:"
                           echo "--------------------------------------------"
			   echo "i.e. HR.EMPLOYEES,HR.DEPARTMENTS,SCOTT.BONUS"
			   echo "";;
                  *)       echo
                           # Convert User's input into UPPERCASE:
                           export TABLESVAR="$(echo ${TABLESVAR}| tr [:lower:] [:upper:])"
                           export TABLELIST="'$(sed s/,/\',\'/g <<<${TABLESVAR}| tr '[:lower:]' '[:upper:]')'"; break ;;
                 esac
 done


echo "WHICH EXPORT UTILITY YOU WANT TO USE: [1) DATAPUMP [EXPDP]]"
echo "===================================="
 echo "1) DATAPUMP [EXPDP]    |Pros: Faster when import, Cloud/PARALLELISM compatible, can Exclude schema/tables |Cons: COMPRESSION requires license"
 echo "2) LEGACY EXPORT [EXP] |Pros: COMPRESSION can happen on the fly without license |Cons: Slower when import, No Cloud/PARALLELISM compatibility"
			while read EXP_TOOL
			do
			case $EXP_TOOL in
			""|"1"|"DATAPUMP"|"datapump"|"DATAPUMP [EXPDP]"|"[EXPDP]"|"EXPDP"|"expdp")

if  [[ ${CHK_PARALLELISM_OPTION} =~ ${INT} ]]
then
        if [ ${CHK_PARALLELISM_OPTION} -eq 1 ]
        then
        echo
        echo "Enter the PARALLEL DEGREE you want to perform the export with PARALLELISM? [If used, The final dump file will be divided into multiple files!]"
        echo "========================================================================="
        echo "[Current CPU Count on this Server is: ${PARALLEL_DEGREE}]"
        echo "Enter a number bigger than 1 to utilize PARALLELISM or enter 0 to disable PARALLELISM"
        echo ""
        while read PARALLEL_ANS
         do
                # Check if the input is an integer:
                if [[ -z ${PARALLEL_ANS} ]]; then
                export PARALLEL_ANS=0
                fi

                if  [[ ${PARALLEL_ANS} =~ ${INT} ]]
                then
                        # Check if the input is greater than 1:
                        if [ "${PARALLEL_ANS}" -gt 1 ]
                        then
                         export PARALLEL="PARALLEL=${PARALLEL_ANS}"
                         export PARA="_%u"
                         echo -e "\033[32;5mPARALLELISM ENABLED | The final dump file will be divided into multiple files based on the degree of parallelism you used.\033[0m"
			 echo
                        else
                         echo "PARALLELISM DISABLED.";echo ""
                        fi
                break
                fi
         done
        else
         echo;echo -e "\033[32;5mPARALLELISM option is not available in the current Database Edition.\033[0m"
        fi
fi

# PARAMETER FILE CREATION:
export DUMPFILENAME="EXPORT_TABLE_${ORACLE_SID}_${DUMPDATE}${PARA}.dmp"
export LOGFILE="${LOC1}/EXPORT_TABLE_${ORACLE_SID}_${DUMPDATE}.log"

# PARAMETER FILE CREATION:
PARFILE=${LOC1}/EXPORT_TABLE_DB_${ORACLE_SID}.par
echo "# TABLE EXPORT PARAMETER FILE CREATED BY export_data.sh SCRIPT on [${DUMPDATE}]: [${ORACLE_SID}]" > ${PARFILE}
echo "DIRECTORY=EXPORT_FILES_DBA_BUNDLE"                        >> ${PARFILE}
echo "DUMPFILE=${DUMPFILENAME}"                                 >> ${PARFILE}
echo "LOGFILE=EXPORT_TABLE_${ORACLE_SID}_${DUMPDATE}.log"       >> ${PARFILE}
echo "${EXPORTSCN}"                                             >> ${PARFILE}
echo "${REUSE_DUMP}"                                            >> ${PARFILE}
echo "TABLES=${TABLESVAR}"                                      >> ${PARFILE}
echo "${PARALLEL}"                                              >> ${PARFILE}

echo
printf "`echo "Do you want to enable the COMPRESSION [Y|N] [N] [Do NOT answer with YES unless you already acquired the"` `echo -e "\033[33;5mAdvanced Compression License\033[0m"` `echo "]"`\n"
         echo "====================================="

while read COMP_ANS
 do                 case $COMP_ANS in
    		    y|Y|yes|YES|Yes) echo;echo "COMPRESSION=ALL" >> ${PARFILE};echo -e "\033[32;5mCompression Enabled.\033[0m";echo; break ;;
                    ""|n|N|no|NO|No) echo; echo "COMPRESSION DISABLED."; echo; break ;;
                    *)               echo;echo "Please Enter a Valid Answer: [Y|N]"
                                          echo "----------------------------";;
                    esac
 done


echo
echo "Enter the CONTENT of data you want to Export:"
echo "============================================="
echo "1. DATA+METADATA [DEFAULT]"
echo "2. METADATA_ONLY [DDL]"
echo "3. DATA_ONLY"
echo ""
while read CONTENTVAR
 do
                 case ${CONTENTVAR} in
                 ""|"DATA+METADATA"|1) echo; echo "EXPORT MODE IS SET TO: [DATA + METADATA]"; echo; break ;;
                 "METADATA_ONLY"|"metadata_only"|"METADATA"|"metadata"|"DDL"|"ddl"|2) echo; export CONTENTVAR="CONTENT=METADATA_ONLY"; echo ${CONTENTVAR} >> ${PARFILE}; echo "EXPORT MODE IS SET TO: [METADATA_ONLY]"; echo; break ;;
                 "DATA_ONLY"|"data_only"|"DATA"|"data"|3)  echo; export CONTENTVAR="CONTENT=DATA_ONLY"; echo ${CONTENTVAR} >> ${PARFILE}; echo "EXPORT MODE IS SET TO: [DATA_ONLY]"; echo; break ;;
                 *) echo; echo "Enter a correct option number between 1 to 3:"
                          echo "--------------------------------------------";;
                esac
 done

echo
echo "Enter the VERSION: [In case you want to import this dump later on a DB with LOWER version] | [Allowed value start from 9.2 and above] "
echo "================="
echo "e.g. If you will import this dump on a 10g DB then enter 10"
echo "For DEFAULT compatibility leave it BLANK."
echo ""
while read VERSION
 do
                 case ${VERSION} in
                 ""|"COMPATIBLE"|"compatible") echo; echo "DUMPFILE COMPATIBILITY version is set to the current DB compatibility level."; echo; break ;;
                 [0-9]) echo; echo "Wrong version number, this value cannot be set lower than 9.2!"
                        echo; echo "Enter a correct version higher than 9.2:"
                              echo "----------------------------------------";;
                  *) echo; VERSION="VERSION=${VERSION}"; echo ${VERSION} >> ${PARFILE}; echo "DUMPFILE COMPATIBILITY version is set to ${VERSION}."; echo; break ;;
                esac
 done


echo
echo "You are almost done!"; echo
sleep 1

echo "Please verify the export settings summary:"
echo "------------------------------------------"
cat ${PARFILE}
echo
sleep 1
echo "Shall we start the EXPORT job now? [[YES] | NO]"
echo "=================================="
while read STARTNOW
do
 case ${STARTNOW} in
      N|n|NO|no) echo; echo "SCRIPT TERMINATED! "; echo; exit;;
 ""|Y|y|YES|yes) echo; echo "STARTING THE EXPORT ..."; echo; break;;
            *) echo "Please enter a valid answer: [YES|NO]";;
 esac
done


echo "Creating the Exporter User DBA_BUNDLEEXP7 ..."
echo "Preparing the BEFORE and AFTER import script which will help you import the dump file later ..."

SPOOLFILE2=${LOC1}/AFTER_IMPORT_TABLE_${DUMPDATE}.sql

VAL11=$(${ORACLE_HOME}/bin/sqlplus -s '/ as sysdba' << EOF
PROMPT CREATE USER DBA_BUNDLEEXP7 [EXPORTER USER] (WILL BE DROPPED AFTER THE EXPORT) ...
CREATE USER DBA_BUNDLEEXP7 IDENTIFIED BY "BUNdle_#-^${PASSHALF}";
ALTER USER DBA_BUNDLEEXP7 IDENTIFIED BY "BUNdle_#-^${PASSHALF}" ACCOUNT UNLOCK;
GRANT CREATE SESSION TO DBA_BUNDLEEXP7;
GRANT DBA TO DBA_BUNDLEEXP7;
-- The following privileges to workaround Bug 6392040:
GRANT EXECUTE ON SYS.DBMS_DEFER_IMPORT_INTERNAL TO DBA_BUNDLEEXP7;
GRANT EXECUTE ON SYS.DBMS_EXPORT_EXTENSION TO DBA_BUNDLEEXP7;
PROMPT CREATING DIRECTORY EXPORT_FILES_DBA_BUNDLE POINTING TO ${LOC1} ...
CREATE OR REPLACE DIRECTORY EXPORT_FILES_DBA_BUNDLE AS '${LOC1}';
PROMPT
PROMPT CREATING AFTER TABLE IMPORT SCRIPT ...
PROMPT
SET PAGES 0 TERMOUT OFF LINESIZE 157 ECHO OFF FEEDBACK OFF
SPOOL ${SPOOLFILE2}
SELECT 'CREATE SYNONYM '||OWNER||'.'||SYNONYM_NAME||' FOR '||TABLE_OWNER||'.'||TABLE_NAME||';' FROM DBA_SYNONYMS
WHERE TABLE_OWNER||'.'||TABLE_NAME in (${TABLELIST}) AND OWNER <> UPPER('PUBLIC')
UNION
SELECT 'CREATE PUBLIC SYNONYM '||SYNONYM_NAME||' FOR '||TABLE_OWNER||'.'||TABLE_NAME||';' FROM DBA_SYNONYMS
WHERE TABLE_OWNER||'.'||TABLE_NAME in (${TABLELIST}) AND OWNER=UPPER('PUBLIC');
SPOOL OFF
EOF
)

# Creation of the Export Script:
export EXPORTSCRIPT=${LOC1}/EXPORTSCRIPT.sh
export EXPORTSCRIPTRUNNER=${LOC1}/EXPORTSCRIPTRUNNER.sh

echo "# Export Script: [Created By DBA_BUNDLE]"                                                 > ${EXPORTSCRIPT}
echo "echo ''"                                                                                  >>${EXPORTSCRIPT}
echo "echo \"While the Export job is running, you can check the STATUS using:\""                >>${EXPORTSCRIPT}
echo "echo \"--------------------------------------------------------------- \""                >>${EXPORTSCRIPT}
echo "echo \"SELECT job_name, operation, job_mode, DEGREE, state FROM dba_datapump_jobs where OPERATION='EXPORT' and state='EXECUTING' and owner_name='DBA_BUNDLEEXP7';\""                                                                      	     >>${EXPORTSCRIPT}
echo "echo ''"                                                                                  >>${EXPORTSCRIPT}
echo "echo \"Then you can ATTACH to the export job and control it using:\""                     >>${EXPORTSCRIPT}
echo "echo \"---------------------------------------------------------- \""                     >>${EXPORTSCRIPT}
echo "echo \"expdp DBA_BUNDLEEXP7/\"BUNdle_#-^${PASSHALF}\" ATTACH=<JOB_NAME_FROM_ABOVE_COMMAND>\""     >>${EXPORTSCRIPT}
echo "echo \"i.e.\""                                                                            >>${EXPORTSCRIPT}
echo "echo \"expdp DBA_BUNDLEEXP7/\"BUNdle_#-^${PASSHALF}\" ATTACH=SYS_EXPORT_TABLE_01\""       >>${EXPORTSCRIPT}
echo "echo \"To Show the STATUS:....... STATUS\""                                               >>${EXPORTSCRIPT}
echo "echo \"To KILL the export:....... KILL_JOB\""                                             >>${EXPORTSCRIPT}
echo "echo \"To PAUSE the export:...... STOP_JOB\""                                             >>${EXPORTSCRIPT}
echo "echo \"To RESUME a paused export: START_JOB\""                                            >>${EXPORTSCRIPT}
echo "export ORACLE_SID=${ORACLE_SID}"                                                          >>${EXPORTSCRIPT}
echo "echo ''"                                                                                  >>${EXPORTSCRIPT}
echo "echo 'Running The Export Job Now ...'"                                                    >>${EXPORTSCRIPT}
echo "${ORACLE_HOME}/bin/expdp DBA_BUNDLEEXP7/\"BUNdle_#-^${PASSHALF}\" PARFILE=${PARFILE}"     >>${EXPORTSCRIPT}
echo "echo ''"                                                                                  >>${EXPORTSCRIPT}
echo "echo 'Running Post Export Steps ...'"                                                     >>${EXPORTSCRIPT}
echo "echo ''"                                                                                  >>${EXPORTSCRIPT}
echo "${ORACLE_HOME}/bin/sqlplus -s '/ as sysdba' << EOF"                                       >>${EXPORTSCRIPT}
echo "PROMPT"                                                                                   >>${EXPORTSCRIPT}
echo "PROMPT DROPPING THE EXPORTER USER DBA_BUNDLEEXP7  ..."                            >>${EXPORTSCRIPT}
echo "DROP USER DBA_BUNDLEEXP7 CASCADE;"                                                        >>${EXPORTSCRIPT}
echo "EOF"                                                                                      >>${EXPORTSCRIPT}
echo "echo \"*****************\""                                                               >>${EXPORTSCRIPT}
echo "echo \"IMPORT GUIDELINES:\""                                                              >>${EXPORTSCRIPT}
echo "echo \"*****************\""                                                               >>${EXPORTSCRIPT}
echo "echo \"FLASHBACK SCN used for this export is: ${CURRENT_SCN}\""                           >>${EXPORTSCRIPT}
echo "echo ''"                                                                                  >>${EXPORTSCRIPT}
echo "echo \"AFTER IMPORTING THE DUMPFILE, RUN THIS SQL SCRIPT: ${SPOOLFILE2}\""                >>${EXPORTSCRIPT}
echo "echo \"IT INCLUDES (PRIVATE & PUBLIC SYNONYMS DDLS) WHICH WILL NOT BE HANDELED BY THE IMPORT PROCESS.\""      >>${EXPORTSCRIPT}
echo "echo ''"                                                                                  >>${EXPORTSCRIPT}
echo "echo \"**************************\""                                                      >>${EXPORTSCRIPT}
echo "echo \"EXPORT DUMP FILE LOCATION: ${LOC1}/${DUMPFILENAME}\""   				>>${EXPORTSCRIPT}
echo "echo \"**************************\""                                                      >>${EXPORTSCRIPT}
echo "export JOBSTATUS=\`grep \"successfully\\|stopped\\|completed\" ${LOGFILE}|tail -1\`"      >>${EXPORTSCRIPT}
echo "export LOGFILE=${LOGFILE}"                                                                >>${EXPORTSCRIPT}
echo "export EMAILID=\"${EMAILANS}\""                                                           >>${EXPORTSCRIPT}
echo "${SENDEMAIL}"                                                                             >>${EXPORTSCRIPT}


chmod 740 ${EXPORTSCRIPT}

echo
echo "#!/bin/bash"                                                                              > ${EXPORTSCRIPTRUNNER}
echo "nohup sh ${EXPORTSCRIPT}| tee ${LOGFILE} 2>&1 &"  					>>${EXPORTSCRIPTRUNNER}
chmod 740 ${EXPORTSCRIPTRUNNER}
echo -e "\033[32;5mFeel free to EXIT from this session as the EXPORT SCRIPT is running in the BACKGROUND.\033[0m"
source ${EXPORTSCRIPTRUNNER}

			echo; exit ;;
			"2"|"LEGACY EXPORT"|"LEGACY"|"EXPORT"|"LEGACY EXPORT [EXP]"|"EXP"|"[EXP]"|"exp"|"legacy export"|"legacy"|"export")

export EXPORTDUMP="${LOC1}/EXPORT_TABLE_${ORACLE_SID}_${DUMPDATE}.dmp"
export LOGFILE="${LOC1}/EXPORT_TABLE_${ORACLE_SID}_${DUMPDATE}.log"

echo
printf "`echo "Do you want to enable the COMPRESSION [Y|N] [N] [COMPRESSION will happen on the fly using mknod |"` `echo -e "\033[33;5mNo License required\033[0m"` `echo "]"`\n"
         echo "====================================="
while read COMP_ANS
 do
                 case $COMP_ANS in
                 y|Y|yes|YES|Yes) echo;export EXPORTDUMP="${LOC1}/EXPORT_TABLE_${ORACLE_SID}_${DUMPDATE}_pipe.dmp"
                                       export MKNOD="rm -f ${EXPORTDUMP}; mknod ${EXPORTDUMP} p"
                                       export ZIP="nohup bzip2 -fz < ${EXPORTDUMP} > ${LOC1}/EXPORT_TABLE_${ORACLE_SID}_${DUMPDATE}.dmp.bz2 &"
                                       export EXPORTDUMPOUTPUT="${LOC1}/EXPORT_TABLE_${ORACLE_SID}_${DUMPDATE}.dmp.bz2"
                                       export REMOVEMKDON="rm -f ${EXPORTDUMP}"
                                       export UNZIPMESSAGE="First DE-COMPRESS the file using this command: bunzip2 -f ${EXPORTDUMPOUTPUT}"
                                  echo -e "\033[32;5mCompression Enabled.\033[0m";echo; break ;;
                 ""|n|N|no|NO|No) echo;export MKNOD=""
                                       export ZIP=""
                                       export EXPORTDUMP="${LOC1}/EXPORT_TABLE_${ORACLE_SID}_${DUMPDATE}.dmp"
                                       export EXPORTDUMPOUTPUT="${LOC1}/EXPORT_TABLE_${ORACLE_SID}_${DUMPDATE}.dmp";break ;;
                 *)               echo;echo "Please Enter a Valid Answer [Y|N]"
                                       echo "---------------------------------";;
                esac
 done


SPOOLFILE2=${LOC1}/AFTER_IMPORT_TABLE_DB_${ORACLE_SID}_${DUMPDATE}.sql

echo "Creating the Exporter User DBA_BUNDLEEXP7 ..."
echo "Preparing the BEFORE and AFTER import script which will help you import the dump file later ..."

VAL11=$(${ORACLE_HOME}/bin/sqlplus -s '/ as sysdba' << EOF
PROMPT CREATE USER DBA_BUNDLEEXP7 [EXPORTER USER] (WILL BE DROPPED AFTER THE EXPORT) ...
CREATE USER DBA_BUNDLEEXP7 IDENTIFIED BY "BUNdle_#-^${PASSHALF}";
ALTER USER DBA_BUNDLEEXP7 IDENTIFIED BY "BUNdle_#-^${PASSHALF}"  ACCOUNT UNLOCK;
GRANT CREATE SESSION TO DBA_BUNDLEEXP7;
GRANT DBA TO DBA_BUNDLEEXP7;
-- The following privileges to workaround Bug 6392040:
GRANT EXECUTE ON SYS.DBMS_DEFER_IMPORT_INTERNAL TO DBA_BUNDLEEXP7;
GRANT EXECUTE ON SYS.DBMS_EXPORT_EXTENSION TO DBA_BUNDLEEXP7;
PROMPT CREATING DIRECTORY EXPORT_FILES_DBA_BUNDLE POINTING TO ${LOC1} ...
CREATE OR REPLACE DIRECTORY EXPORT_FILES_DBA_BUNDLE AS '${LOC1}';
PROMPT
PROMPT CREATING AFTER TABLE IMPORT SCRIPT ...
PROMPT
SET PAGES 0 TERMOUT OFF LINESIZE 157 ECHO OFF FEEDBACK OFF
SPOOL ${SPOOLFILE2}
SELECT 'CREATE SYNONYM '||OWNER||'.'||SYNONYM_NAME||' FOR '||TABLE_OWNER||'.'||TABLE_NAME||';' FROM DBA_SYNONYMS
WHERE TABLE_OWNER||'.'||TABLE_NAME in (${TABLELIST}) AND OWNER <> UPPER('PUBLIC')
UNION
SELECT 'CREATE PUBLIC SYNONYM '||SYNONYM_NAME||' FOR '||TABLE_OWNER||'.'||TABLE_NAME||';' FROM DBA_SYNONYMS
WHERE TABLE_OWNER||'.'||TABLE_NAME in (${TABLELIST}) AND OWNER=UPPER('PUBLIC');
SPOOL OFF
EOF
)

# Creation of the Post Export Script:
export EXPORTSCRIPT=${LOC1}/EXPORTSCRIPT.sh
export EXPORTSCRIPTRUNNER=${LOC1}/EXPORTSCRIPTRUNNER.sh

echo "# Export Script: [Created By DBA_BUNDLE]"                                                 > ${EXPORTSCRIPT}
echo "export ORACLE_SID=${ORACLE_SID}"                                                          >>${EXPORTSCRIPT}
echo "echo ''"                                                                                  >>${EXPORTSCRIPT}
echo "echo 'Running The Export Job Now ...'"                                                    >>${EXPORTSCRIPT}
echo "${MKNOD}"                                                                                 >>${EXPORTSCRIPT}
echo "sleep 1"                                                                                  >>${EXPORTSCRIPT}
echo "${ZIP}"                                                                                   >>${EXPORTSCRIPT}
echo "${ORACLE_HOME}/bin/exp DBA_BUNDLEEXP7/\"BUNdle_#-^${PASSHALF}\" TABLES=${TABLESVAR} DIRECT=y CONSISTENT=y STATISTICS=NONE FEEDBACK=100000 ${EXPORTSCN} RESUMABLE=y RESUMABLE_NAME=DBA_BUNDLE_EXPORT RESUMABLE_TIMEOUT=86400 FILE=${EXPORTDUMP} log=${LOGFILE}"	>>${EXPORTSCRIPT}

echo "echo ''"                                                                                  >>${EXPORTSCRIPT}
echo "echo 'Running Post Export Steps ...'"                                                     >>${EXPORTSCRIPT}
echo "echo ''"                                                                                  >>${EXPORTSCRIPT}
echo "${ORACLE_HOME}/bin/sqlplus -s '/ as sysdba' << EOF"                                       >>${EXPORTSCRIPT}
echo "PROMPT"                                                                                   >>${EXPORTSCRIPT}
echo "PROMPT DROPPING THE EXPORTER USER DBA_BUNDLEEXP7  ..."	                                >>${EXPORTSCRIPT}
echo "DROP USER DBA_BUNDLEEXP7 CASCADE;"                                                        >>${EXPORTSCRIPT}
echo "EOF"                                                                                      >>${EXPORTSCRIPT}
echo "echo ''"                                                                                  >>${EXPORTSCRIPT}
echo "sleep 3"                                                                                  >>${EXPORTSCRIPT}
echo "${REMOVEMKDON}"                                                                           >>${EXPORTSCRIPT}
echo "echo \"*****************\""                                                               >>${EXPORTSCRIPT}
echo "echo \"IMPORT GUIDELINES:\""                                                              >>${EXPORTSCRIPT}
echo "echo \"*****************\""                                                               >>${EXPORTSCRIPT}
echo "echo \"FLASHBACK SCN used for this export is: ${CURRENT_SCN}\""                           >>${EXPORTSCRIPT}
echo "echo ''"                                                                                  >>${EXPORTSCRIPT}
echo "echo \"${UNZIPMESSAGE}\""                                                                 >>${EXPORTSCRIPT}
echo "echo ''"                                                                                  >>${EXPORTSCRIPT}
echo "echo \"AFTER IMPORTING THE DUMPFILE, RUN THIS SQL SCRIPT: ${SPOOLFILE2}\""                >>${EXPORTSCRIPT}
echo "echo \"IT INCLUDES (PRIVATE & PUBLIC SYNONYMS DDLS) WHICH WILL NOT BE HANDELED BY THE IMPORT PROCESS.\""      >>${EXPORTSCRIPT}
echo "echo ''"                                                                                  >>${EXPORTSCRIPT}
echo "echo \"**************************\""                                                      >>${EXPORTSCRIPT}
echo "echo \"EXPORT DUMP FILE LOCATION: ${EXPORTDUMPOUTPUT}\""   				>>${EXPORTSCRIPT}
echo "echo \"**************************\""                                                      >>${EXPORTSCRIPT}
echo "export JOBSTATUS=\`grep \"successfully\\|stopped\\|completed\" ${LOGFILE}|tail -1\`"      >>${EXPORTSCRIPT}
echo "export LOGFILE=${LOGFILE}"                                                                >>${EXPORTSCRIPT}
echo "export EMAILID=\"${EMAILANS}\""                                                           >>${EXPORTSCRIPT}
echo "${SENDEMAIL}"                                                                             >>${EXPORTSCRIPT}


chmod 740 ${EXPORTSCRIPT}

echo
echo "#!/bin/bash"                                                                              > ${EXPORTSCRIPTRUNNER}
echo "nohup sh ${EXPORTSCRIPT}| tee ${LOGFILE} 2>&1 &"  					>>${EXPORTSCRIPTRUNNER}
chmod 740 ${EXPORTSCRIPTRUNNER}
echo -e "\033[32;5mFeel free to EXIT from this session as the EXPORT SCRIPT is running in the BACKGROUND.\033[0m"
source ${EXPORTSCRIPTRUNNER}

                        echo; exit ;;
                        *) echo "Enter a valid number:"
                           echo "====================="
                           echo "i.e."
                           echo "1 for expdp tool"
                           echo "2 for exp tool"
                           echo ;;
                        esac
                        done

 break;;
 *) echo "Enter a NUMBER between 1 to 3 boss:"
    echo "==================================" ;;
esac
done

# #############
# END OF SCRIPT
# #############
# DISCLAIMER: THIS SCRIPT IS DISTRIBUTED IN THE HOPE THAT IT WILL BE USEFUL, BUT WITHOUT ANY WARRANTY. IT IS PROVIDED "AS IS".
# Do not live under a rock :-) Every month a new version of DBA_BUNDLE get released, download it by visiting:
# http://dba-tips.blogspot.com/2014/02/oracle-database-administration-scripts.html
# REPORT BUGs to: mahmmoudadel@hotmail.com
