#!/usr/bin/perl

use 5.010;
use strict;
use warnings;

use FindBin qw($Bin);
use lib "$Bin/lib";
use Data::Dumper;
use Config::General;
use ZabbixAPI;
our $VERSION = 3.0;
my $conf;
$conf  = eval {Config::General->new('/usr/local/etc/zabbix_syslog.cfg')};
if ($@) {
        eval {$conf  = Config::General->new('/etc/zabbix/zabbix_syslog.cfg')};
        if ($@) {die "Please check that config file is available as /usr/local/etc/zabbix_syslog.cfg or /etc/zabbix/zabbix_syslog.cfg\n";}
}

my %Config = $conf->getall;

#Authenticate yourself
my $url      = $Config{'url'} || die "URL is missing in zabbix_syslog.cfg\n";
my $user     = $Config{'user'} || die "API user is missing in zabbix_syslog.cfg\n";
my $password = $Config{'password'}   || die "API user password is missing in zabbix_syslog.cfg\n";
my $server = $Config{'server'}   || die "server hostname is missing in zabbix_syslog.cfg\n";

my $debug = $Config{'debug'};
my ( $authID, $response, $json );


my $zbx = ZabbixAPI->new( { api_url => $url, username => $user, password => $password } );
$zbx->login();

my $syslog_url_base = 'history.php?action=showvalues';

    my @selements;

    foreach my $map ( @{ map_get_extended() } ) {
        my $mapid=$map->{sysmapid};
        #put all map elements into array @selements (so you can update map later!)
        @selements = @{ $map->{selements} };

	print "INFO: Checking map with mapid $map->{sysmapid}\n";
        foreach my $selement (@selements) {
            my $syslog_button_exists = 0;

            if ( $debug > 0 ) {
                print 'Object ID: '
                  . $selement->{selementid}
                  . ' Type: '
                  . $selement->{elementtype}."\n";
            }

            # elementtype=0 hosts
            if ( $selement->{elementtype} == 0 ) {
                my $hostid;
                #Zabbix API 3.4+
                if (exists($selement->{elements}->[0]->{hostid})) {
                    $hostid = $selement->{elements}->[0]->{hostid};
                }
                #Zabbix API before 3.4
                elsif (exists($selement->{elementid})) {
                    $hostid = $selement->{elementid};
                }
                else {
                    die "Cannot get hostid of selement $selement->{selementid}\n";
                }

                my $itemid = get_syslogid_by_hostid($hostid);
                if ($itemid) {

                    #and add urls:

                    my $syslog_exists = 0;
                    foreach my $syslog_url ( @{ $selement->{urls} } ) {
                        $syslog_exists = 0;

                        if ( $syslog_url->{name} =~ 'Syslog' ) {

                            $syslog_exists = 1;
                            $syslog_url->{'name'} = 'Syslog';

                            $syslog_url->{'url'} =
                                $syslog_url_base
                              . '&itemids['
                              . $itemid . ']='
                              . $itemid;
                        }
                    }
                    if ( $syslog_exists == 0 ) {

                        #syslog item doesn't exist... add it
                        push @{ $selement->{urls} },
                          {
                            'name' => 'Syslog',
                            'url'  => $syslog_url_base
                              . '&itemids['
                              . $itemid . ']='
                              . $itemid
                          };
                    }

                }

            }

        }
            map_update($mapid,\@selements);
    }



$zbx->logout();

#______SUBS
sub get_syslogid_by_hostid {
    
    
    my $hostid = shift;

    my $params = {
            output  => ['itemid'],
            hostids => $hostid,
            filter => {'key_' => 'syslog' },
            limit   => 1,
        };
    my $result = $zbx->do('item.get',$params);


    # Check if response was successful
    if ( !$result ) {
        $zbx->logout();
        die "item.get failed\n";
    }

    #return itemid of syslog key (trapper type)
    return ${ $result }[0]->{itemid};
}


sub map_get {

    #retrieve all maps
    my $params = {
            output => ['sysmapid']
        };
    my $result = $zbx->do('map.get',$params);

    # Check if response was successful
    if ( !$result ) {
        $zbx->logout();
        die "map.get failed\n";
    }

    if ( $debug > 1 ) { print Dumper $result; }
    return $result;

}


sub map_get_extended {
    my $params = {
            selectSelements => 'extend',
            #sysmapids       => $map,
    };
    
    my $result = $zbx->do('map.get',$params);

    # Check if response was successful
    if ( !$result ) {
        $zbx->logout();
        die "map.get failed\n";
    }
    if ( $debug > 1 ) {

        print Dumper $result;
    }

    return $result;
}

sub map_update {
    my $mapid = shift;
    my $selements_ref = shift;
    my $params = {
            selements => [@{$selements_ref}],
            sysmapid  => $mapid,
        };
    my $result;
    eval {$result=$zbx->do('map.update',$params);};
    if($@){
        warn "Failed to update map with mapid $mapid, check for write permissions for this map\n";
    }
    else {
        if ( $debug > 0 ) {
            print "About to map.update this\n:";
            print Dumper $params;
        }

        if ( $debug > 0 ) {
            print Dumper $result;
        }
    }

    return;
}