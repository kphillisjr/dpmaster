package testlib;

use strict;
use warnings;

# Libraries
use Fcntl;
use Getopt::Long;
use POSIX qw(:sys_wait_h :stdlib_h);
use Socket;
use Socket6;
use Time::HiRes qw(time sleep);


# Constants - dpmaster
use constant DEFAULT_DPMASTER_PATH => "../src/dpmaster";
use constant IPV4_LOOPBACK_ADDRESS => "127.0.0.1";
use constant IPV6_LOOPBACK_ADDRESS => "::1";
use constant DEFAULT_DPMASTER_PORT => 27950;

# Constants - game properties
use constant DEFAULT_GAMENAME => "DpmasterTest";
use constant DEFAULT_PROTOCOL => 5;
use constant QUAKE3ARENA_GAMENAME => "Quake3Arena";
use constant QUAKE3ARENA_PROTOCOL => 67;
use constant RTCW_GAMENAME => "wolfmp";
use constant RTCW_PROTOCOL => 60;
use constant WOET_GAMENAME => "et";
use constant WOET_PROTOCOL => 84;

# Constants - misc
use constant DEFAULT_SERVER_PORT => 5678;
use constant DEFAULT_CLIENT_PORT => 4321;
use constant {
	GAME_FAMILY_DARKPLACES => 0,
	GAME_FAMILY_QUAKE3ARENA => 1,
	GAME_FAMILY_RTCW => 2,
	GAME_FAMILY_WOET => 3,
};


# Global variables - dpmaster
my $dpmasterPid = undef;
my %dpmasterProperties = (
	exitvalue => undef,
	remoteAddress => undef,

	# Command line options
	allowLoopback => 1,
	floodProtectionThrottle => undef,
	gamePolicy => undef,
	hashPorts => 1,
	maxNbServers => undef,
	maxNbServersPerAddr => undef,
	port => DEFAULT_DPMASTER_PORT,
	extraCmdlineOptions => [],
);

# Global variables - servers
my @serverList = ();
my $nextServerPort = DEFAULT_SERVER_PORT;
my $nextServerId = 0;

# Global variables - clients
my @clientList = ();
my $nextClientPort = DEFAULT_CLIENT_PORT;
my $nextClientId = 0;

# Global variables - misc
my $currentTime = time;
my $testStartTime = undef;
my $mustExit = 0;
my $testNumber = 0;
my @failureDiagnostic = ();

# Command-line options
my $optVerbose = 0;
my $optDpmasterOutput = 0;
my $optDpmasterPath = DEFAULT_DPMASTER_PATH;


#***************************************************************************
# BEGIN block
#***************************************************************************
BEGIN {
	use Exporter ();

	our ($VERSION, @ISA, @EXPORT);
	$VERSION = v1.0;
	@ISA = qw(Exporter);
	@EXPORT = qw(
		&Client_New
		&Client_SetGameProperty
		&Client_SetProperty

		&Master_GetProperty
		&Master_SetProperty

		&Server_GetGameProperty
		&Server_New
		&Server_SetGameProperty
		&Server_SetProperty

		&Test_Run

		GAME_FAMILY_DARKPLACES
		GAME_FAMILY_QUAKE3ARENA
		GAME_FAMILY_RTCW
		GAME_FAMILY_WOET
	);
}


#***************************************************************************
# INIT block
#***************************************************************************
INIT {
	# Parse the options
	GetOptions (
		"verbose" => \$optVerbose,
		"dpmaster-output" => \$optDpmasterOutput,
		"dpmaster-path=s" => \$optDpmasterPath,
	);

	# Install the signal handler
	$SIG{TERM} = $SIG{HUP} = $SIG{INT} = \&Test_SignalHandler;
}


#***************************************************************************
# END block
#***************************************************************************
END {
	Test_StopAll ();
}


