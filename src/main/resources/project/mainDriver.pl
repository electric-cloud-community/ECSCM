#!/usr/bin/env perl
# -*-Perl-*-

# ecclientpreflight -
#
# This script is eval'ed by ecclientpreflight.
#   - Gathers the command-line arguments and provides SCM-independent helper
#     subroutines.
#   - Retrieves and invokes the SCM-specific driver script which then gathers
#     deltas, starts the build, and uploads/copies deltas so the agent can
#     overlay them over a clean source snapshot.
#
# The following special keyword indicates that the "cleanup" script should
# scan this file for formatting errors, even though it doesn't have one of
# the expected extensions.
# CLEANUP: CHECK
#
# Copyright (c) 2008-2010 Electric Cloud, Inc.
# All rights reserved

#------------------------------------------------------------------------------
# Appended text to print in response to --help.
#------------------------------------------------------------------------------

$::gVersion = "@PLUGIN_VERSION@";

$::gHelpMessage .= "
Logging Options:
  -l,--log                  If specified, debug information will be logged.
                            Off by default.
  --logDir                  Where to store log and other files.  Defaults to
                            the user's home directory.

Procedure Invocation Options:

  --projectName <name>      The name of the Commander project containing the
                            procedure to invoke.
  --procedureName <name>    The name of the Commander procedure to invoke.
  -p,--param <name>=<value> Supply additional parameters to the procedure.
                            May appear multiple times.  If any parameters were
                            specified in the config file, then those supplied
                            on the command-line will append to that list,
                            overriding parameters with the same name.
  --priority <priority>     The priority of the job.  Possible values are
                            low, normal, high, highest.  If left unspecified,
                            defaults to normal.
  --jobTimeout <timeout>    The number of seconds to wait for the job to
                            complete when auto-committing changes.  Defaults
                            to 3600 seconds (1 hour).
  --waitForJob              Wait for the job to complete and report its
                            outcome.  Not done by default, unless a set of
                            SCM changes are being automatically committed.
  --runOnly                 Run the procedure and exit immediately.  The SCM
                            driver will not be downloaded in this case.

SCM Options:

  --scmType <scm>           The name of the SCM.  The driver will be downloaded
                            from \$driverLocation/clientDrivers/\$scmType.
                            Required unless the procedure is invoked in 'run
                            only' mode.
  --autoCommit <1|0>        Whether or not the changes should be automatically
                            committed if the job completes successfully.  Off
                            by default.
  --commitComment <comment> The comment to go along with the auto-commit.
";

#------------------------------------------------------------------------------
# Command-line options.  For details, see the corresponding entries in the help
# message above.
#------------------------------------------------------------------------------

# General options.

$::gLog = 0;
$::gLogDir = "";

# Procedure invocation options.

$::gProjectName = undef;
$::gProcedureName = undef;
$::gPriority = undef;
%::gExtraParameters = ();
$::gJobTimeout = undef;
$::gWaitForJob = undef;
$::gRunOnly = undef;
%::gSCMArgs = ();

# SCM options.

$::gScm = undef;

# Commit options.

$::gAutoCommit = undef;
$::gCommitComment = undef;

# Input for GetOptions:

%::gClientOptions = (
        "log|l"             => \$::gLog,
        "logDir=s"          => \$::gLogDir,

        # Procedure invocation options:

        "projectName=s"     => \$::gProjectName,
        "procedureName=s"   => \$::gProcedureName,
        "parameter|p=s"     => \%::gExtraParameters,
        "priority=s"        => \$::gPriority,
        "jobTimeout=s"      => \$::gJobTimeout,
        "waitForJob"        => \$::gWaitForJob,
        "runOnly"           => \$::gRunOnly,

        # SCM options:

        "scmType=s"         => \$::gScm,
        "autoCommit=s"      => \$::gAutoCommit,
        "commitComment=s"   => \$::gCommitComment,
    );

#------------------------------------------------------------------------------
# Global variables.
#------------------------------------------------------------------------------

# Procedure invocation options.

@::gParameters = ();

# Other globals.

$::gJobId = undef;
$::gJobNotesId = undef;
$::gWaitForStep = 0;
%::gFilesToUpload = ();
%::gFilesToCommit = ();
$::gTargetDirectory = "";
$::gLatestTimestamp = 0;
$::gTesting = 0;
$::gWaitedForJob = 0;

#------------------------------------------------------------------------------
# runCommand
#
#       Invokes a given command.  If no error occurs, then the command's output
#       is returned.  If an error occurs, then based on the caller's choice,
#       either the error is printed and the program is killed, or both stdout
#       and stderr are returned.
#
# Arguments:
#       command -           The command to invoke.
#       properties -        (Optional) A hash of supported properties:
#       * dieOnError -      Defaults to true.  If set to false, then errors
#                           will be suppressed (included in stdout), and the
#                           combined result will be returned.
#       * ignoredErrors     Pattern to ignore in error output
#       * input -           Input to pipe into the command.
#------------------------------------------------------------------------------

