#About
Scripts to get Syslog (protocol) messages into Zabbix from network devices, servers and others.  


![new](https://cloud.githubusercontent.com/assets/14870891/19680057/da8dcf52-9aac-11e6-915a-cf136577dae3.png)  
1. Configure network devices to route all Syslog messages to a your zabbix-server or zabbix-proxy host with rsyslog on board    
2. with rsyslog configuration altered it would run script (3) and determines from what zabbix-host this message comes from(using Zabbix API)    
4. zabbix-sender protocol is then used to put messages into zabbix  

Features include:  
- ip to host resolutions are cached to minimize the number of Zabbix API queries  
- zabbix_sender here is in a form of a perl function, so no cli zabbix_sender tool is required      

##Map context menu  
As a bonus, script `zabbix_syslog_create_urls.pl` can be used(and scheduled in cron for regular map link updates) to append a direct link into maps host menu for reading Syslog item values for each host that has syslog:  
![2013-12-30_152557](https://cloud.githubusercontent.com/assets/14870891/19680048/d248b76c-9aac-11e6-8a95-accd34794563.png)  
Script will do no rewriting of existing host links, only appending to a list. Also link only added to hosts that has item with key 'syslog'.  

#Setup  
##Dependencies  

The script is written in Perl and you will need common modules in order to run it:  
```
LWP
JSON::XS
CHI
Config::General
```
There are numerous ways to install them:  

| in Debian  | In Centos* | using CPAN | using cpanm|  
|------------|-----------|------------|------------|  
|  `apt-get install libwww-perl libjson-xs-perl libchi-perl libconfig-general-perl` | `yum install perl-JSON-XS perl-libwww-perl perl-LWP-Protocol-https perl-Config-General` | `PERL_MM_USE_DEFAULT=1 perl -MCPAN -e 'install Bundle::LWP'` and  `PERL_MM_USE_DEFAULT=1 perl -MCPAN -e 'install JSON::XS` and `PERL_MM_USE_DEFAULT=1 perl -MCPAN -e 'install CHI'` and `PERL_MM_USE_DEFAULT=1 perl -MCPAN -e 'install Config::General'` | `cpanm install LWP` and `cpanm install JSON::XS` and `cpanm install CHI` and `cpanm install Config::General`|  
* No package for CHI in Centos 7. Use cpanm.  

##Copy scripts  
```
cp zabbix_syslog_create_urls.pl /usr/local/bin/zabbix_syslog_create_urls.pl
chmod +x /usr/local/bin/zabbix_syslog_create_urls.pl


cp zabbix_syslog_lkp_host.pl /usr/local/bin/zabbix_syslog_lkp_host.pl
chmod +x /usr/local/bin/zabbix_syslog_lkp_host.pl

cp zabbix_syslog.cfg /usr/local/etc/zabbix_syslog.cfg
sudo chown zabbix:zabbix /usr/local/etc/zabbix_syslog.cfg
sudo chmod 700 /usr/local/etc/zabbix_syslog.cfg
```
edit `/usr/local/etc/zabbix_syslog.cfg`  

##rsyslog
add file /etc/rsyslog.d/zabbix_rsyslog.conf with contents:  
```
$template RFC3164fmt,"<%PRI%>%TIMESTAMP% %HOSTNAME% %syslogtag%%msg%"
$template network-fmt,"%TIMESTAMP:::date-rfc3339% [%fromhost-ip%] %pri-text% %syslogtag%%msg%\n"


#exclude unwanted messages:
:msg, contains, "Child connection from" ~
:msg, contains, "exit after auth (ubnt): Disconnect received" ~
:msg, contains, "password auth succeeded for 'ubnt' from ::ffff:10.2.0.21" ~
:msg, contains, "password auth succeeded for 'ubnt' from" ~
:msg, contains, "exit before auth: Exited normally" ~
if $fromhost-ip != '127.0.0.1' then ^/usr/local/bin/zabbix_syslog_lkp_host.pl;network-fmt       
if $fromhost-ip != '127.0.0.1' then /var/log/network.log;network-fmt
& ~
```
and restart rsyslog  

##Import template
Import syslog template and attach it to hosts from which you expect syslog messages to come  

#More info:  
https://habrahabr.ru/company/zabbix/blog/252915/  
