#!/usr/bin/perl -w

use strict;
use testlib;


Server_New ();

my $clientRef = Client_New ();
Client_SetProperty ($clientRef, "alwaysUseExtendedQuery", 1);

Test_Run ("Client using an extended query (getserversExt)");
