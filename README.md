#Install reqs:  
```
PERL_MM_USE_DEFAULT=1 perl -MCPAN -e 'install CHI'
PERL_MM_USE_DEFAULT=1 perl -MCPAN -e 'install Config::General'
```

```
/usr/local/bin/zabbix_syslog_create_urls.pl
chmod +x /usr/local/bin/zabbix_syslog_create_urls.pl


/usr/local/bin/zabbix_syslog_lkp_host.pl
chmod +x /usr/local/bin/zabbix_syslog_lkp_host.pl

/usr/local/etc/zabbix_syslog.cfg
sudo chown zabbix:zabbix /usr/local/etc/zabbix_syslog.cfg
sudo chmod 700 /usr/local/etc/zabbix_syslog.cfg
```
in /etc/rsyslog.d/zabbix_rsyslog.conf:  
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


#More info:  
https://habrahabr.ru/company/zabbix/blog/252915/  