#!/bin/bash

#for debug purpose, uncomment following
#set -x

usage="$0 IP.IP.IP.IP [fullinit|getinfos|changeip|setrootpw|adduser|getraclogs|sethostname] [<root pw>|<3 username password profile>|<hostname>|<ip mask gw>]
    examples:
        $0 IP.IP.IP.IP setrootpw secret
        $0 IP.IP.IP.IP getinfos
        $0 IP.IP.IP.IP fullinit
        $0 IP.IP.IP.IP getraclogs
        $0 IP.IP.IP.IP sethostname HOSTNAME.domain.ltd
        $0 IP.IP.IP.IP adduser 3 john johnsecret 0x000000C1
            for setting the value of profile, see https://www.dell.com/support/manuals/us/en/04/poweredge-fx2/cmcfx2fx2s13rg-v1/cfguseradminprivilege-readwrite?guid=guid-863f4d46-0927-4367-89fa-e87b150612e8&lang=en-us
        $0 oldIP.oldIP.oldIP.oldIP changeip 192.168.1.10 255.255.255.0 192.168.1.1
"

### command line references.
# ref. v6: http://pleiades.ucsc.edu/doc/dell/openmanage/RACADM_Command_Line_Reference_Guide_for_iDRAC6.pdf
# ref. v7: http://pleiades.ucsc.edu/doc/dell/openmanage/RACADM_Command_Line_Reference_Guide_for_iDRAC7.pdf
# ref. v8: https://topics-cdn.dell.com/pdf/integrated-dell-remote-access-cntrllr-8-with-lifecycle-controller-v2.00.00.00_reference-guide_en-us.pdf
# ref. v9: https://topics-cdn.dell.com/pdf/idrac9-lifecycle-controller-v3151515_users-guide_en-us.pdf

source racadm_local.conf

LIBSSLPATH=/usr/lib/x86_64-linux-gnu/libssl.so.1.0.0

RACADMPATH=`which racadm`
if [ -z "$RACADMPATH" ]; then
  echo "No racadm found... Exiting..."
  exit 1
fi

SBIN_RACADM_DIR=$( dirname `realpath $RACADMPATH` )
DELL_RACADM_DIR=`echo ${SBIN_RACADM_DIR/sbin/}`

# bug with libssl.so
if [ ! -f /opt/dell/srvadmin/lib64/libssl.so ]; then
  if [[ `realpath $RACADMPATH` =~ "idrac7" ]]; then
    if [ -f $LIBSSLPATH ]; then
      sudo ln -s $LIBSSLPATH $DELL_RACADM_DIR/lib64/libssl.so
    fi
  fi
fi

if [[ "$USER" == "root" ]]; then
  RACADM=$RACADMPATH
else
  RACADM="sudo $RACADMPATH"
fi

if [ "$#" -lt 2 ]; then
    echo -e "$usage"
    exit 1
fi

ip=$1
if [[ ! $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
    echo -e "$usage"
    echo "Bad IP format"
    exit 1
fi

# Retrieving idrac version https://www.dell.com/community/Systems-Management-General/Determine-DRAC-version-from-RACADM/td-p/4394174
# idrac matrix
# 10 | v6
# 11 | v6
# 16 | v7
# 17 | v7
# 32 | v8
# 33 | v8
# 14G Monolithic | v9
retrieve_version() {
  local idracv=$( $RACADM -r $ip -u $user -p $password getconfig -g idracinfo |awk -F"=" '/idRacType/ {print $2}' )
  case "$idracv" in
    10*|11*)  version="v6";;
    16*|17*)  version="v7";;
    32*|33*)  version="v8";;
    14G*)     version="v9";;
    *)
      echo $idracv;
      echo "UNKNOWN VERSION OF IDRAC";
      exit 1;
      ;;
  esac
  echo "Your remote iDracType is: "$idracv
  echo "with iDrac version:" $version
}

check_user_id() {
    id=$1
    if [[ "$version" == "v9" || "$version" == "v6" || "$version" == "v8" ]]; then
        testid=$( $RACADM -r $ip -u $user -p $password getconfig -g cfgUserAdmin -i $id | awk -F"=" '/UserName/ {print $2}' )
    else
        testid=$( $RACADM -r $ip -u $user -p $password get iDRAC.Users.$id.UserName | awk -F"=" '/UserName/ {print $2}' )
    fi
}


retrieve_version

