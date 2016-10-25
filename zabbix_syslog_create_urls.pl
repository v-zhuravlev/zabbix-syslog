#!/usr/bin/perl
#fixed URL for ZBX 2.4

use 5.010;
use strict;
use warnings;

use FindBin qw($Bin);
use lib "$Bin/lib";
use Data::Dumper;
use Config::General;
use ZabbixAPI;
our $VERSION = 1.1;
my $conf   = Config::General->new('/usr/local/etc/zabbix_syslog.cfg');
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
        #next unless ($mapid == 120 or $mapid == 116); #debug
       #put all mapelements into array @selements (so you can update map later!)
        @selements = @{ $map->{selements} };

        foreach my $selement (@selements) {
            my $syslog_button_exists = 0;

            if ( $debug > 0 ) {
                print 'Object ID: '
                  . $selement->{selementid}
                  . ' Type: '
                  . $selement->{elementtype}
                  . ' Elementid '
                  . $selement->{elementid} . " \n";
            }

            # elementtype=0 hosts
            if ( $selement->{elementtype} == 0 ) {

                my $hostid = $selement->{elementid};

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
            search  => { 'key_' => 'syslog' },
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
    my $result = $zbx->do('map.update',$params);
    if ( $debug > 0 ) {
        print "About to map.update this\n:";
        print Dumper $params;
    }

    if ( $debug > 0 ) {
        print Dumper $result;
    }

    # Check if response was successful
    if ( !$result ) {
        $zbx->logout();
        die "map.update failed\n";
    }
    return;
}