sub runCommand($;$) {
    my ($command, $properties) = @_;

    my $originalCommand = $command;
    my $dieOnError      = 1;
    my $input;
    my $ignoredErrors   = "";

    if (defined($properties->{dieOnError})) {
        $dieOnError = $properties->{dieOnError};
    }
    if (defined($properties->{input})) {
        $input = $properties->{input};
    }
    if (defined($properties->{ignoredErrors})) {
        $ignoredErrors = $properties->{ignoredErrors};
    }

    # Redirect errors according to the "dieOnError" option.

    my $errorFile;
    if ($dieOnError) {
        $errorFile = "$::gLogDir/_err";
        $command .= " 2>\"$errorFile\"";
    } else {
        $command .= " 2>&1";
    }

    # If standard input is provided, open a pipe to the command and print
    # the input to the pipe.  Otherwise, just run the command.

    my $out;
    if (defined($input)) {
        my (undef, $outputName) =
                File::Temp::tempfile("ecout_XXXXXX", OPEN => 0,
                DIR => File::Spec->tmpdir);
        open(PIPE, "|-", "$command >\"$outputName\"")
                or error("Cannot open pipe to \"$outputName\": $!");
        print(PIPE $input);
        close(PIPE);
        open(FILE, $outputName)
                or error("Cannot open file \"$outputName\": $!");
        my @fileContents = <FILE>;
        $out = join("", @fileContents);
        close(FILE);
        unlink($outputName);
    } else {
        $out = `$command`;
    }
    if ($dieOnError) {
        my $exit = $? >> 8;
        my $err = "";
        open(ERR, $errorFile) or error("Cannot open file \"$errorFile\": $!");
        my @contents = <ERR>;
        $err = join("", @contents);
        close(ERR);
        unlink($errorFile);

        # Strip out ignored errors
        if ($ignoredErrors ne "") {
            $err =~ s/$ignoredErrors//gm;
        }

        if ($exit != 0 || $err ne "") {
            error("Command \"$originalCommand\" failed with exit code $exit "
                    . "and errors:\n$err");
        }
    }
    return $out;
}

#------------------------------------------------------------------------------
# startJob
#
#       Kick off the preflight build by calling runProcedure.  Save the job id
#       for future use.
#------------------------------------------------------------------------------

sub startJob()
{
    display("Launching the preflight build");
    my %args = (
        "procedureName"     => $::gProcedureName,
        "actualParameter"   => \@::gParameters
    );

    if (!defined($::gPriority) || $::gPriority eq "") {
        $::gPriority = "normal";
    }

    if ($::gPriority ne "normal") {
        $args{"priority"} = $::gPriority;
    }
    my ($error, $xpath) = invokeCommander("runProcedure",
            [$::gProjectName, \%args]);
    $::gJobId = $xpath->findvalue("jobId")->string_value;
    display("JOB ID: $::gJobId");
}

#------------------------------------------------------------------------------
# waitForJob
#
#       Invoked by the SCM driver script once it's done uploading deltas.
#       Returns the outcome of the job once it completes.
#------------------------------------------------------------------------------

sub waitForJob()
{
    if ($::gTesting) {
        display("Would wait for job");
        return;
    }
    display("Waiting for the job to complete");
    my ($error, $xpath) = invokeCommander("waitForJob",
            [$::gJobId, $::gJobTimeout],
            "NoSuchProperty");
    my $status = $xpath->findvalue("//status")->string_value;
    my $outcome = $xpath->findvalue("//outcome")->string_value;
    if ($status ne "completed") {
        error("The job did not complete in the given timeout ($::gJobTimeout "
                . "seconds)");
    }
    if ($outcome ne "success") {
        $::gJobId = undef;
        error("The job did not complete successfully");
    }
    display("The job completed successfully");
    $::gWaitedForJob = 1;
}

#------------------------------------------------------------------------------
# saveDataToFile
#
#       Writes the contents of a string to a file.
#------------------------------------------------------------------------------

sub saveDataToFile ($$) {
    my ($filename, $data) = @_;

    open(FILE, ">$filename") or error("Cannot open file \"$filename\": $!");
    binmode(FILE);
    print(FILE $data);
    close(FILE);
}

#------------------------------------------------------------------------------
# processOptions
#
#       Process the options passed to the command-line.  Parse the XML files
#       that are used to pass information and save all retrieved values in
#       global variables.
#------------------------------------------------------------------------------

