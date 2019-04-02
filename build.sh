#!/bin/bash

###################################################################
#Script Name	: build.sh                                                                                            
#Description	: Application deployment automation script
#Date		: 27/03/2019
#Version        : v1.5                                                           
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

#Print line
hline() { 
    printf '%*s\n' "${COLUMNS:-$(tput cols)}" '' | tr ' ' - 
}

# Source configuration files
source appserv.config

# Required Variables
prop_file=build.properties
bkp_name="$pname"_$(date +%d-%m-%Y_%H:%M).war
dep_path=$webdir/$dname/webapp
httpdir=/etc/httpd/conf.d

clear
printf "executing script....\n\n" 


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
    echo -e "Creating Properties file...\t\t [${G}SUCCESS${NC}]"
else
    echo -e "Creating Properties file...\t\t [${R}FAILED${NC}]" ; exit 1
fi

if [ -f ${dname}.xml ]; then
    echo -e "Build XML file found-----------: ${Y}${dname}.xml${NC}"
    cp -f ${dname}.xml $buildDir/build.xml && printf '\n'
else
    echo -e "${R}ERR!! Build XML file not found.${NC}\n${Y}Please generate XML file and try again.${NC}"
    exit 0;
fi

#git clone
   cd ${buildDir}
   echo -e "Fetching code from BitBucket repository-----: ${Y}$pname${NC}"
   git clone $repo_url/${pname}.git && printf "\n"
   	if [ -f ${dep_path}/ROOT.war ]; then
	echo -e "${Y}Taking backup of current application...${NC}"
	cp -iv $dep_path/ROOT.war ${bkpdir}/${bkp_name} && printf "\n"
	fi
   printf "\n"
   logger "$0 Build Process started."
   ant war
   hline ; sleep 1 ;
   #Remove local copies
   echo -e "Attempting to remove local copies.."
   if [ -f ROOT.war ] || [ -d $pname ]; then 
       rm -rf $buildDir
       echo -e "Removed successfully."
   else
       echo -e "${R}ERR!!${NC}File not found.";
   fi
   # Remove old backups
   cd ${bkpdir}; fc=`ls -1rt ${pname}* | wc -l`
   if [ $fc > $maxkeep  ];then
   echo -e "\nRemoving Old backup file.."
   ls -1rt ${pname}* | head -n -$maxkeep | xargs rm -v
   hline ; exit 0
   fi
}


restore() {
read -n 1 -rep "Are you sure to continue (Y/N)? " ans
case $ans in
        [Yy]* ) echo "Restoring backup file.."
                cp -v $res_file $dep_path/ROOT.war
                if [ $? == 0  ]; then
		    logger "$0 Application $pname restored from $res_file"
                    echo -e "\nRestore from backup...\t\t [${G}SUCCESS${NC}]"
                else
		    logger "$0 Application $pname Restore Failed."
                    echo -e "\nRestore from backup...\t\t [${R}FAILED${NC}]" ; exit 1
                fi
                hline
                ;;
        [Nn]* ) logger "$0: Application $pname Restore cancelled."
		printf "\n${Y}Aborted.\n${NC}" ;;
        * ) 	echo -e "${B}Please answer yes or no.${NC}"
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

