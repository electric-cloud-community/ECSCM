#!/bin/sh

exec "$COMMANDER_HOME/bin/ec-perl" -x "$0" "${@}"

#!perl
# ecscm.cgi -
#
# Get/set ECSCM configuration info for UI
#
# The following special keyword indicates that the "cleanup" script should
# scan this file for formatting errors, even though it doesn't have one of
# the expected extensions.
# CLEANUP: CHECK
#
# Copyright (c) 2007-2009 Electric Cloud, Inc.
# All rights reserved

#use strict;
#no strict "subs";
#use warnings;
use Getopt::Long;
use File::Spec;
use File::Temp;
use ElectricCommander;
use ElectricCommander::PropMod;
use ElectricCommander::Util;
use CGI qw(:standard);

# used for output redirection
$::tmpOut = "";
$::tmpErr = "";
$::oldout;
$::olderr;

#-------------------------------------------------------------------------
# main
#
#      Main program for the application.
#-------------------------------------------------------------------------

sub main() {

    ## globals
    $::cg = CGI->new();
    $::opts = $::cg->Vars;
    $::ec = new ElectricCommander();
    $::ec->abortOnError(0);

    # make sure no libraries print to STDOUT
    saveOutErr();

    # Check for required arguments.
    if (!defined $::opts->{cmd} || "$::opts->{cmd}" eq "") {
        retError("error: cmd is required parameter");
    }

    # load ECSCM object
    my $proj_prop = "/plugins/ECSCM/projectName";
    my $proj = $::ec->getProperty("$proj_prop")->findvalue('//value')->string_value;
    if (!defined $proj || "$proj" eq "" ) {
        retError("Could not find promoted ECSCM plugin");
    }
    my $prop = "/projects/$proj/scm_driver/ECSCM::Base::Cfg";
    if (!ElectricCommander::PropMod::loadPerlCodeFromProperty($::ec,$prop)) {
        retError("Could not load $prop");
    }

    $prop = "/projects/$proj/scm_driver/ECSCM::Base::Driver";
    if (!ElectricCommander::PropMod::loadPerlCodeFromProperty($::ec,$prop)) {
        retError("Could not load $prop");
    }

    # ---------------------------------------------------------------
    # Dispatch operation
    # ---------------------------------------------------------------
    for ($::opts->{cmd})
    {
        # modes
        /getCfgList/i and do   { getCfgList(); last; };
        /getSCMPluginName/i and do   { getSCMPluginName(); last; };
        /getImplementingCfgs/i and do   { getImplementingCfgs(); last; };
    }
    retError("unknown command $::opts->{cmd}");

    exit 0;
}


#############################################
# getCfgList
#
# Return the list of configurations from ECSCM
#############################################
sub getCfgList {

    my $ecscm = new ECSCM::Base::Cfg($::ec,"");

    my %cfgs = $ecscm->getRows();

    # print results as XML block
    my $xml = "";
    $xml .= "<cfgs>\n";
    foreach my $cfg (keys %cfgs) {
        my $scm = new ECSCM::Base::Cfg($::ec,$cfg);
        my $name = $scm->getSCMPluginName();
        my $desc = eval { $ecscm->getCol("$cfg/description") };
        $xml .= "  <cfg>\n";
        $xml .= "     <name>$cfg</name>\n";
        $xml .= "     <plugin>" . xmlQuote($name) . "</plugin>\n";
        $xml .= "     <desc>"   . xmlQuote($desc) . "</desc>\n";
        $xml .= "  </cfg>\n";
    }
    $xml .= "</cfgs>\n";
    printXML($xml);
    exit 0;
}

