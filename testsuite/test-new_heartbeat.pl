#!/usr/bin/perl -w

use strict;
use testlib;


Master_SetProperty ("extraOptions", [ "-g", "Warsow", "heartbeat=Warsow" ]);

# Server1's heartbeat advertizes the Warsow game, but send another game name. It shouldn't work
my $server1Ref = Server_New ();
Server_SetProperty ($server1Ref, "masterProtocol", "Warsow");
Server_SetGameProperty ($server1Ref, "gamename", "SomethingElse");
Server_SetProperty ($server1Ref, "cannotBeRegistered", 1);

# Server2's heartbeat advertizes the Warsow game, and uses this game name. It should work
my $server2Ref = Server_New ();
Server_SetProperty ($server2Ref, "masterProtocol", "Warsow");
Server_SetGameProperty ($server2Ref, "gamename", "Warsow");

my $clientRef = Client_New ();
Client_SetGameProperty ($clientRef, "gamename", "Warsow");

Test_Run ("Server using a new heartbeat");