#***************************************************************************
# Common_CreateSocket
#***************************************************************************
sub Common_CreateSocket {
	my $port = shift;
	my $useIPv6 = shift;

	my $proto = getprotobyname("udp");

	my ($family, $loopbackAddr);
	if ($useIPv6) {
		$family = AF_INET6;
		$loopbackAddr = IPV6_LOOPBACK_ADDRESS;
	}
	else {
		$family = AF_INET;
		$loopbackAddr = IPV4_LOOPBACK_ADDRESS;
	}

	my ($connectAddr, $bindAddr);
	if ($dpmasterProperties{remoteAddress}) {
		$connectAddr = $dpmasterProperties{remoteAddress};
		$bindAddr = "";
	}
	else {
		$connectAddr = $loopbackAddr;
		$bindAddr = $loopbackAddr;
	}

	# Build the address for connect()
	my @res = getaddrinfo ($connectAddr, $dpmasterProperties{port}, $family, SOCK_DGRAM, $proto, 0);
	if (scalar @res < 5) {
		die "Can't resolve address \"$connectAddr\" (port: $port)";
	}
	my ($sockType, $dpmasterAddr, $canonName);
	($family, $sockType, $proto, $dpmasterAddr, $canonName, @res) = @res;

	# Build the address for bind()
	@res = getaddrinfo ($bindAddr, $port, $family, SOCK_DGRAM, $proto, AI_PASSIVE);
	if (scalar @res < 5) {
		die "Can't resolve address \"$bindAddr\" (port: $port)";
	}
	my $addr;
	($family, $sockType, $proto, $addr, $canonName, @res) = @res;

	# Open an UDP socket
	my $socket;
	socket ($socket, $family, SOCK_DGRAM, $proto) or die "Can't create socket: $!\n";

	# Bind it to the port
	bind ($socket, $addr) or die "Can't bind to port $port: $!\n";

	# Connect the socket to the dpmaster address
	connect ($socket, $dpmasterAddr) or die "Can't connect to the dpmaster address: $!\n";

	# Make the IOs from this socket non-blocking
	Common_SetNonBlockingIO($socket);
	
	return $socket;
}


#***************************************************************************
# Common_VerbosePrint
#***************************************************************************
sub Common_VerbosePrint {

	if ($optVerbose) {
		my $string = shift;

		print ("        " . $string);
	}
}


#***************************************************************************
# Common_SetNonBlockingIO
#***************************************************************************
sub Common_SetNonBlockingIO {
	my $handle = shift;

    my $flags = fcntl ($handle, F_GETFL, 0) or die "Can't get the handle's flags: $!\n";
    fcntl ($handle, F_SETFL, $flags | O_NONBLOCK) or die "Can't set the handle as non-blocking: $!\n";
}


#***************************************************************************
# Client_CheckServerList
#***************************************************************************
sub Client_CheckServerList {
	my $clientRef = shift;
	
	# If this client got no answer
	if ($clientRef->{serverListCount} == 0) {
		if (not $clientRef->{cannotBeAnswered}) {
			push @failureDiagnostic, "Client_CheckServerList: client $clientRef->{id} should have received a response, but it did not";
			return 0;
		}

		return 1;
	}

	if ($clientRef->{cannotBeAnswered}) {
		push @failureDiagnostic, "Client_CheckServerList: client $clientRef->{id} shouldn't have got any response, but it got $clientRef->{serverListCount}";
		return 0;
	}

	my $clUseIPv6 = $clientRef->{useIPv6};
	my $clPropertiesRef = $clientRef->{gameProperties};
	my $clGamename = $clPropertiesRef->{gamename};
	my $clProtocol = $clPropertiesRef->{protocol};
	my $clGametype = $clPropertiesRef->{gametype};

	my $returnValue = 1;

	my %clientServerList = %{$clientRef->{serverList}};
	foreach my $serverRef (@serverList) {
		my $svUseIPv6 = $serverRef->{useIPv6};
		my $svPropertiesRef = $serverRef->{gameProperties};
		my $svGamename = $svPropertiesRef->{gamename};
		my $svProtocol = $svPropertiesRef->{protocol};
		my $svGametype = $svPropertiesRef->{gametype};
		if (not defined $svGametype) {
			$svGametype = "0";
		}
		
		# Skip this server if it doesn't match the conditions
		if (($svUseIPv6 != $clUseIPv6) or
			(not defined ($clProtocol) or ($svProtocol ne $clProtocol)) or
			(defined ($clGametype) and ($svGametype ne $clGametype)) or
			(defined ($svGamename) != defined ($clGamename)) or
			(defined ($svGamename) and ($svGamename ne $clGamename))) {
			next;
		}

		# Skip this server if it shouldn't be registered
		next if ($serverRef->{cannotBeAnswered} or $serverRef->{cannotBeRegistered});

		my $fullAddress = ($svUseIPv6 ? "[" . IPV6_LOOPBACK_ADDRESS . "]" : IPV4_LOOPBACK_ADDRESS);
		$fullAddress .= ":" . $serverRef->{port};
		
		if (exists $clientServerList{$fullAddress}) {
			Common_VerbosePrint ("CheckServerList: found server $fullAddress\n");
			delete $clientServerList{$fullAddress}
		}
		else {
			push @failureDiagnostic, "CheckServerList: server $fullAddress missed by client $clientRef->{id}";
			$returnValue = 0;
		}
	}
	
	# If there is unknown servers in the list
	if (scalar %clientServerList) {
		foreach my $unknownServer (keys %clientServerList) {
			push @failureDiagnostic, "CheckServerList: server $unknownServer erroneously sent to client $clientRef->{id}";
		}
		$returnValue = 0;
	}

	return $returnValue;
}


