#!/usr/bin/perl -w

use strict;
use testlib;


my @serverPropertiesList = (
	# DarkPlaces servers
	{
		family => GAME_FAMILY_DARKPLACES,
		id => "DPServer0",
		gametype => undef,
	},
	{
		family => GAME_FAMILY_DARKPLACES,
		id => "DPServer1",
		gametype => -2,
	},
	{
		family => GAME_FAMILY_DARKPLACES,
		id => "DPServer2",
		gametype => 0,
	},
	{
		family => GAME_FAMILY_DARKPLACES,
		id => "DPServer3",
		gametype => 3,
	},

	# Warsow servers
	{
		family => GAME_FAMILY_DARKPLACES,
		id => "WSServer0",
		gametype => undef,
	},
	{
		family => GAME_FAMILY_DARKPLACES,
		id => "WSServer1",
		gametype => "ca",
	},
	{
		family => GAME_FAMILY_DARKPLACES,
		id => "WSServer2",
		gametype => "tdm",
	},
	{
		family => GAME_FAMILY_DARKPLACES,
		id => "WSServer3",
		gametype => "classicduel",
	},

	# Q3A servers
	{
		family => GAME_FAMILY_QUAKE3ARENA,
		id => "Q3Server0",
		gametype => undef,
	},
	{
		family => GAME_FAMILY_QUAKE3ARENA,
		id => "Q3Server1",
		gametype => -2,
	},
	{
		family => GAME_FAMILY_QUAKE3ARENA,
		id => "Q3Server2",
		gametype => 0,
	},
	{
		family => GAME_FAMILY_QUAKE3ARENA,
		id => "Q3Server3",
		gametype => 3,
	},
);

my $protocol = 1357;

foreach my $propertiesRef (@serverPropertiesList) {
	my $serverFamily = $propertiesRef->{family};
	my $serverId = $propertiesRef->{id};
	my $serverGametype = $propertiesRef->{gametype};

	# Create the server
	my $serverRef = Server_New ($serverFamily);
	Server_SetProperty ($serverRef, "id", $serverId);
	Server_SetGameProperty ($serverRef, "protocol", $protocol);
	if (defined $serverGametype) {
		Server_SetGameProperty ($serverRef, "gametype", $serverGametype);
	}

	# Create the associated client
	my $clientId = $serverId;
	$clientId =~ s/Server/Client/;
	my $clientRef = Client_New ($serverFamily);
	Client_SetProperty ($clientRef, "id", $clientId);
	Client_SetGameProperty ($clientRef, "protocol", $protocol);
	if (defined $serverGametype) {
		Client_SetGameProperty ($clientRef, "gametype", $serverGametype);
	}
}

Test_Run ("Servers running games using different gametypes and families");
