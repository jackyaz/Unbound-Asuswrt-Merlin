#!/bin/bash
destinationIP="0.0.0.0"
tempoutlist="/opt/var/lib/unbound/adblock/adlist.tmp"
tempwhitelistoutlist="/opt/var/lib/unbound/adblock/whitelist.tmp"
outlist='/opt/var/lib/unbound/adblock/tmp.host'
finalist='/opt/var/lib/unbound/adblock/tmp.finalhost'
permlist='/opt/var/lib/unbound/adblock/permlist'
adlist='/opt/var/lib/unbound/adblock/adservers'
sites='/opt/var/lib/unbound/adblock/sites'

echo "Removing possible temporary files.."
[ -f $tempoutlist ] && rm -f $tempoutlist
[ -f $tempwhitelistoutlist ] && rm -f $tempwhitelistoutlist
[ -f $outlist ] && rm -f $outlist
[ -f $finalist ] && rm -f $finalist

# check for sites file
if [ ! -f $sites ]; then
  logger -st "($(basename $0))" "Missing $sites file"
  exit
fi

# process sites list
while read -r line
do
  set -- $line
  if [ "$2" != "" ]; then
    if [ "$1" == "hosts" ]; then
      echo "Processsing hosts file @ $2"
      curl --progress-bar $2 | grep -v "#" | grep -v "::1" | grep -v "0.0.0.0 0.0.0.0" | sed '/^$/d' | sed 's/\ /\\ /g' | awk '{print $2}' | grep -v '^\\' | grep -v '\\$'| sort >> $tempoutlist
    elif [ "$1" == "domains" ]; then
     echo "Processing domains file @ $2"
     curl --progress-bar $2 >> $tempoutlist
    elif [ "$1" == "whitelist-domains" ]; then
     echo "Processing whitelist domains file @ $2"
     curl --progress-bar $2 >> $tempwhitelistoutlist
    else
      echo "Unknown file type = $1"
    fi
  else
    echo "Missing site URL on line $line"
  fi
done < "$sites"

echo "Combining User Custom block host..."
cat /opt/var/lib/unbound/adblock/blockhost >> $tempoutlist

if [ -f $tempwhitelistoutlist ]; then
  echo "Removing any downloaded whitelist items..."
  awk 'NR==FNR{a[$0];next} !($0 in a) {print $NF}' $tempwhitelistoutlist $tempoutlist > $outlist
  mv $outlist $tempoutlist
fi

echo "Edit User Custon list of allowed domains..."
awk 'NR==FNR{a[$0];next} !($0 in a) {print $NF}' $permlist $tempoutlist > $outlist

echo "Removing duplicate formatting from the domain list..."
cat $outlist | sed -r -e 's/[[:space:]]+/\t/g' | sed -e 's/\t*#.*$//g' | sed -e 's/[^a-zA-Z0-9\.\_\t\-]//g' | sed -e 's/\t$//g' | sed -e '/^#/d' | sed -e '/^\([0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\).*$/d' | sed -e 's/^[ \t]*//;s/[ \t]*$//' | sort -u | sed '/^$/d' | awk -v "IP=$destinationIP" '{sub(/\r$/,""); print IP" "$0}' > $finalist
numberOfAdsBlocked=$(wc -l < $outlist)
echo "$numberOfAdsBlocked domains compiled"

echo "Generating Unbound adlist....."
awk '/^0.0.0.0/ {print "local-zone: \""$2"\" always_nxdomain"}' $finalist > $adlist
numberOfAdsBlocked=$(wc -l < $adlist)
echo "$numberOfAdsBlocked suspicious and blocked domains"

echo "Removing temporary files..."
[ -f $tempoutlist ] && rm -f $tempoutlist
[ -f $tempwhitelistoutlist ] && rm -f $tempwhitelistoutlist
[ -f $outlist ] && rm -f $outlist
[ -f $finalist ] && rm -f $finalist

echo "Restarting DNS servers..."
/opt/etc/init.d/S61unbound restart
