#!/usr/bin/perl -w

use strict;
use testlib;


my $serverRef = Server_New ();
Server_SetProperty ($serverRef, "useIPv6", 1);

my $clientRef = Client_New ();
Client_SetProperty ($clientRef, "useIPv6", 1);

Test_Run ("Basic IPv6 support");