#***************************************************************************
# Client_HandleGetServersReponse
#***************************************************************************
sub Client_HandleGetServersReponse {
	my $clientRef = shift;
	my $addrList = shift;
	my $extended = shift;

	my $strlen = length($addrList);
	Common_VerbosePrint ("Client received a getservers" . ($extended ? "Ext" : "") . "Response\n");
		
	$clientRef->{serverListCount}++;

	while ($addrList) {
		my ($address, $port, $fullAddress);

		my $separator = unpack ("a1", $addrList);
		if ($separator eq "\\") {
			($separator, $address, $port) = unpack ("a1a4n", $addrList);

			# If end of transmission is found
			if ($address eq "EOT\0" and $port == 0) {
				Common_VerbosePrint ("    * End Of Transmission\n");
				return 1;
			}

			$fullAddress = inet_ntoa ($address) . ":" . $port;
			Common_VerbosePrint ("    * Found a server at $fullAddress\n");
			
			$addrList = substr ($addrList, 7);
		}
		elsif ($separator eq "/") {
			($separator, $address, $port) = unpack ("a1a16n", $addrList);

			$fullAddress = "[" . inet_ntop (AF_INET6, $address) . "]:" . $port;
			Common_VerbosePrint ("    * Found a server at $fullAddress\n");
			
			$addrList = substr ($addrList, 19);
		}
		else {
			Common_VerbosePrint ("    * WARNING: unexpected end of list\n");
			last;
		}

		my $clientServerListRef =  $clientRef->{serverList};
		if (exists $clientServerListRef->{$fullAddress}) {
			Common_VerbosePrint ("        * ERROR: already in the server list!\n");
			$clientServerListRef->{$fullAddress} += 1;
			push @failureDiagnostic, "Client_HandleGetServersReponse: client $clientRef->{id} received address $fullAddress $clientServerListRef->{$fullAddress} times";
		}
		else {
			$clientServerListRef->{$fullAddress} = 1;
		}
	}

	return 0;
}


#***************************************************************************
# Client_New
#***************************************************************************
sub Client_New {
	my $gameFamily = shift;

	if (not defined ($gameFamily)) {
		$gameFamily = GAME_FAMILY_DARKPLACES;
	}

	# Pick a port number
	my $port = $nextClientPort;
	$nextClientPort++;

	# Pick an ID
	my $id = $nextClientId;
	$nextClientId++;

	# Game family specific variables
	my ($gamename, $protocol, $queryFilters);
	$queryFilters = "empty full";
	if ($gameFamily == GAME_FAMILY_QUAKE3ARENA) {
		$gamename = QUAKE3ARENA_GAMENAME;
		$protocol = QUAKE3ARENA_PROTOCOL;
	}
	elsif ($gameFamily == GAME_FAMILY_RTCW) {
		$gamename = RTCW_GAMENAME;
		$protocol = RTCW_PROTOCOL;
	}
	elsif ($gameFamily == GAME_FAMILY_WOET) {
		$gamename = WOET_GAMENAME;
		$protocol = WOET_PROTOCOL;
		$queryFilters = "";		# WoET never send "empty" and "full"
	}
	else {  # $gameFamily == GAME_FAMILY_DARKPLACES
		$gamename = DEFAULT_GAMENAME;
		$protocol = DEFAULT_PROTOCOL;
	}

	my $newClient = {
		family => $gameFamily,
		id => $id,
		state => undef,  # undef -> Init -> WaitingServerList -> Done
		lastRequestTime => 0,
		port => $port,
		socket => undef,
		serverList => {},
		serverListCount => 0,  # Nb of server lists received
		alwaysUseExtendedQuery => 0,
		cannotBeAnswered => undef,
		useIPv6 => 0,
		queryFilters => $queryFilters,
		ignoreEOTMarks => 0,
		retryDelay => undef,

		gameProperties => {
			gamename => $gamename,
			protocol => $protocol
		}
	};
	push @clientList, $newClient;

	return $newClient;
}


