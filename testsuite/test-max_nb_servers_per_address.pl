#!/usr/bin/perl -w

use strict;
use testlib;


Master_SetProperty ("maxNbServersPerAddr", 2);

# The 2 first servers should be accepted
my $server1Ref = Server_New ();
my $server2Ref = Server_New ();

# The 3rd one should be refused
my $server3Ref = Server_New ();
Server_SetProperty ($server3Ref, "cannotBeAnswered", 1);

my $clientRef = Client_New ();

Test_Run ("Maximum number of servers per address (IPv4)");


# Run the same test using IPv6
Server_SetProperty ($server1Ref, "useIPv6", 1);
Server_SetProperty ($server2Ref, "useIPv6", 1);
Server_SetProperty ($server3Ref, "useIPv6", 1);

Client_SetProperty ($clientRef, "useIPv6", 1);

Test_Run ("Maximum number of servers per address (IPv6)");