sub doProcessOptions()
{
    # Parse command line arguments into global variables.

    Getopt::Long::Configure("pass_through");
    if (!GetOptions(%::gClientOptions))  {
        error($::gHelpMessage);
    }

    # Set the log file directory to the user's home directory if it wasn't
    # passed in.

    if (!defined($::gLogDir) || $::gLogDir eq "") {
        if (isWindows()) {
            $::gLogDir = $::ENV{USERPROFILE} . '/Local Settings/'
                    . 'Application Data/Electric Cloud/ElectricCommander/'
                    . ".$::gProgram";
            $::gLogDir =~ s/\\/\//g;
            $::gLogDir =~ s/\/\//\//g;
        } else {
            if (defined($::ENV{HOME}) && $::ENV{HOME}) {
                $::gLogDir = $::ENV{HOME} . "/.$::gProgram";
            } else {
                $::gLogDir = "/tmp/.$::gProgram";
            }
        }
    }
    mkpath($::gLogDir);

    # If the user chose to write out a log of all actions taken by the client
    # script, open the log file and print a time stamp.

    if ($::gLog) {
        my $logFile = "$::gLogDir/$::gProgram.log";
        open(LOG, ">>$logFile") or error("Cannot open file \"$logFile\": $!");
        binmode(LOG);
        print(LOG "---------------------------------------------\n");
        my ($sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst) =
                localtime(time);
        printf(LOG "$::gProgram invoked at %02d:%02d:%02d on %4d-%02d-%02d\n",
                $hour, $min, $sec, $year + 1900, $mon + 1, $mday);
    }

    # Collect the procedure invocation information.

    if (defined($::gOptions) && $::gOptions ne "") {
        extractOption(\$::gProjectName, "procedure/projectName", {
                required => 1,
                cltOption => "projectName"
            });
        extractOption(\$::gProcedureName, "procedure/procedureName", {
                required => 1,
                cltOption => "procedureName"
            });
        extractOption(\$::gPriority, "procedure/priority");
        if (!defined($::gPriority) || $::gPriority eq "") {
            $::gPriority = "normal";

        }

        extractOption(\$::gWaitForJob, "procedure/waitForJob", {
            required => 0
            });
        if (!defined($::gWaitForJob) || $::gWaitForJob eq "") {
            $::gWaitForJob = 0;
        }

        extractOption(\$::gJobTimeout, "procedure/jobTimeout");
        if (!defined($::gJobTimeout) || $::gJobTimeout eq "") {
            $::gJobTimeout = 3600;
        }

        extractOption(\$::gRunOnly, "procedure/runOnly");

        foreach my $parameter($::gOptions->findnodes(
                '/data/procedure/parameter')) {
            my $name = $parameter->findvalue("name")->string_value;
            my $value = $parameter->findvalue("value")->string_value;
            push @::gParameters, {
                    actualParameterName => $name,
                    value => $value
                };
            debug("Added parameter from config file: '$name' = '$value'");
        }
    } else {
        if (!defined($::gProjectName) || $::gProjectName eq "") {
            error("Required element \"projectName\" is empty or absent in the "
                    . "provided options.  May be passed on the command line "
                    . "using --projectName");
        }
        if (!defined($::gProcedureName) || $::gProcedureName eq "") {
            error("Required element \"procedureName\" is empty or absent in "
                    . "the provided options.  May be passed on the command "
                    . "line using --procedureName");
        }
    }

    foreach my $name (keys %::gExtraParameters) {
        my $value = $::gExtraParameters{$name};
        my $found = 0;
        foreach my $param (@::gParameters) {
            if (defined($param->{actualParameterName})
                    && $param->{actualParameterName} eq $name) {
                $param->{value} = $value;
                $found = 1;
                last;
            }
        }
        if (!$found) {
            push @::gParameters, {
                actualParameterName => $name,
                value => $value
            };
            debug("Added parameter from command-line: '$name' = '$value'");
        } else {
            debug("Overwrote parameter from command-line: '$name' = '$value'");
        }
    }
    if (!defined($::gRunOnly)) {
        $::gRunOnly = 0;
    }

    if (!$::gRunOnly) {
        if (defined($::gOptions) && $::gOptions ne "") {
            # SCM-specific information will be collected by the driver script.
            # Collect the general values here.

            extractOption(\$::gScm, "scm/type", {
                    required => 1,
                    cltOption => "scmType"
                });
            extractOption(\$::gAutoCommit, "scm/autoCommit");
            extractOption(\$::gCommitComment, "scm/commitComment");
        } else {
            if (!defined($::gScm) || $::gScm eq "") {
                error("Required element \"scmType\" is empty or absent in the "
                        . "provided options.  May be passed on the command "
                        . "line using --scmType");
            }
        }
    }
}

