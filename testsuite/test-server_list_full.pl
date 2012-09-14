#!/usr/bin/perl -w

use strict;
use testlib;


Master_SetProperty ("maxNbServers", 2);

# The 2 first servers should be accepted
my $server1Ref = Server_New ();
my $server2Ref = Server_New ();

# The 3rd one should be refused
my $server3Ref = Server_New ();
Server_SetProperty ($server3Ref, "cannotBeAnswered", 1);

my $clientRef = Client_New ();


Test_Run ("Server list becomes full");
