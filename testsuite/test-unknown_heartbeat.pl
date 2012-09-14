#!/usr/bin/perl -w

use strict;
use testlib;


my $serverRef = Server_New ();
my $clientRef = Client_New ();

Server_SetProperty ($serverRef, "masterProtocol", "Warsow");
Server_SetProperty ($serverRef, "cannotBeAnswered", 1);
Test_Run ("Server sending an unknown heartbeat");