#------------------------------------------------------------------------------
# readFile
#
#       Read the contents of a file and return them.
#
# Arguments:
#       filename -          The name of the file.
#------------------------------------------------------------------------------

sub readFile($)
{
    my ($filename) = @_;
    open(FILE, "$filename") or error("Cannot open file \"$filename\": $!");
    my @fileContents = <FILE>;
    close(FILE);
    return join("", @fileContents);
}

#------------------------------------------------------------------------------
# isWindows
#
#       Returns true if we're running on Windows.
#------------------------------------------------------------------------------

sub isWindows() {
    return ($^O eq "MSWin32");
}

#------------------------------------------------------------------------------
# display
#
#       Prints a given message to stdout and the log.
#
# Arguments:
#       message -           The message to display.
#------------------------------------------------------------------------------

sub doDisplay($) {
    my ($message) = @_;
    chomp($message);
    $message =~ s/\.$//;
    $message = "$message.\n";
    if ($::gLog) {
        print(LOG $message);
    }
    print($message);
}

#------------------------------------------------------------------------------
# debug
#
#       Prints a given message to the log, and also to stdout if the
#       program was invoked in debug mode.
#
# Arguments:
#       message -           The message to display.
#------------------------------------------------------------------------------

sub doDebug($) {
    my ($message) = @_;
    chomp($message);
    $message =~ s/\.$//;
    $message = "    $message.\n";
    if ($::gLog) {
        print(LOG $message);
    }
    if ($::gDebug) {
        print($message);
    }
}

#------------------------------------------------------------------------------
# error
#
#       Prints a given error message to the log and stderr, and exits
#       the program.
#
# Arguments:
#       message -           The message to display.
#------------------------------------------------------------------------------

sub doError($) {
    my ($message) = @_;
    chomp($message);
    $message =~ s/\.$//;
    $message = "ERROR: $message.\n";
    if ($::gLog) {
        print(LOG $message);
    }
    print(STDERR $message);
    exitHandler();
}

#------------------------------------------------------------------------------
# warning
#
#       Prints a given error message to the log and stderr, and exits
#       the program.
#
# Arguments:
#       message -           The message to display.
#------------------------------------------------------------------------------

sub warning($) {
    my ($message) = @_;
    chomp($message);
    $message =~ s/\.$//;
    $message = "WARNING: $message.\n";
    if ($::gLog) {
        print(LOG $message);
    }
    print($message);
}

#------------------------------------------------------------------------------
# prompt
#
#       Prompts the user and returns their response.
#------------------------------------------------------------------------------

sub prompt() {
    my $response = <STDIN>;
    chomp $response;
    return $response;
}

#------------------------------------------------------------------------------
# checkWaitForStep
#
#       Checks if the "waitForStep" property has been set on the procedure
#       so that the driver script knows if it should upload deltas immediately
#       after starting the job, or wait until it receives the snapshot location
#       and overlay the deltas directly.
#------------------------------------------------------------------------------

sub checkWaitForStep()
{
    debug("Checking for the waitForStep property on the procedure");
    my ($error, $xpath) = invokeCommander("getProperty",
            ["/projects[$::gProjectName]/procedures[$::gProcedureName]/"
            . "ec_preflight/waitForStep"], "NoSuchProperty");
    if (!$error) {
        my $waitForStep = $xpath->findvalue("property/value")->string_value;
        if ($waitForStep) {
            debug("The waitForStep property was found and is set to true");
            $::gWaitForStep = 1;
        } else {
            debug("The waitForStep property was found but is set to false");
        }
        return;
    }
    debug("The waitForStep property was not found");
}

#------------------------------------------------------------------------------
# saveScmInfo
#
#       Save the given data to a file called ecpreflight_scmInfo, and then add
#       it to the files to be uploaded.
#
# Arguments:
#       data -              SCM information to write to the file.
#------------------------------------------------------------------------------

sub saveScmInfo($)
{
    my ($data) = @_;

    # Create a file with specific SCM information needed on the agent-side
    # to create the source snapshot.

    my $infoFile = "$::gLogDir/ecpreflight_scmInfo";
    saveDataToFile($infoFile, $data);
    debug("Adding SCM info file \"$infoFile\" to copy to "
            . "ecpreflight_data/scmInfo");
    $::gFilesToUpload{$infoFile} = "ecpreflight_data/scmInfo";
}

#------------------------------------------------------------------------------
# findTargetDirectory
#
#       If the preflight is set to wait for the step to complete, then upload
#       a "signal" file, ecpreflight_needTarget, and then wait for the step
#       to return a target directory to which to copy the sources directly.
#------------------------------------------------------------------------------

