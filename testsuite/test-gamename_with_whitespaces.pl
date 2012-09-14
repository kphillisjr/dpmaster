#!/usr/bin/perl -w

use strict;
use testlib;


my $gamename = "Dpmaster Test";

my $serverRef = Server_New ();
Server_SetGameProperty ($serverRef, "gamename", $gamename);

my $clientRef = Client_New ();
Client_SetGameProperty ($clientRef, "gamename", $gamename);

Test_Run ("Game name containing whitespaces");
