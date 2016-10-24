#!/usr/bin/perl

use 5.010;
use strict;
use warnings;
use JSON::RPC::Legacy::Client;
use Data::Dumper;
use Config::General;
use CHI;
use List::MoreUtils qw (any);
use English '-no_match_vars';
use Readonly;
use MIME::Base64 qw(encode_base64);
use IO::Socket::INET;
our $VERSION = 2.0;

Readonly my $CACHE_TIMEOUT => 600;
Readonly my $CACHE_DIR     => '/tmp/zabbix_syslog_cache';

my $conf   = Config::General->new('/usr/local/etc/zabbix_syslog.cfg');
my %Config = $conf->getall;

#Authenticate yourself
my $client = JSON::RPC::Legacy::Client->new();
my $url = $Config{'url'} || die "URL is missing in zabbix_syslog.cfg\n";
my $user = $Config{'user'} || die "API user is missing in zabbix_syslog.cfg\n";
my $password = $Config{'password'} || die "API user password is missing in zabbix_syslog.cfg\n";
my $server = $Config{'server'} || die "server hostname is missing in zabbix_syslog.cfg\n";


my $debug = $Config{'debug'};
my ( $authID, $response, $json );
my $id = 0;

my $message = shift @ARGV   || die
  "Syslog message required as an argument\n";  #Grab syslog message from rsyslog
chomp($message);

#get ip from message
my $ip;

#IP regex patter part
my $ipv4_octet = q/(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)/;

if ( $message =~ / \[ ((?:$ipv4_octet[.]){3}${ipv4_octet}) \]/msx ) {
    $ip = $1;
}
else {
    die "No IP in square brackets found in '$message', cannot continue\n";
}

my $cache = CHI->new(
    driver   => 'File',
    root_dir => $CACHE_DIR,
);

my $hostname = $cache->get($ip);

if ( !defined $hostname ) {

    $authID = login();
    my @hosts_found;
    my $hostid;
    foreach my $host ( hostinterface_get() ) {

        $hostid = $host->{'hostid'};

        if ( any { /$hostid/msx } @hosts_found ) {
            next;
        }    #check if $hostid already is in array then skip(next)
        else { push @hosts_found, $hostid; }

###########now get hostname
        if ( get_zbx_trapper_syslogid_by_hostid($hostid) ) {

            my $result = host_get($hostid);

            #return hostname if possible
            if ( $result->{'host'} ) {

                if ( $result->{'proxy_hostid'} == 0 )    #check if host monitored directly or via proxy
                {
                    #lease $server as is
                }
                else {
                   #assume that rsyslogd and zabbix_proxy are on the same server
                    $server = 'localhost';
                }
                $hostname = $result->{'host'};
            }

        }

    }
    logout();
    $cache->set( $ip, $hostname, $CACHE_TIMEOUT );
}

zabbix_send( $server, $hostname, 'syslog', $message );

#______SUBS
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

sub hostinterface_get {

    $json = {

        jsonrpc => '2.0',
        method  => 'hostinterface.get',
        params  => {
            output => [ 'ip', 'hostid' ],
            filter => { ip => $ip, },

            #    limit => 1,
        },
        id   => $id++,
        auth => $authID,
    };

    $response = $client->call( $url, $json );

    if ( $debug > 0 ) { print Dumper $response; }

    # Check if response was successful (not empty array in result)
    if ( !@{ $response->content->{'result'} } ) {
        logout();
        die "hostinterface.get failed\n";
    }

    return @{ $response->content->{'result'} }

}

sub get_zbx_trapper_syslogid_by_hostid {

    my $hostids = shift;

    $json = {
        jsonrpc => '2.0',
        method  => 'item.get',
        params  => {
            output  => ['itemid'],
            hostids => $hostids,
            search  => {
                'key_' => 'syslog',
                type   => 2,          #type => 2 is zabbix_trapper
                status => 0,

            },
            limit => 1,
        },
        id   => $id++,
        auth => $authID,
    };

    $response = $client->call( $url, $json );
    if ( $debug > 0 ) { print Dumper $response; }

    # Check if response was successful
    if ( !@{ $response->content->{'result'} } ) {
        logout();
        die "item.get failed\n";
    }

    #return itemid of syslog key (trapper type)
    return ${ $response->content->{'result'} }[0]->{itemid};
}

sub host_get {
    my $hostids = shift;

    $json = {

        jsonrpc => '2.0',
        method  => 'host.get',
        params  => {
            hostids => [$hostids],
            output  => [ 'host', 'proxy_hostid', 'status' ],
            filter => { status => 0, },    # only use hosts enabled
            limit  => 1,
        },
        id   => $id++,
        auth => $authID,
    };

    $response = $client->call( $url, $json );

    if ( $debug > 0 ) { print Dumper $response; }

    # Check if response was successful
    if ( !$response->content->{'result'} ) {
        logout();
        die "host.get failed\n";
    }
    return ${ $response->content->{'result'} }[0];    #return result
}

sub zabbix_send {
    my $zabbixserver = shift;
    my $hostname     = shift;
    my $item         = shift;
    my $data         = shift;
    Readonly my $SOCK_TIMEOUT     => 10;
    Readonly my $SOCK_RECV_LENGTH => 1024;

    my $result;

    my $request =
      sprintf
      "<req>\n<host>%s</host>\n<key>%s</key>\n<data>%s</data>\n</req>\n",
      encode_base64($hostname), encode_base64($item), encode_base64($data);

    my $sock = IO::Socket::INET->new(
        PeerAddr => $zabbixserver,
        PeerPort => '10051',
        Proto    => 'tcp',
        Timeout  => $SOCK_TIMEOUT
    );

    die "Could not create socket: $ERRNO\n" unless $sock;
    $sock->send($request);
    my @handles = IO::Select->new($sock)->can_read($SOCK_TIMEOUT);
    if ( $debug > 0 ) { print "item - $item, data - $data\n"; }

    if ( scalar(@handles) > 0 ) {
        $sock->recv( $result, $SOCK_RECV_LENGTH );
        if ( $debug > 0 ) {
            print "answer from zabbix server $zabbixserver: $result\n";
        }
    }
    else {
        if ( $debug > 0 ) { print "no answer from zabbix server\n"; }
    }
    $sock->close();
    return;
}