#***************************************************************************
# Client_Run
#***************************************************************************
sub Client_Run {
	my $clientRef = shift;

	my $state = $clientRef->{state};

	# "Init" state
	if ($state eq "Init") {
		# TODO: find a smarter way to determine when the servers can start
		if ($currentTime > $testStartTime + 1) {
			Client_SendGetServers ($clientRef);
			$clientRef->{state} = "WaitingServerList";
		}
	}

	# "WaitingServerList" state
	elsif ($state eq "WaitingServerList") {
		my $recvPacket;
		if (recv ($clientRef->{socket}, $recvPacket, 1500, 0)) {
			# If we received a server list, unpack it
			if ($recvPacket =~ /^\xFF\xFF\xFF\xFFgetservers(Ext)?Response[\\\/]/) {
				my $extended = ((defined $1) and ($1 eq "Ext"));
				my $addrList = substr ($recvPacket, $extended ? 25 : 22);

				my $eotFound = Client_HandleGetServersReponse($clientRef, $addrList, $extended);
				if ($eotFound) {
					if ($clientRef->{ignoreEOTMarks}) {
						Common_VerbosePrint ("EOT mark ignored. Waiting for the next packet\n");
					}
					else {
						$clientRef->{state} = "Done";
					}
				}
				else {
					Common_VerbosePrint ("No EOT mark found. Waiting for the next packet\n");
				}
			}
			else {
				# FIXME: report the error correctly instead of just dying
				die "Invalid message received while waiting for the server list";
			}
		}
		
		if ($clientRef->{serverListCount} == 0) {
			if (defined ($clientRef->{retryDelay})) {
				# If enough time has passed since our last request, try one more time to get an answer 
				if ($clientRef->{lastRequestTime} + $clientRef->{retryDelay} <= $currentTime) {
					Client_SendGetServers ($clientRef);
				}
			}
		}
	}

	# "Done" state
	elsif ($state eq "Done") {
		# Nothing to do
	}

	# Invalid state
	else {
		die "Invalid client state: $state";
	}
}


#***************************************************************************
# Client_SendGetServers
#***************************************************************************
sub Client_SendGetServers {
	my $clientRef = shift;

	my $getservers = "getservers";

	my $useExtendedQuery;
	if ($clientRef->{useIPv6} or $clientRef->{alwaysUseExtendedQuery}) {
		$useExtendedQuery = 1;
		$getservers .= "Ext";
	}
	else {
		$useExtendedQuery = 0;
	}

	Common_VerbosePrint ("Sending $getservers from client $clientRef->{id}\n");
	
	# Add the message header
	$getservers = "\xFF\xFF\xFF\xFF" . $getservers;

	my $gameProp = $clientRef->{gameProperties};

	if ($clientRef->{family} == GAME_FAMILY_DARKPLACES or $useExtendedQuery) {
		if (defined ($gameProp->{gamename})) {
			$getservers .= " $gameProp->{gamename}";
		}
	}
	if (defined $gameProp->{protocol}) {
		$getservers .= " $gameProp->{protocol}";
	}
	if (defined $clientRef->{queryFilters}) {
		$getservers .= " $clientRef->{queryFilters}";
	}

	my $gametype = $gameProp->{gametype};
	if (defined $gametype) {
		my $gametypeFilter = "gametype=$gametype";

		# Q3A uses shortcuts for the gametype test
		if ($clientRef->{family} == GAME_FAMILY_QUAKE3ARENA) {
			if ($gametype == "0") {
				$gametypeFilter = "ffa";
			}
			elsif ($gametype == "1") {
				$gametypeFilter = "tourney";
			}
			elsif ($gametype == "3") {
				$gametypeFilter = "team";
			}
			elsif ($gametype == "4") {
				$gametypeFilter = "ctf";
			}
		}

		$getservers .= " $gametypeFilter";
	}

	send ($clientRef->{socket}, $getservers, 0) or die "Can't send packet: $!";
	$clientRef->{lastRequestTime} = $currentTime;

	if (not defined $clientRef->{cannotBeAnswered}) {
		$clientRef->{cannotBeAnswered} = not (Client_ValidateGetServers ($getservers) and Master_IsGameAccepted ($gameProp->{gamename}));
	}
}