sub findTargetDirectory()
{
    # If the job's workspace is marked as available on a network share, then
    # start the job immediately, wait for the preflight step to write out its
    # workspace information via putFiles, and then use that as the root for
    # copying deltas.

    if ($::gWaitForStep) {
        if (!$::gTesting) {
            # Kick off the preflight build now since we need the workspace
            # information from the preflight step before we can overlay the
            # sources directly.

            startJob();
        }

        # Invoke putFiles right away with a special file "needTarget" which
        # signals to the step that it needs to pass back its workspace info.

        my $signalFile = "$::gLogDir/ecpreflight_needTarget";
        saveDataToFile($signalFile, "");
        $::gFilesToUpload{$signalFile} = "ecpreflight_data/needTarget";
        if (!$::gTesting) {
            invokeCommander("putFiles", [$::gJobId, \%::gFilesToUpload]);

            # Call getFiles immediately, expecting the workspace information
            # to be uploaded by the step.

            invokeCommander("getFiles", [{
                    "jobId" => $::gJobId,
                    "channel" => "workspace",
                    "baseDir" => $::gLogDir}]);
        }

        # Read the workspace information and select the appropriate entry
        # based on the client's OS.

        my $wsInfo = readFile("$::gLogDir/ecpreflight_targetInfo");
        $wsInfo =~ m/(.*)\n(.*)\n/;
        $::gTargetDirectory = isWindows() ? $1 : $2;
    }
}

#------------------------------------------------------------------------------
# createManifestFiles
#
#       Create a couple of files: ecpreflight_deletes and ecpreflight_deltas
#       which will be used to store a lists of deletes and deltas for the
#       agent script to overlay on top of the source tree.
#------------------------------------------------------------------------------

sub createManifestFiles()
{
    # Create a file used to collect all files which need to be deleted from
    # the source snapshot.

    my $deleteFileName = "$::gLogDir/ecpreflight_deletes";
    open(DELETES, ">$deleteFileName") or error("Couldn't create a delete "
            . "manifest file: $!");
    binmode(DELETES);

    # Create a file which will contain a list of delta files for the agent to
    # retrieve and copy over the source snapshot.

    my $deltasFileName = "$::gLogDir/ecpreflight_deltas";
    open(DELTAS, ">$deltasFileName") or error("Couldn't create a delta "
            . "manifest file: $!");
    binmode(DELTAS);

    # Create a file which will contain a list of directories for the agent to
    # create in the source tree.

    my $directoriesFileName = "$::gLogDir/ecpreflight_directories";
    open(DIRECTORIES, ">$directoriesFileName") or error("Couldn't create a "
            . "directory manifest file: $!");
    binmode(DIRECTORIES);
}

#------------------------------------------------------------------------------
# closeManifestFiles
#
#       Close the deltas and deletes manifest files created earlier, and add
#       them to the list of files to be uploaded to the agent.
#------------------------------------------------------------------------------

sub closeManifestFiles()
{
    # Add the deletes manifest to the putFiles operation.

    close(DELETES);
    debug("Adding deletes file \"$::gLogDir/ecpreflight_deletes\" "
            . "to copy to ecpreflight_data/deletes");
    $::gFilesToUpload{"$::gLogDir/ecpreflight_deletes"}
            = "ecpreflight_data/deletes";

    # Add the deltas manifest to the putFiles operation.

    close(DELTAS);
    debug("Adding deltas file \"$::gLogDir/ecpreflight_deltas\" "
            . "to copy to ecpreflight_data/deltas");
    $::gFilesToUpload{"$::gLogDir/ecpreflight_deltas"}
            = "ecpreflight_data/deltas";

    # Add the directories manifest to the putFiles operation.

    close(DIRECTORIES);
    debug("Adding directories file "
            . "\"$::gLogDir/ecpreflight_directories\" "
            . "to copy to ecpreflight_data/directories");
    $::gFilesToUpload{"$::gLogDir/ecpreflight_directories"}
            = "ecpreflight_data/directories";
}

#------------------------------------------------------------------------------
# addDelta
#
#       Depending on whether a target directory has been defined or not, either
#       copy the file straight there or add it to the list of files to be
#       uploaded to the agent.
#
# Arguments:
#       source -            The source file.
#       dest -              The destination path, relative to the source tree.
#------------------------------------------------------------------------------

