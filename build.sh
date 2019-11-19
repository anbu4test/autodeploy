#!/bin/bash

###################################################################
#Script Name	: build.sh                                                                                            
#Description	: Application deployment automation script
#Date		: 19/11/2019
#Version        : v1.8                                                           
#Args           :                                                                                          
#Author       	: Anbazhagan Kali                                      
#Email         	: kali.anbazhagan@mahindra.com                                   
###################################################################

#Terminal output colors
R='\033[0;31m'
G='\033[0;32m'
Y='\033[0;33m'
B='\033[0;34m'
M='\033[0;35m'
C='\033[0;36m'
NC='\033[0m'
bold="$(tput bold)"


#script initialization with valid arguments
usage() { echo -e "${Y}Usage: $0 [-p <project name>] [-d <domain name>] [install / restore]${NC}" 1>&2; exit 1; }

while getopts ":p:d:" o; do
    case "${o}" in
        p)
            pname=${OPTARG}
            ;;
        d)
            dname=${OPTARG}
            ;;
        *)
            usage
            ;;
    esac
done
shift $((OPTIND-1))

if [ -z "${pname}" ] || [ -z "${dname}" ]; then
    usage
fi

## Common print functions
print_status() {
  local outp=$(echo "$1") # | sed -r 's/\\n/\\n## /mg')
  echo
  echo -e "## ${outp}"
}

print_bold() {
    title="$1"

    echo -e "${R}================================================================================${NC}"
    echo -e "  ${bold}${Y}${title}${NC}"
    echo -e "${R}================================================================================${NC}"
}

#Print line
hline() { 
    printf '%*s\n' "${COLUMNS:-$(tput cols)}" '' | tr ' ' - 
}

# Write log file
log() {
    tag=$1
    text=$2
    echo `date +"%F %T %Z"` $tag $text >> $logfile
}


# Source configuration files
source appserv.config

# Required Variables
configfile=appserv.config
prop_file=build.properties
bkp_name="$pname"_$(date +%d-%m-%Y_%H:%M).war
dep_path=$webdir/$dname/webapp
httpdir=/etc/httpd/conf.d
logfile=$(echo "$(cd "$(dirname "$1")"; pwd -P)")/logs/build.log

clear
print_status "executing script..."

#Virtual host configuration
vhsetup() {
read -n 1 -rep "Do you want auto-configure VirtualHost setup (Y/N)? " ans
    case $ans in
        [Yy]* ) echo "Creating web directories.."
                cd $webdir ; mkdir -p "$dname"/{webapp,statistics/logs} ; cd $dname ;
		chown -R root:tomcat webapp ; chmod 775 webapp ; cd ../../ 
		echo $pname ; echo $dname ;; 
	[Nn]* ) hline ; gclone ;;
	* ) 	echo -e "${B}Please answer yes (y) or no (n).${NC}"
		vhsetup ;;
    esac