case $2 in
  getinfos)
    echo "###################### iDrac versions #####################"
    $RACADM -r $ip -u $user -p $password getconfig -g idracinfo
    echo "###########################################################"
    echo ""
    echo "#################### iDrac getsysinfos ###################"
    $RACADM -r $ip -u $user -p $password getsysinfo
    #$RACADM -r $ip -u $user -p $password getniccfg
    echo "##########################################################"
    echo ""
    echo "############### iDrac RemoteHosts Config #################"
    $RACADM -r $ip -u $user -p $password getconfig -g cfgRemoteHosts
    echo "##########################################################"
    echo ""
  ;;
  getraclogs)
    $RACADM -r $ip -u $user -p $password getraclog -c 100
  ;;
  sethostname)
    if [ -n "$3" ]; then
      $RACADM -r $ip -u $user -p $password set system.ServerOS.HostName $3
    else
      echo -e "$usage"
      echo "You need to specify a hostname... Exiting..."
      exit 1
    fi
  ;;
  changeip)
    echo "Sorry, it is in my TO DO list..."
    exit 0
  ;;
  setrootpw)
    if [ -n "$3" ]; then
      # root has userid set to '2' by default. see https://lonesysadmin.net/2015/08/13/interesting-dell-idrac-tricks/
      $RACADM -r $ip -u $user -p $password set iDRAC.Users.2.Password $3
    else
      echo -e "$usage"
      echo "You need to specify a password... Exiting..."
      exit 1
    fi
  ;;
  adduser)
    if [ $# -ne 6 ]; then
        echo $usage
        exit 1
    fi
    id=$3
    username=$4
    userpassword=$5
    profile=$6
    check_user_id $id
    if [ -z "$testid" ]; then
        $RACADM -r $ip -u $user -p $password config -g cfgUserAdmin -o cfgUserAdminUserName -i $id $username
        $RACADM -r $ip -u $user -p $password config -g cfgUserAdmin -o cfgUserAdminPassword -i $id $userpassword
        $RACADM -r $ip -u $user -p $password config -g cfgUserAdmin -i $id -o cfgUserAdminPrivilege $profile
    else
        echo "You will overwrite a user. If you really want to do this, please enter:"
        echo "
        $RACADM -r $ip -u $user -p $password config -g cfgUserAdmin -o cfgUserAdminUserName -i $id $username
        $RACADM -r $ip -u $user -p $password config -g cfgUserAdmin -o cfgUserAdminPassword -i $id $userpassword
        $RACADM -r $ip -u $user -p $password config -g cfgUserAdmin -i $id -o cfgUserAdminPrivilege $profile
        "
    fi
  ;;
  fullinit)
    #DNS
    $RACADM -r $ip -u $user -p $password config -g cfgLanNetworking -o cfgDNSDomainName $dnsdomainname
    #racadm -r $ip -u $user -p $password set iDRAC.NIC.DNSDomainName $dnsdomainname
    $RACADM -r $ip -u $user -p $password config -g cfgLanNetworking -o cfgDNSServer1 $DNS1
    $RACADM -r $ip -u $user -p $password config -g cfgLanNetworking -o cfgDNSServer2 $DNS2

    #Config SMTP
    $RACADM -r $ip -u $user -p $password config -g cfgRemoteHosts -o cfgRhostsSmtpServerIpAddr $SMTP

    # idrac6 ?
    if [ "$version" == "v6" ];then
      $RACADM -r $ip -u $user -p $password config -g cfgEmailAlert -o cfgEmailAlertEnable -i 1 1
      $RACADM -r $ip -u $user -p $password config -g cfgEmailAlert -o cfgEmailAlertAddress -i 1 $contactmail
    else
      $RACADM -r $ip -u $user -p $password set idrac.snmp.agentenable 1
      $RACADM -r $ip -u $user -p $password set iDRAC.EmailAlert.Enable.1 1
      $RACADM -r $ip -u $user -p $password set iDRAC.EmailAlert.Address.1 $contactmail
      $RACADM -r $ip -u $user -p $password eventfilters set -c idrac.alert.all -a none -n snmp
      $RACADM -r $ip -u $user -p $password eventfilters set -c idrac.alert.critical -a none -n snmp,email
    fi
    # verif
    $RACADM -r $ip -u $user -p $password getconfig -g cfgEmailAlert -i 1
    #Test envoi de mail
    $RACADM -r $ip -u $user -p $password testemail -i 1

    # NTP
    echo "Configuring NTP..."
    case $version in
      v6)
        $RACADM -r $ip -u $user -p $password config -g cfgRemoteHosts -o cfgRhostsNtpEnable 1
        $RACADM -r $ip -u $user -p $password config -g cfgRemoteHosts -o cfgRhostsNtpServer1 $NTP
        ;;
      v7|v8)
        $RACADM -r $ip -u $user -p $password set idrac.time.1.Timezone $TimeZone
        $RACADM -r $ip -u $user -p $password set idrac.ntpConfigGroup.1.NTPEnable Enabled
        $RACADM -r $ip -u $user -p $password set idrac.ntpConfigGroup.1.NTP1 $NTP
        ;;
      v9)
        $RACADM -r $ip -u $user -p $password set idrac.time.Timezone $TimeZone
        $RACADM -r $ip -u $user -p $password set idrac.ntpConfigGroup.NTPEnable Enabled
        $RACADM -r $ip -u $user -p $password set idrac.ntpConfigGroup.NTP1 $NTP
        ;;
    esac
  ;;
  *)
    echo -e "$usage"
    exit 1
  ;;
esac