sub addDelta($$)
{
    my ($source, $dest) = @_;
    $::gFilesToCommit{$source} = 1;
    if (defined($::gTargetDirectory) && $::gTargetDirectory ne "") {
        # Copy the file directly to the network share.

        debug("Copying \"$source\" to \"$::gTargetDirectory/$dest\"");
        mkpath(dirname("$::gTargetDirectory/$dest"));
        unlink("$::gTargetDirectory/$dest");
        copy($source, "$::gTargetDirectory/$dest");
    } else {
        # Add the file to the putFiles call.

        debug("Adding \"$source\" to copy to "
                . "\"ecpreflight_files/$dest\"");
        $::gFilesToUpload{$source} = "ecpreflight_files/$dest";
    }
    display("    Copying \"$dest\"");
    print(DELTAS "$dest\n");

    # Save the latest timestamp for comparison purposes before auto-
    # commiting (so any changes to the files can be detected).

    my $timestamp = stat($source);
    if (defined($timestamp) && $timestamp->mtime > $::gLatestTimestamp) {
        $::gLatestTimestamp = $timestamp->mtime;
    }
}

#------------------------------------------------------------------------------
# addDelete
#
#       Add a file to the delete manifest so the agent script deletes it after
#       creating the snapshot.
#
# Arguments:
#       dest -              The destination path, relative to the source tree.
#------------------------------------------------------------------------------

sub addDelete($)
{
    my ($dest) = @_;
    display("    Deleting \"$dest\"");
    print(DELETES "$dest\n");
}

#------------------------------------------------------------------------------
# addDirectory
#
#       Depending on whether a target directory has been defined or not, either
#       create the directory straight there or add it to a list of directories
#       uploaded to the agent
#
# Arguments:
#       dest -              The destination directory, relative to the source
#                           tree.
#------------------------------------------------------------------------------

sub addDirectory($)
{
    my ($dest) = @_;
    display("    Adding directory \"$dest\"");
    print(DIRECTORIES "$dest\n");
}

#------------------------------------------------------------------------------
# uploadFiles
#
#       Start the job if we haven't already, and upload the collected data
#       and deltas to the agent via putFiles.
#------------------------------------------------------------------------------

sub uploadFiles()
{
    if (!$::gTesting) {
        if (!$::gWaitForStep) {
            # Kick off the preflight build.

            startJob();
        }

        # Call putFiles with all of the collected files and information.

        display("Uploading new and modified files");
        invokeCommander("putFiles", [$::gJobId, \%::gFilesToUpload]);
    }
}

#------------------------------------------------------------------------------
# checkTimestamps
#
#       Compare the timestamps of all deltas with the latest timestamp stored
#       before uploading them, and error out if any files have been modified
#       since the preflight was started.
#------------------------------------------------------------------------------

sub checkTimestamps()
{
    foreach my $fileName (keys %::gFilesToCommit) {
        my $timestamp = stat($fileName);
        if (defined($timestamp) && $timestamp->mtime > $::gLatestTimestamp) {
            error("Changes have been made to \"$fileName\" since the "
                    . "preflight build was launched");
        }
    }
}

#------------------------------------------------------------------------------
# exitHandler
#
#       Invoked when the program is killed or exits.  The preflight job is
#       aborted if it was started.
#------------------------------------------------------------------------------

sub doExitHandler()
{
    if ($::gLog) {
        close(LOG);
    }
}

#------------------------------------------------------------------------------
# clientMain
#
#       Main program for the application.
#------------------------------------------------------------------------------

sub clientMain()
{
    if (getSCMMode() eq "new") {
        debug("Running scm plugin version");
        newStyleDriver();
    } else {
        debug("Running legacy plugin version");
        oldStyleDriver();
    }
}

#------------------------------------------------------------------------------
# getNewStylePlugin
#
#       get plugin name based on options passed in
#------------------------------------------------------------------------------
sub getNewStylePlugin
{
    my $opts = shift;

    my $scmType = $opts->{scm_type};

    if (defined $scmType) {
        # if actual plugin name specified, use it
        if ("$scmType" =~ /^ECSCM/) { return "$scmType"; }

        # otherwise map legacy names to new drivers
        if ("$scmType" eq "Perforce") { return "ECSCM-Perforce"; }
        if ("$scmType" eq "perforce") { return "ECSCM-Perforce"; }
        if ("$scmType" eq "Accurev") { return "ECSCM-Accurev"; }
        if ("$scmType" eq "accurev") { return "ECSCM-Accurev"; }
        if ("$scmType" eq "Clearcase") { return "ECSCM-ClearCase"; }
        if ("$scmType" eq "clearcase") { return "ECSCM-ClearCase"; }
        if ("$scmType" eq "Subversion") { return "ECSCM-SVN"; }
        if ("$scmType" eq "subversion") { return "ECSCM-SVN"; }
    } else {
        $scmType = "";
    }
    error("Unknown scmType $scmType");
}

