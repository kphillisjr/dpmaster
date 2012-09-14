#!/usr/bin/perl -w

use strict;
use testlib;


Master_SetProperty ("floodProtectionThrottle", 4);
Master_SetProperty ("hashPorts", 0);

my $serverRef = Server_New ();

my $client1Ref = Client_New ();
my $client2Ref = Client_New ();
my $client3Ref = Client_New ();
my $client4Ref = Client_New ();

# The 4th request should be ignored
Client_SetProperty ($client4Ref, "cannotBeAnswered", 1);
Test_Run ("Flood protection (no retry)");

# The 4th client should be able to get an answer after a 3 sec delay
Client_SetProperty ($client4Ref, "cannotBeAnswered", 0);
Client_SetProperty ($client4Ref, "retryDelay", 3);
Test_Run ("Flood protection (retry after 3 sec)", 5);
