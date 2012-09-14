#!/usr/bin/perl -w

use strict;
use testlib;


my @serverPropertiesList = (
	# DarkPlaces servers
	{
		family => GAME_FAMILY_DARKPLACES,
		id => "DPServer1",
		protonum => 1,
		game => "Game1",
	},
	{
		family => GAME_FAMILY_DARKPLACES,
		id => "DPServer2",
		protonum => 2,
		game => "Game1",
	},
	{
		family => GAME_FAMILY_DARKPLACES,
		id => "DPServer3",
		protonum => 1,
		game => "Game1",
	},
	{
		family => GAME_FAMILY_DARKPLACES,
		id => "DPServer3",
		protonum => 1,
		game => "Game2",
	},

	# Q3A servers
	{
		family => GAME_FAMILY_QUAKE3ARENA,
		id => "Q3Server1",
		protonum => 2,
	},
	{
		family => GAME_FAMILY_QUAKE3ARENA,
		id => "Q3Server2",
		protonum => 1,
	},
	{
		family => GAME_FAMILY_QUAKE3ARENA,
		id => "Q3Server3",
		protonum => 2,
	},

	# RTCW servers
	{
		family => GAME_FAMILY_RTCW,
		id => "RtCWServer1",
		protonum => 19,
	},

	# WoET servers
	{
		family => GAME_FAMILY_WOET,
		id => "WoETServer1",
		protonum => 20,
	},
);

foreach my $propertiesRef (@serverPropertiesList) {
	my $serverFamily = $propertiesRef->{family};
	my $serverId = $propertiesRef->{id};
	my $serverProtocol = $propertiesRef->{protonum};
	my $serverGame = $propertiesRef->{game};

	# Create the server
	my $serverRef = Server_New ($serverFamily);
	Server_SetProperty ($serverRef, "id", $serverId);
	Server_SetGameProperty ($serverRef, "protocol", $serverProtocol);
	if (defined $serverGame) {
		Server_SetGameProperty ($serverRef, "gamename", $serverGame);
	}

	# Create the associated client
	my $clientId = $serverId;
	$clientId =~ s/Server/Client/;
	my $clientRef = Client_New ($serverFamily);
	Client_SetProperty ($clientRef, "id", $clientId);
	Client_SetGameProperty ($clientRef, "protocol", $serverProtocol);
	if (defined $serverGame) {
		Client_SetGameProperty ($clientRef, "gamename", $serverGame);
	}
}

Test_Run ("Servers running games from different game families");