#############################################
# getImplementingCfgs
#
# Return the list of configurations which
# implement the given method
#############################################
sub getImplementingCfgs {

    my $xml = "";
    if (!defined $::opts->{method}) {
        retError("No method for getImplementCfgs");
        exit 1;
    }

    # fetch all cfgs
    my $ecscm = new ECSCM::Base::Driver($::ec,"");
    my %cfgs = $ecscm->getCfg()->getRows();

    # print out results
    my $implentingCache = ();
    $xml .= "<cfgs>\n";
    foreach my $cfg (keys %cfgs) {
        
        # load each cfg and get its plugin name
        my $scm = new ECSCM::Base::Cfg($::ec,$cfg);
        my $scmPluginName = $scm->getSCMPluginName();

        # make sure a promoted version of the plugin exists
        my $ver = $::ec->getPlugin($scmPluginName)->findvalue('//pluginVersion');
        if (!defined $ver || "$ver" eq "") {
            next;
        }

        # determine whether the cfg's SCM driver implements the given method;
        # cache the answers as we go
        my $isImplemented;
        my $cachedAnswer = $implementingCache->{$scmPluginName};
        
        if (defined $cachedAnswer) {
            $isImplemented = $cachedAnswer;
        } else {
            # load the specific SCM driver to determine if it implements the given method
            my $mod = $ecscm->load_driver("$scmPluginName") ;
            $scm_new = new $mod($ec, $cfg);
            $isImplemented = $scm_new->isImplemented($opts->{method});
            
            # cache the answer for the next time we see this plugin
            $implementingCache->{$scmPluginName} = $isImplemented;
        }
        
        # return both the cfg name and its plugin name
        if ($isImplemented == 1) {
            my $scmPluginDesc = eval { $ecscm->getCol("$cfg/description") };

            $xml .= "<cfg>\n";
            $xml .= "     <name>$cfg</name>\n";
            $xml .= "     <plugin>" . xmlQuote($scmPluginName) . "</plugin>\n";
            $xml .= "     <desc>" . xmlQuote($scmPluginDesc) . "</desc>\n";
            $xml .= "</cfg>\n";
        }
    }
    $xml .= "</cfgs>\n";
    printXML($xml);
    exit 0;
}

##############################################
# retError
#
# return an error message
##############################################
sub retError {
    my $msg = shift;

    printXML("<error>" . escapeHTML($msg) . "</error>\n");
    exit 1;
}

##############################################
# printXML
#
# print the XML block, add stdout, stderr
##############################################
sub printXML {
    my $xml = shift;

    my ($out,$err) = retrieveOutErr();
    print $::cg->header("-type"=>"text/xml", -charset=>'utf-8', getNoCache());
    print "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n";
    print "<response>\n";
    print "$xml\n";
    print "<stdout>" . xmlQuote($out) . "</stdout>\n";
    print "<stderr>" . xmlQuote($err) . "</stderr>\n";
    print "</response>";
}


##############################################
# saveOutErr
#
# redirect stdout/stderr to files so that any
# spurious output from commands does not 
# end up on the return to the cgi caller
##############################################
sub saveOutErr {
    # temporarily save STDOUT/STDERR to files
    open $::oldout, ">&STDOUT"  or die "Can't dup STDOUT: $!";
    open $::olderr, ">&STDERR"  or die "Can't dup STDERR: $!";
    close STDOUT;
    open STDOUT, '>', \$::tmpOut or die "Can't open STDOUT: $!";
    close STDERR;
    open STDERR, '>', \$::tmpErr or die "Can't open STDOUT: $!";

}

##############################################
# retrieveOutErr
#
# reset stdout/sterr back to normal and 
# return the contents of the temp files
##############################################
sub retrieveOutErr {
    # reconnect to normal STDOUT/STDERR
    open STDOUT, ">&", $::oldout or die "can't reinstate $!";
    open STDERR, ">&", $::olderr or die "can't reinstate $!";
    return ($::tmpOut, $::tmpErr);
}

#-------------------------------------------------------------------------
# xmlQuote
#
#      Quote special characters such as & to generate well-formed XML
#      character data.
#
# Results:
#      The return value is identical to $string except that &, <, and >,
#      have been translated to &amp;, &lt;, and &gt;, respectively.
#
# Side Effects:
#      None.
#
# Arguments:
#      string -        String whose contents should be quoted.
#-------------------------------------------------------------------------

sub xmlQuote($) {
    my ($string) = @_;

    $string =~ s/&/&amp;/g;
    $string =~ s/</&lt;/g;
    $string =~ s/>/&gt;/g;
    $string =~ s{([\0-\x{08}\x{0b}\x{0c}\x{0e}-\x{1f}])}{
    sprintf("%%%02x", ord($1))}ge;
    return $string;
}


main();