#################################################################
# getNewStyleOptions
#
# Legacy driver architecture expects to extract values on the fly
# (using extractOptions). The legacy method used global vars to pass
# information around.
# The ECSCM drivers, however, need all options passed in one hash
#
# So, we call the legacy processOptions and then store all the
# options in  $opts
#
# Legacy options used keywords of the form  area/value
# But we need the keys to be valide barewords and / is not allowd,
# so we convert slashs to underscore (area_value)
#
# Options hash is passed in and may have existing values
# Changes to $opts->{xxx}  persist after the call
#################################################################
sub getNewStyleOptions
{
    my ($opts) = @_;

    debug("In getNewStyleOptions");

    doProcessOptions();

    # take all variables from globals and put in
    # one hash so ECSCM driver has options in one place
    if (defined $::gOptions)  {
        foreach my $node ($::gOptions->findnodes("//scm/*")) {
            my $name = $node->getName();
            my $value = $node->string_value;
            my $keyname = "scm_$name";
            # if the same option is given twice, add to the existing
            # option with | separator
            if (defined $opts->{$keyname} && $opts->{$keyname} ne "") {
                $opts->{$keyname} .= "|";
            }
            $opts->{"$keyname"} .= "$value";
            debug("Auto setting $keyname=$value");
        }
    }

    # now add named global variables. This may
    # overwrite values stored from gOptions above, but
    # is consistent with how ecclientpreflight prioritizes
    # values. The list of globals comes from ecclientpreflight code

    $opts->{server_hostName}           = $::gServer;
    $opts->{server_port}               = $::gPort;
    $opts->{server_securePort}         = $::gSecurePort;
    $opts->{server_secure}             = $::gSecure;
    $opts->{server_timeout}            = $::gTimeout;
    $opts->{server_userName}           = $::gUserName;
    $opts->{server_password}           = $::gPassword;
    $opts->{server_driverLocation}     = $::gDriverLocation;
    $opts->{server_mainDriver}         = $::gMainDriver;
    $opts->{procedure_projectName}     = $::gProjectName;
    $opts->{procedure_procedureName}   = $::gProcedureName;
    $opts->{procedure_priority}        = $::gPriority;
    $opts->{procedure_waitForJob}      = $::gWaitForJob;
    $opts->{procedure_jobTimeout}      = $::gJobTimeout;
    $opts->{procedure_runOnly}         = $::gRunOnly;
    @{$opts->{procedure_parameters}}   = @::gParameters;
    $opts->{scm_type}                  = $::gScm;
    $opts->{scm_autoCommit}            = $::gAutoCommit;
    $opts->{scm_commitComment}         = $::gCommitComment;
    $opts->{opt_Log}                   = $::gLog;
    $opts->{opt_LogDir}                = $::gLogDir;
    $opts->{opt_Program}               = $::gProgram;
    $opts->{opt_Testing}               = $::gTesting;

    foreach my $k (sort keys %$opts) {
        if (defined $opts->{$k}) {
            debug("    opts->{$k}=" . $opts->{$k} );
        } else {
            debug("    opts->{$k}=undef" );
        }
    }
}