#Apache Virtual host configuration
echo "Configuring Virtual host in Apache httpd..."
touch $httpdir/"$dname".conf
echo "### $dname - GENERATED AUTOMATICALLY ###
<VirtualHost *:80>
    ServerName $dname
    #DocumentRoot $webdir/$dname/webapp/$pname

    CustomLog $webdir/$dname/statistics/logs/access_log combined
    ErrorLog  $webdir/$dname/statistics/logs/error_log

    #<Directory $webdir/$dname/webapp/$pname>
    #    Options -Includes +FollowSymLinks +MultiViews
    #    AllowOverride All
    #    Order allow,deny
    #    Allow from all
    #</Directory>
       JkMount /* myworker
</VirtualHost>" > $httpdir/"$dname".conf

if [ $? == 0  ]; then
    logger "$0 $dname configured in Web Server."
    echo -e "httpd server configuration...\t\t [${G}SUCCESS${NC}]"
else
    echo -e "httpd server configuration...\t\t [${R}FAILED${NC}]" ; exit 1
fi

#Tomcat Virtual host configuration
echo "Configuring Virtual host in Tomcat server..."
cd $appserv_conf
tac server.xml | sed '1,3d' | tac > tmp.xml
mv server.xml server.xml.$(date +%d-%m-%Y_%H:%M)
echo "<!-- $dname - GENERATED AUTOMATICALLY -->
     <Host name=\"$dname\" appBase=\"$webdir/$dname/webapp\" >
        <Alias>www.$dname</Alias>
        <Valve className=\"org.apache.catalina.valves.AccessLogValve\" directory=\"logs\"
           prefix=\"${dname}_access_log\" suffix=\".txt\"
           pattern=\"%h %l %u %t %r %s %b\" />
     </Host>

    </Engine>
  </Service>
</Server>"  >> $appserv_conf/tmp.xml
mv tmp.xml server.xml ; chown root:tomcat server.xml

if [ $? == 0  ]; then
    logger "$0 $dname Virtual host added in Application Server"
    echo -e "tomcat server configuration...\t\t [${G}SUCCESS${NC}]"
else
    echo -e "tomcat server configuration...\t\t [${R}FAILED${NC}]" ; exit 1
fi

# Backup Directory creation
if [ ! -d $bkpdir ]; then
   	echo -e "${Y}WARN!!${NC}Backup Directory \"$bkpdir\" does not exists."
   	mkdir -p $bkpdir && if [ $? == 0  ]; then
   	echo -e "${G}Backup Directory created!! -------: ${bkpdir}${NC}"
	fi
else
	echo -e "${G}Backup Directory already exists. -----------: ${bkpdir}${NC}" && printf "\n"
	echo -e "${C}INFO: Please restart apache httpd and tomcat server then try installation.${NC}"
        exit 0
fi
	
}


#deploy application using git
gclone () {

# create build configuration files
buildDir="/tmp/${pname}.`date +%d%m%y%H%M%S`"
mkdir ${buildDir}
touch $buildDir/$prop_file
echo "### Properties file - GENERATED AUTOMATICALLY ###
PROJ.DIR=$pname
REPO.URL=$repo_url
PROJ.NAME=$pname
LIB.DIR=WebContent/WEB-INF/lib
APPSERVER.HOME=$appserv_home
APPSERVER.LIB=\${APPSERVER.HOME}/lib
DEPLOY.PATH=$webdir/$dname/webapp
WAR.FILE=ROOT.war
tomcat.manager.url=http://localhost:8080/manager
tomcat.manager.username=$username
tomcat.manager.password=$password" > $buildDir/${prop_file}

if [ $? == 0  ]; then
    print_status "Creating Properties file...\t\t [${G}SUCCESS${NC}]"
else
    print_status "Creating Properties file...\t\t [${R}FAILED${NC}]" ; exit 1
fi

if [ -f ${dname}.xml ]; then
    print_status "Build XML file found-----------: ${Y}${dname}.xml${NC}"
    cp -f ${dname}.xml $buildDir/build.xml
else
    print_status "${R}ERR!! Build XML file not found.${NC}\n${Y}Please generate XML file and try again.${NC}"
    exit 0;
fi

#Repo URL check
url_count=$(grep -c '^repo_url' $configfile)

if [ $url_count -gt 1  ]; then
    urlopt=($(grep '^repo_url' appserv.config | cut -d "=" -f 2 | sed -e 's/^\s*//' -e '/^$/d' -e 's/"//g'))
    urls=$(printf '%s ' "${urlopt[@]}")
    print_status "${Y}Mutiple repo url found. Please choose any one.${NC}\n"
    PS3="repurl (1-$url_count): "
    select repurl  in $urls
    do
        if [[ -z $repurl  ]]; then
            echo -e "${R}Invalid Choice:${NC} '$REPLY'" >&2
        else
            break
        fi
    done
else
   repurl=$repo_url
