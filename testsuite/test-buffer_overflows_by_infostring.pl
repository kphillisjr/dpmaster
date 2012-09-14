#!/usr/bin/perl -w

use strict;
use testlib;


my $longValue = "abcdefghijklmnopqrstuvwxyz" x 12;  # 26 * 12 = 312 chars
my $clientRef = Client_New ();
my $serverRef = Server_New ();

# 1st test - a long value
my $previousGamename = Server_GetGameProperty ($serverRef, "gamename");
Server_SetGameProperty ($serverRef, "gamename", $longValue);
Test_Run ("Buffer overflow in infostring, using a long value");

Server_SetGameProperty ($serverRef, "gamename", $previousGamename);

# 2nd test - a long key
Server_SetGameProperty ($serverRef, $longValue, "dummyString");
# We remove the "clients" property to force the master to parse the whole infostring
Server_SetGameProperty ($serverRef, "clients", undef);
Test_Run ("Buffer overflow in infostring, using a long key");
