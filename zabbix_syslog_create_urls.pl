#!/usr/bin/perl
#fixed URL for ZBX 2.4

use 5.010;
use strict;
use warnings;
use JSON::RPC::Legacy::Client;
use Data::Dumper;
use Config::General;
our $VERSION = 1.1;
my $conf   = Config::General->new('/usr/local/etc/zabbix_syslog.cfg');
my %Config = $conf->getall;

#Authenticate yourself
my $client   = JSON::RPC::Legacy::Client->new();
my $url      = $Config{'url'} || die "URL is missing in zabbix_syslog.cfg\n";
my $user     = $Config{'user'} || die "API user is missing in zabbix_syslog.cfg\n";
my $password = $Config{'password'}   || die "API user password is missing in zabbix_syslog.cfg\n";
my $server = $Config{'server'}   || die "server hostname is missing in zabbix_syslog.cfg\n";

my $debug = $Config{'debug'};
my ( $authID, $response, $json );
my $id = 0;



$authID = login();

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



logout();

#______SUBS
sub get_syslogid_by_hostid {
    my $hostids = shift;

    $json = {
        jsonrpc => '2.0',
        method  => 'item.get',
        params  => {
            output  => ['itemid'],
            hostids => $hostids,
            search  => { 'key_' => 'syslog' },
            limit   => 1,
        },
        id   => $id++,
        auth => $authID,
    };

    $response = $client->call( $url, $json );

    # Check if response was successful
    if ( !$response->content->{'result'} ) {
        logout();
        die "item.get failed\n";
    }

    #return itemid of syslog key (trapper type)
    return ${ $response->content->{'result'} }[0]->{itemid};
}

sub login {

    $json = {
        jsonrpc => '2.0',
        method  => 'user.login',
        params  => {
            user     => $user,
            password => $password

        },
        id => $id++,
    };

    $response = $client->call( $url, $json );

    # Check if response was successful
    die "Authentication failed\n" unless $response->content->{'result'};

    if ( $debug > 0 ) { print Dumper $response->content->{'result'}; }

    return $response->content->{'result'};

}

sub map_get {

    #retrieve all maps
    $json = {
        jsonrpc => '2.0',
        method  => 'map.get',
        params  => {
            output => ['sysmapid']
        },
        id   => $id++,
        auth => "$authID",
    };

    $response = $client->call( $url, $json );

    # Check if response was successful
    if ( !$response->content->{'result'} ) {
        logout();
        die "map.get failed\n";
    }

    if ( $debug > 1 ) { print Dumper $response->content->{result}; }
    return $response->content->{result};

}

sub logout {

    $json = {
        jsonrpc => '2.0',
        method  => 'user.logout',
        params  => {},
        id      => $id++,
        auth    => $authID,
    };

    $response = $client->call( $url, $json );

    # Check if response was successful
    warn "Logout failed\n" unless $response->content->{'result'};

    return;
}

sub map_get_extended {
    $json = {
        jsonrpc => '2.0',
        method  => 'map.get',
        params  => {
            selectSelements => 'extend',
            #sysmapids       => $map,
        },
        id   => $id++,
        auth => $authID,
    };

    $response = $client->call( $url, $json );

    # Check if response was successful
    if ( !$response->content->{'result'} ) {
        logout();
        die "map.get failed\n";
    }
    if ( $debug > 1 ) {

        print Dumper $response->content->{'result'};
    }

    return $response->content->{'result'};
}

sub map_update {
    my $mapid = shift;
    my $selements_ref = shift;
    $json = {
        jsonrpc => '2.0',
        method  => 'map.update',
        params  => {
            selements => [@{$selements_ref}],
            sysmapid  => $mapid,
        },
        id   => $id++,
        auth => $authID,
    };

    if ( $debug > 0 ) {
        print "About to map.update this\n:";
        print Dumper $json;
    }

    $response = $client->call( $url, $json );

    if ( $debug > 0 ) {
        print Dumper $response;
    }

    # Check if response was successful
    if ( !$response->content->{'result'} ) {
        logout();
        die "map.update failed\n";
    }
    return;
}