#***************************************************************************
# Client_SetGameProperty
#***************************************************************************
sub Client_SetGameProperty {
	my $clientRef = shift;
	my $propertyName = shift;
	my $propertyValue = shift;
	
	$clientRef->{gameProperties}{$propertyName} = $propertyValue;
}

	
#***************************************************************************
# Client_SetProperty
#***************************************************************************
sub Client_SetProperty {
	my $clientRef = shift;
	my $propertyName = shift;
	my $propertyValue = shift;
	
	# If the property doesn't exist, there is a problem in the caller script
	die "Client_SetProperty: property \"$propertyName\" is unknown" if (not exists $clientRef->{$propertyName});

	$clientRef->{$propertyName} = $propertyValue;
}

	
#***************************************************************************
# Client_Start
#***************************************************************************
sub Client_Start {
	my $clientRef = shift;

	$clientRef->{socket} = Common_CreateSocket ($clientRef->{port}, $clientRef->{useIPv6});
	$clientRef->{state} = "Init";
	$clientRef->{lastRequestTime} = 0;
}

	
#***************************************************************************
# Client_Stop
#***************************************************************************
sub Client_Stop {
	my $clientRef = shift;

	my $socket = $clientRef->{socket};
	if (defined ($socket)) {
		close ($socket);
		$clientRef->{socket} = undef;
	}

	# Clean the server list
	$clientRef->{serverList} = {};
	$clientRef->{serverListCount} = 0;
	
	$clientRef->{cannotBeAnswered} = undef;
}

	
#***************************************************************************
# Client_ValidateGetServers
#***************************************************************************
sub Client_ValidateGetServers {
	my $getservers = shift;
	
	if ($getservers =~ /^\xFF\xFF\xFF\xFFgetservers(Ext)? (.*)$/) {
		my $isExtended = (defined $1 and $1 eq "Ext");
		my $payload = $2;
		
		if ($payload =~ /^ *([^ ]+ )?(-?\d+)( .*)?$/) {
			my $gamename = $1;
			my $protocol = $2;
			my $filters = $3;
			
			if (not defined $gamename and $isExtended) {
				Common_VerbosePrint ("getservers NOT valided: extended query is missing the game name\n");
				return 0;
			}

			Common_VerbosePrint ("getservers valided\n");
			return 1;
		}
		else {
			Common_VerbosePrint ("getservers NOT valided: invalid payload\n");
		}
	}
	else {
		Common_VerbosePrint ("getservers NOT valided: invalid header\n");
	}
	
	return 0;
}

	
#***************************************************************************
# Master_IsGameAccepted
#***************************************************************************
sub Master_IsGameAccepted {
	my $gamename = shift;
	
	my $gamePolicy = $dpmasterProperties{gamePolicy};
	if (not defined ($gamePolicy)) {
		return 1;
	}
	
	my $returnValueWhenFound = ($gamePolicy->{policy} eq "accept");
	
	my $returnedValue;
	if (grep { $_ eq $gamename } @{$gamePolicy->{gamenames}}) {
		$returnedValue = $returnValueWhenFound;
	}
	else {
		$returnedValue = not $returnValueWhenFound;
	}
	
	if ($returnedValue) {
		Common_VerbosePrint ("Master accepts game \"$gamename\"\n");
	}
	else {
		Common_VerbosePrint ("Master REJECTS game \"$gamename\"\n");
	}
	
	return $returnedValue;
}

	
#***************************************************************************
# Master_Run
#***************************************************************************
sub Master_Run {
	# If we use a remote master, there's nothing to do
	if ($dpmasterProperties{remoteAddress}) {
		return;
	}

	# Print the master server output
	while (<DPMASTER_PROCESS>) {
		if ($optDpmasterOutput) {
			Common_VerbosePrint ("[DPM] $_");
		}
	}
}

	
#***************************************************************************
# Master_GetProperty
#***************************************************************************
sub Master_GetProperty {
	my $propertyName = shift;
	
	return $dpmasterProperties{$propertyName};
}

	
#***************************************************************************
# Master_SetProperty
#***************************************************************************
sub Master_SetProperty {
	my $propertyName = shift;
	my $propertyValue = shift;
	
	# Check the validity of the property, if possible
	if ($propertyName eq "gamePolicy" and defined $propertyValue) {
		my $policy = $propertyValue->{policy};
		if ($policy ne "accept" and $policy ne "reject") {
			die "Master_SetProperty: Invalid game policy \"$policy\" (must be \"accept\" or \"reject\")";
		}
		
		if (scalar @{$propertyValue->{gamenames}} <= 0) {
			die "Master_SetProperty: no game names specified for the game policy";
		}
	}

	$dpmasterProperties{$propertyName} = $propertyValue;
}


#***************************************************************************
# Master_Start
#***************************************************************************
sub Master_Start {
	# If we use a remote master, there's nothing to do
	if ($dpmasterProperties{remoteAddress}) {
		return;
	}
	
	my $dpmasterCmdLine = $optDpmasterPath . " -p $dpmasterProperties{port}";
	
	if ($optDpmasterOutput) {
		$dpmasterCmdLine .= " -v";
	}
	
	if (defined $dpmasterProperties{maxNbServers}) {
		$dpmasterCmdLine .= " -n $dpmasterProperties{maxNbServers}";
	}
	
	if (defined $dpmasterProperties{floodProtectionThrottle}) {
		$dpmasterCmdLine .= " -f --fp-throttle $dpmasterProperties{floodProtectionThrottle}";
	}
	
	# "--hash-ports" and "-N" are mutually incompatible options
	if (defined $dpmasterProperties{maxNbServersPerAddr}) {
		$dpmasterCmdLine .= " -N $dpmasterProperties{maxNbServersPerAddr}";
	}
	else {
		if ($dpmasterProperties{hashPorts}) {
			$dpmasterCmdLine .= " --hash-ports";
		}
	}
	
	if ($dpmasterProperties{allowLoopback}) {
		$dpmasterCmdLine .= " --allow-loopback";
	}
	
	my $gamePolicyRef = $dpmasterProperties{gamePolicy};
	if (defined $gamePolicyRef) {
		$dpmasterCmdLine .= " --game-policy $gamePolicyRef->{policy}";
		foreach my $gamename (@{$gamePolicyRef->{gamenames}}) {
			$dpmasterCmdLine .= " $gamename";
		}
	}
	
	my $extraOptionsRef = $dpmasterProperties{extraOptions};
	if (defined $extraOptionsRef) {
		foreach my $extraOption (@{$extraOptionsRef}) {
			$dpmasterCmdLine .= " $extraOption";
		}
	}

	Common_VerbosePrint ("Launching dpmaster as: $dpmasterCmdLine\n");
	$dpmasterPid = open DPMASTER_PROCESS, "$dpmasterCmdLine |";
	if (not defined $dpmasterPid) {
	   die "Can't run dpmaster: $!\n";
	}

	# Make the IOs from dpmaster's pipe non-blocking
	Common_SetNonBlockingIO(\*DPMASTER_PROCESS);
	
	# Wait for the master to be ready
	# TODO: find a better way to do this
	sleep (0.5);
}