#------------------------------------------------------------------------------
# newStyleDriver
#
#       get drivers the new way (from ECSCM plugins)
#
#   Most of the functions in this file have been moved
#   into the ECSCM::Base::Driver package. The versions in this
#   file are only for oldsytyle scm drivers. However the
#   option processing in this file IS used.
#
#   When we quit supporting the old style drivers
#   most of this file will be obsolete.
#------------------------------------------------------------------------------
sub newStyleDriver()
{
    my $opts = {};
    my $result;

    # load all options in one hash
    getNewStyleOptions($opts);

    # load helpers (availe Commander 3.6 and beyond)
    require ElectricCommander::PropMod;
    require ElectricCommander::PropDB;

    # dynamically load the ECSCM base class
    my $proj_prop = "/plugins/ECSCM/projectName";
    my $proj = $::gCommander->getProperty("$proj_prop")->findvalue('//value')->string_value;
    if (!defined $proj || "$proj" eq "" ) {
        print "Could not find promoted ECSCM plugin\n";
        exit 1;
    }

    ## find ECSCM plugin project
    my $prop = "/projects/$proj/scm_driver/ECSCM::Base::Driver";
    debug("Loading base driver from $prop");
    if (!ElectricCommander::PropMod::loadPerlCodeFromProperty($::gCommander,"$prop") ) {
        print "Could not load ECSCM base driver.\n";
        exit 1;
    }
    $prop = "/projects/$proj/scm_driver/ECSCM::Base::Cfg";
    if (!ElectricCommander::PropMod::loadPerlCodeFromProperty($::gCommander,"$prop") ) {
        print "Could not load ECSCM cfg driver.\n";
        exit 1;
    }

    ## use routines in bootstrap to load an SCM driver
    my $ecscm = new ECSCM::Base::Driver($::gCommander,"-none-");
    if (!defined $ecscm) {
        # failures should be verbose, no need to pile on
        error("");
    }

    # Load policy values
    # Looks in /plugins/ECSCM/policies/preflight/...."
    my $propDBTable = "/projects/$proj/policies";
    debug("Loading policies $propDBTable");
    $opts->{opt_DieOnNewCheckins}      = "0";
    $opts->{opt_DieOnWorkspaceChanges} = "0";
    $opts->{opt_DieOnFileChanges}      = "0";
    my $dbobj = ElectricCommander::PropDB->new($::gCommander,$propDBTable );
    if (defined $dbobj) {
        $opts->{opt_DieOnNewCheckins}      = $dbobj->getCol("preflight", "DieOnNewCheckins") || "0" ;
        $opts->{opt_DieOnWorkspaceChanges} = $dbobj->getCol("preflight", "DieOnWorkspaceChanges") || "0" ;
        $opts->{opt_DieOnFileChanges}      = $dbobj->getCol("preflight", "DieOnFileChanges") || "0" ;
    }
    debug( "policy DieOnNewCheckins=$opts->{opt_DieOnNewCheckins}" );
    debug( "policy DieOnWorkspaceChanges=$opts->{opt_DieOnWorkspaceChanges}" );
    debug( "policy DieOnFileChanges=$opts->{opt_DieOnFileChanges}" );

    if ($opts->{procedure_runOnly}) {
        debug("Run only starting job");
        $ecscm->cpf_startJob($opts);
    } else {
        my $pluginName = getNewStylePlugin($opts);

        debug("Loading driver $pluginName");
        my $scmName = $ecscm->load_driver("$pluginName");
        if (!defined $scmName) {
            error("Could not load $pluginName");
        }
        debug("SCM NAME=$scmName");
        my $scm = new $scmName($::gCommander, "");
        if (!defined $scm) {
            error($::gHelpMessage);
        }

        # Check for a pre-defined network share location.
        $scm->cpf_checkWaitForStep($opts);

        ## run client preflight for this driver
        $scm->cpf_driver($opts);
        debug("Client Driver completed.");
    }
    # If the user asked to wait for a job and the job hasn't already been
    # waited for in the driver script, wait for it here.

    if ($opts->{procedure_waitForJob} && ! $opts->{rt_WaitedForJob}
          && defined($opts->{rt_jobId} )) {
        $ecscm->cpf_waitForJob($opts);
    }

    if ($opts->{opt_Log}) {
        close(LOG);
    }
}


#------------------------------------------------------------------------------
# oldStyleDriver
#
#       get drivers the old way (just from properties)
#------------------------------------------------------------------------------
sub oldStyleDriver()
{
    # Process the command-line options.
    processOptions();

    # Check for a pre-defined network share location.
    checkWaitForStep();

    if ($::gRunOnly) {
        startJob();
    } else {
        # Retrieve the rest of the script from a well known property and eval
        my $driverLocation = "$::gDriverLocation/clientDrivers/$::gScm";
        debug("Retrieving the SCM driver script from \"$driverLocation\"");

        my ($error, $xpath) = invokeCommander("getProperty",
                [$driverLocation], "NoSuchProperty");
        if ($error) {
            error("SCM driver script not found in property "
                    . "\"$driverLocation\"");
        }
        my $driver = $xpath->findvalue("property/value")->string_value;
        debug("Found the driver script");
        eval $driver;
        if ($@) {
            error("Errors occurred when executing the driver: $@");
        }
    }

    # If the user asked to wait for a job and the job hasn't already been
    # waited for in the driver script, wait for it here.

    if ($::gWaitForJob && !$::gWaitedForJob && defined($::gJobId)) {
        waitForJob();
    }

    if ($::gLog) {
        close(LOG);
    }
}

#------------------------------------------------------------------------------
# getSCMMode
#
#       find out if server is in legacy mode (v3.5 and earlier)
#       or new mode
#------------------------------------------------------------------------------
sub getSCMMode {
    my $property = "/server/ec_preflight/scm_mode";
    my ($error, $xpath) = invokeCommander("getProperty",
            ["$property"], "NoSuchProperty");
    if ($error) {
        error("SCM mode not found in property "
                . "\"$property\"");
    }
    my $mode = $xpath->findvalue("property/value")->string_value;
    return $mode;
}


# Run the driver script, unless the script is being tested.

if (defined($ENV{ECPREFLIGHT_TEST}) && $ENV{ECPREFLIGHT_TEST} ne "") {
    $::gTesting = 1;
} else {
    clientMain();
}

