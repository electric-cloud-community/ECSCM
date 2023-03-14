#!/bin/sh

exec "$COMMANDER_HOME/bin/ec-perl" -x "$0" "${@}"

#!perl

###############################################################################
# 
# monitorJob.cgi
#
# Monitors a job: waits for it to complete and reports on its success or
# failure.
#
###############################################################################

use strict vars;
use utf8;
use ElectricCommander;
use ElectricCommander::Util;
use XML::XPath;
use CGI;

my $gTimeout = 20;

# -----------------------------------------------------------------------------
# main
#
# -----------------------------------------------------------------------------

sub main {

    # Get CGI args
    my $cgi = new CGI;
    print $cgi->header("-type"=>"text/html", -charset=>'utf-8', getNoCache());
    
    my $cgiArgs = $cgi->Vars;
    
    # Check for required args
    my $jobId = $cgiArgs->{jobId};
    if (!defined $jobId || "$jobId" eq "") {
        reportError("jobId is a required parameter");
    }
    
    # Wait for job
    my $ec = new ElectricCommander({abortOnError => 0});
    my $xpath = $ec->waitForJob($jobId, $gTimeout);
    my $errors = $ec->checkAllErrors($xpath);
    
    if ("$errors" ne "") {
        reportError($errors);
    }
    
    my $status = $xpath->findvalue("//status");
    if ("$status" ne "completed") {
        
        # Abort job and report failure
        abortJobAndReportError($ec, $jobId);
    }
    
    my $outcome = $xpath->findvalue("//outcome");
    if ("$outcome" ne "success") {
        
        # Report job errors
        reportJobErrors($ec, $jobId);
    }
    
    # If the job was successful and the debug flag is not set, delete it
    my $debug = $cgiArgs->{debug};
    if (!defined $debug || "$debug" ne "1") {
        $ec->deleteJob($jobId);
    }
    
    # Report the job's success
    reportSuccess();
}

# -----------------------------------------------------------------------------
# abortJobAndReportError
#
#   Abort the job and report the timeout error.
# -----------------------------------------------------------------------------

sub abortJobAndReportError($$) {
    my ($ec, $jobId) = @_;
    
    my $errMsg = "Aborting job after reaching timeout";
        
    # Try to abort the job
    my $xpath = $ec->abortJob($jobId);
    my $errors = $ec->checkAllErrors($xpath);
    if ("$errors" ne "") {
        reportError($errMsg . "\n" . $errors);
    }
    
    # Wait for the job to finish aborting
    $xpath = $ec->waitForJob($jobId, $gTimeout);
    $errors = $ec->checkAllErrors($xpath);
    if ("$errors" ne "") {
        reportError($errMsg . "\n" . $errors);
    }
    
    # Check to see if the job actually aborted
    my $status = $xpath->findvalue("//status");
    if ("$status" ne "completed") {
        reportError($errMsg . "\nJob still running after abort");
    }
    
    reportError($errMsg . "\nJob successfully aborted");
}

# -----------------------------------------------------------------------------
# reportJobErrors
#
#   Look for errors in the job to report.
# -----------------------------------------------------------------------------

sub reportJobErrors($$) {
    my ($ec, $jobId) = @_;
    
    # Get job details
    my $xpath = $ec->getJobDetails($jobId);
    my $errors = $ec->checkAllErrors($xpath);
    if ("$errors" ne "") {
        reportError($errors);
    }
    
    # Look for configError first
    my $configError = $xpath->findvalue("//job/propertySheet/property[propertyName='configError']/value");
    if (defined $configError && "$configError" ne "") {
        reportError($configError);
    }
    
    # Find the first error message and report it
    my @errorMessages = $xpath->findnodes("//errorMessage");
    if (@errorMessages > 0) {
        my $firstMessage = $errorMessages[0]->string_value();
        reportError($firstMessage);
    }
    
    # Report a generic error message if we couldn't find a specific one on the
    # job
    reportError("Configuration creation failed");
}

# -----------------------------------------------------------------------------
# reportError
#
#   Print the error message and exit.
# -----------------------------------------------------------------------------

sub reportError($) {
    my ($error) = @_;
    
    print $error;
    exit 1;
}

# -----------------------------------------------------------------------------
# reportSuccess
#
#   Report success.
# -----------------------------------------------------------------------------

sub reportSuccess() {
    print "Success";
}

main();
exit 0;