#***************************************************************************
# Master_Stop
#***************************************************************************
sub Master_Stop {
	# If we use a remote master, there's nothing to do
	if ($dpmasterProperties{remoteAddress}) {
		return;
	}

	# Kill dpmaster if it's still running
	if (defined ($dpmasterPid)) {
		kill ("HUP", $dpmasterPid);
		$dpmasterPid = undef;
	}

	# Close the pipe
	close (DPMASTER_PROCESS);
}

	
#***************************************************************************
# Server_GetGameProperty
#***************************************************************************
sub Server_GetGameProperty {
	my $serverRef = shift;
	my $propertyName = shift;
	
	return $serverRef->{gameProperties}{$propertyName};
}


#***************************************************************************
# Server_New
#***************************************************************************
sub Server_New {
	my $gameFamily = shift;

	if (not defined ($gameFamily)) {
		$gameFamily = GAME_FAMILY_DARKPLACES;
	}

	# Pick a port number
	my $port = $nextServerPort;
	$nextServerPort++;

	# Pick an ID
	my $id = $nextServerId;
	$nextServerId++;


	# Game family specific variables
	my ($gamename, $protocol, $masterProtocol);
	if ($gameFamily == GAME_FAMILY_QUAKE3ARENA) {
		$gamename = QUAKE3ARENA_GAMENAME;
		$protocol = QUAKE3ARENA_PROTOCOL;
		$masterProtocol = "QuakeArena-1";
	}
	elsif ($gameFamily == GAME_FAMILY_RTCW) {
		$gamename = RTCW_GAMENAME;
		$protocol = RTCW_PROTOCOL;
		$masterProtocol = "Wolfenstein-1";
	}
	elsif ($gameFamily == GAME_FAMILY_WOET) {
		$gamename = WOET_GAMENAME;
		$protocol = WOET_PROTOCOL;
		$masterProtocol = "EnemyTerritory-1";
	}
	else {  # $gameFamily == GAME_FAMILY_DARKPLACES
		$gamename = DEFAULT_GAMENAME;
		$protocol = DEFAULT_PROTOCOL;
		$masterProtocol = "DarkPlaces";
	}

	my $newServer = {
		family => $gameFamily,
		id => $id,
		state => undef,  # undef -> Init -> WaitingGetInfos -> Done
		heartbeatTime => undef,
		port => $port,
		masterProtocol => $masterProtocol,
		socket => undef,
		cannotBeRegistered => 0,
		cannotBeAnswered => 0,
		useIPv6 => 0,
		
		gameProperties => {
			gamename => $gamename,
			protocol => $protocol,
			sv_maxclients => 8,
			clients => 2
		}
	};
	push @serverList, $newServer;

	return $newServer;
}

	
#***************************************************************************
# Server_Run
#***************************************************************************
sub Server_Run {
	my $serverRef = shift;

	my $state = $serverRef->{state};

	# "Init" state
	if ($state eq "Init") {
		# If it's time to send an heartbeat
		if ($currentTime >= $serverRef->{heartbeatTime}) {
			Server_SendHeartbeat ($serverRef);

			$serverRef->{heartbeatTime} = undef;
			$serverRef->{state} = "WaitingGetInfos";
		}
	}

	# "WaitingGetInfos" state
	elsif ($state eq "WaitingGetInfos") {
		my $recvPacket;
		if (recv ($serverRef->{socket}, $recvPacket, 1500, 0)) {
			# If we received a getinfo message, reply to it
			if ($recvPacket =~ /^\xFF\xFF\xFF\xFFgetinfo +(\S+)$/) {
				my $challenge = $1;
				Common_VerbosePrint ("Server $serverRef->{id} received a getinfo with challenge \"$challenge\"\n");
				
				if ($serverRef->{cannotBeAnswered}) {
					push @failureDiagnostic, "Server_Run: server $serverRef->{id} got a getinfo message when it should have been ignored by the master";
					$mustExit = 1;
				}

				Server_SendInfoResponse ($serverRef, $challenge);
				$serverRef->{state} = "Done";
			}
			else {
				# FIXME: report the error correctly instead of just dying
				die "Invalid message received while waiting for getinfos";
			}
		}
	}

	# "Done" state
	elsif ($state eq "Done") {
		# Nothing to do
	}

	# Invalid state
	else {
		die "Invalid server state: $state";
	}
}

	
#***************************************************************************
# Server_SendHeartbeat
#***************************************************************************
sub Server_SendHeartbeat {
	my $serverRef = shift;

	Common_VerbosePrint ("Sending heartbeat from server $serverRef->{id}\n");
	my $heartbeat = "\xFF\xFF\xFF\xFFheartbeat $serverRef->{masterProtocol}\x0A";
	send ($serverRef->{socket}, $heartbeat, 0) or die "Can't send packet: $!";
	
	if (not $serverRef->{cannotBeAnswered}) {
		$serverRef->{cannotBeAnswered} = not $dpmasterProperties{allowLoopback};
		if ($serverRef->{cannotBeAnswered}) {
			Common_VerbosePrint ("server cannot be answered: no servers allowed on loopback interfaces\n");
		}
	}
}

	
#***************************************************************************
# Server_SendInfoResponse
#***************************************************************************
sub Server_SendInfoResponse {
	my $serverRef = shift;
	my $challenge = shift;

	Common_VerbosePrint ("Sending infoResponse from server $serverRef->{id}\n");
	my $infoResponse = "\xFF\xFF\xFF\xFFinfoResponse\x0A" . 
						"\\challenge\\$challenge";

	# Append all game properties to the message
	while (my ($propKey, $propValue) = each %{$serverRef->{gameProperties}}) {
		if (defined ($propValue) and
			($propKey ne "gamename" or $serverRef->{family} != GAME_FAMILY_QUAKE3ARENA)) {
			$infoResponse .= "\\$propKey\\$propValue";
		}
	}
	
	$serverRef->{cannotBeRegistered} = not (Server_ValidateInfoResponse ($infoResponse) and Master_IsGameAccepted ($serverRef->{gameProperties}{gamename}));

	send ($serverRef->{socket}, $infoResponse, 0) or die "Can't send packet: $!";
}

	
#***************************************************************************
# Server_SetGameProperty
#***************************************************************************
sub Server_SetGameProperty {
	my $serverRef = shift;
	my $propertyName = shift;
	my $propertyValue = shift;
	
	$serverRef->{gameProperties}{$propertyName} = $propertyValue;
}

	
#***************************************************************************
# Server_SetProperty
#***************************************************************************
sub Server_SetProperty {
	my $serverRef = shift;
	my $propertyName = shift;
	my $propertyValue = shift;
	
	# If the property doesn't exist, there is a problem in the caller script
	die if (not exists $serverRef->{$propertyName});

	$serverRef->{$propertyName} = $propertyValue;
}

	
#***************************************************************************
# Server_Start
#***************************************************************************
sub Server_Start {
	my $serverRef = shift;

	$serverRef->{socket} = Common_CreateSocket($serverRef->{port}, $serverRef->{useIPv6});
	$serverRef->{state} = "Init";
	$serverRef->{heartbeatTime} = $currentTime;
}

	
#***************************************************************************
# Server_Stop
#***************************************************************************
sub Server_Stop {
	my $serverRef = shift;

	my $socket = $serverRef->{socket};
	if (defined ($socket)) {
		close ($socket);
		$serverRef->{socket} = undef;
	}

	$serverRef->{cannotBeRegistered} = 0;
}

	
#***************************************************************************
# Server_ValidateInfoResponse
#***************************************************************************
sub Server_ValidateInfoResponse {
	my $infoReponse = shift;
	
	if ($infoReponse =~ /^\xFF\xFF\xFF\xFFinfoResponse\x0A\\(.*)$/) {
		my @infostringElts = split (/\\/, $1);
		if (scalar @infostringElts % 2 == 0) {
			my %infostringMap = @infostringElts;
			
			# Look for keys or values with an unsupported length (>=256)
			# NOTE that it's an implementation-specific limit. The protocol
			# itself puts no limit to the length of keys and values.
			foreach my $key (keys (%infostringMap)) {
				#print ">>> \"", $key, "\"=\"", $infostringMap{$key}, "\"\n";
				if (length ($key) >= 256) {
					Common_VerbosePrint ("infoResponse NOT valided: key \"$key\" is too long\n");
					return 0;
				}
				if (length ($infostringMap{$key}) >= 256) {
					Common_VerbosePrint ("infoResponse NOT valided: value \"$infostringMap{$key}\" is too long\n");
					return 0;
				}
			}

			my $gamename = $infostringMap{gamename};
			if (defined $gamename) {
				# Check that the gamename value contains no whitespaces
				if (index ($gamename, " ") > 0) {
					Common_VerbosePrint ("infoResponse NOT valided: gamename contains whitespaces\n");
					return 0;
				}
			}
			
			# Check that there is a "clients" key
			if (not defined $infostringMap{clients}) {
				Common_VerbosePrint ("infoResponse NOT valided: no \"clients\" key\n");
				return 0;
			}

			Common_VerbosePrint ("infoResponse valided\n");
			return 1;
		}		
	}
	
	return 0;
}