fi


#git clone
   if [[ $build_detail == 1 ]]; then
       print_bold "* Change Log required to continue"
       read -ep "Enter Change Log in brief : " chlog
       # Check if string is empty
       if [[ -z "$chlog" ]]; then
           echo -e "${R}No input entered${NC}"
           exit 1
       fi

       read -ep "Enter Developer Name      : " devname
       # Check if string is empty
       if [[ -z "$devname" ]]; then
           echo -e "${R}No input entered${NC}"
           exit 1
       fi
   fi

   cd ${buildDir}
   print_status "Fetching code from BitBucket repository-----: ${Y}$pname${NC}"
   git clone $repurl/${pname}.git

   if [[ $? == 128 ]]; then
	print_status "${R}ERR!!${NC} Invalid Username or Password."; exit 1;
   fi

   if [[ $deploy_env == "prod" ]]; then
        grep "^jdbc.url.*$rdsendpoint" $pname/$dbcon_file > /dev/null
        if (( $? )); then
        	print_status "${R}ERR!!${NC} RDS Endpoint mismatch. Check DB Connection File."; exit 1;
        fi
   fi

   if [ -f ${dep_path}/ROOT.war ]; then
	print_status "${Y}Taking backup of current application...${NC}"
	cp -iv $dep_path/ROOT.war ${bkpdir}/${bkp_name} && printf "\n"
   fi

   logger "$0 Build Process started for '$dname'"
   log INFO "$0: Build Process Started. CN=$dname DEV=$devname MSG=$chlog"

   ant war

   if [ $? -eq 0 ]; then
   	log INFO "$0: BUILD SUCCESSFULL"
   else
   	log ERROR "$0: BUILD FAILED"
   fi

   hline ; sleep 1 ;
   #Remove local copies
   print_status "Attempting to remove local copies.."
   if [ -f ROOT.war ] || [ -d $pname ]; then 
       rm -rf $buildDir
       print_status "Removed successfully."
   else
       print_status "${R}ERR!!${NC}File not found.";
   fi
   # Remove old backups
   cd ${bkpdir}; fc=`ls -1rt ${pname}* | wc -l`
   if [ $fc > $maxkeep  ];then
   print_status "Removing Old backup file.."
   ls -1rt ${pname}* | head -n -$maxkeep | xargs rm -v
   hline ; exit 0
   fi
}


restore() {
read -n 1 -rep "Are you sure to continue (Y/N)? " ans
case $ans in
        [Yy]* ) print_status "Restoring backup file.."
                cp -v $res_file $dep_path/ROOT.war
                if [ $? == 0  ]; then
		    logger "$0 Application $pname restored from $res_file"
                    print_status "Restore from backup...\t\t [${G}SUCCESS${NC}]"
                else
		    logger "$0 Application $pname Restore Failed."
                    print_status "Restore from backup...\t\t [${R}FAILED${NC}]" ; exit 1
                fi
                hline
                ;;
        [Nn]* ) logger "$0: Application $pname Restore cancelled."
		printf "\n${Y}Aborted.\n${NC}" ;;
        * ) 	print_status "${B}Please answer yes or no.${NC}"
		restore ;;
    esac

}

option="${1}"
case ${option} in
    install) #Checking if repo directory already exists
        if [ ! -d $webdir/$dname ]; then
            echo -e "${Y}\"$dname\"${NC} looks like new Domain.." ; vhsetup
             
        else
	    gclone ;
        fi
	;;
    restore) #Restore application from backup
	if [ "$(ls -A $bkpdir)" ]; then
     	    res_file=`ls -t $bkpdir/$pname* | head -1`
            echo -e "Latest backup file found ------: ${G}$res_file${NC}"
            restore
	else
    	    echo -e "${R}ERR!!${NC} Backup file not found for ${C}$dname${NC}"
	fi
	;;	
    * ) usage

esac

exit 0