#***************************************************************************
# Test_RunAll
#***************************************************************************
sub Test_RunAll {
	Master_Run ();

	foreach my $server (@serverList) {
		Server_Run ($server);
	}

	foreach my $client (@clientList) {
		Client_Run ($client);
	}
}


#***************************************************************************
# Test_SignalHandler
#***************************************************************************
sub Test_SignalHandler {
	# If it's the second time we get a signal during this frame, just exit
	if ($mustExit) {
		die "Double signal received\n";
	}
	$mustExit = 1;

	my $signal = shift;
	Common_VerbosePrint ("Signal $signal received. Exiting...\n");
}


#***************************************************************************
# Test_StartAll
#***************************************************************************
sub Test_StartAll {
	$testStartTime = $currentTime;

	Master_Start ();

	foreach my $server (@serverList) {
		Server_Start ($server);
	}

	foreach my $client (@clientList) {
		Client_Start ($client);
	}
}


#***************************************************************************
# Test_StopAll
#***************************************************************************
sub Test_StopAll {
	foreach my $client (@clientList) {
		Client_Stop ($client);
	}

	foreach my $server (@serverList) {
		Server_Stop ($server);
	}

	Master_Stop ();
}


#***************************************************************************
# Test_Run
#***************************************************************************
sub Test_Run {
	my $testTitle = shift;
	my $testDuration = shift;
	my $skipServerListCheck = shift;
	
	$testNumber++;
	if (not defined ($testTitle)) {
		$testTitle = "Test " . $testNumber;
	}
	print ("    * " . $testTitle . "\n");

	@failureDiagnostic = ();
	$currentTime = time();

	Test_StartAll ();

	if (not defined ($testDuration)) {
		$testDuration = 3;  # 3 sec of test, by default
	}
	my $testTime = $currentTime + $testDuration;
	my $exitValue = undef;

	for (;;) {
		$currentTime = time;

		# Check exit conditions
		last if ($mustExit or $currentTime >= $testTime);

		Test_RunAll ();

		# Unless we use a remote master
		unless ($dpmasterProperties{remoteAddress}) {
			# If the dpmaster process is dead
			if (waitpid($dpmasterPid, WNOHANG) == $dpmasterPid) {
				$exitValue = $? >> 8;
				my $receivedSignal = $? & 127;
				Common_VerbosePrint ("Dpmaster end status: $? (exit value = $exitValue, received signal = $receivedSignal)...\n");
				last;
			}
		}

		# Sleep a bit to avoid wasting the CPU time
		sleep (0.1);
	}

	my $Result = EXIT_SUCCESS;

	# Unless we use a remote master
	unless ($dpmasterProperties{remoteAddress}) {
		# If the dpmaster process is in the expected state
		my $expectedExitValue = $dpmasterProperties{exitvalue};
		if ((defined ($expectedExitValue) != defined ($exitValue)) or
			(defined ($expectedExitValue) and defined ($exitValue) and $expectedExitValue != $exitValue)) {
			$Result = EXIT_FAILURE;
		
			my $state;
			if (defined ($exitValue)) {
				$state = "dead";
			}
			else
			{
				$state = "running";
			}
			push @failureDiagnostic, "The dpmaster process is in an unexpected state ($state)";
		}
	}

	# Check that the server lists we got are valid
	unless ($skipServerListCheck) {
		if ($Result == EXIT_SUCCESS) {
			foreach my $client (@clientList) {
				if (not Client_CheckServerList ($client)) {
					$Result = EXIT_FAILURE;
					last;
				}
			}
		}
	}

	# TODO: any other tests?

	if ($Result == EXIT_SUCCESS) {
		print ("        Test passed\n");
	}
	else {
		print ("        Test FAILED\n");

		foreach my $diagnosticText (@failureDiagnostic) {
			print ("            " . $diagnosticText . "\n");
		}
	}

	Test_StopAll ();

	print ("\n");
	return ($Result);
}


return 1;
