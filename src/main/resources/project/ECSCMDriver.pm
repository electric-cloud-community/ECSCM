###################################################################
#
# ECSCM::Base::Driver Object to represent interactions with an SCM system
#        This is a base clase. Actual SCM's will derive from this
#        base class.
#
####################################################################
package ECSCM::Base::Driver;
use ElectricCommander;
use ElectricCommander::PropMod;
use Cwd;
use File::Basename;
use File::Path;
use File::Copy;
use File::Find;
use File::Spec;
use File::stat;
use File::Temp;
use IO::File;
use Time::Local;
use HTML::Entities ();
use utf8;

# code in begin section is equivalent to next code.
# this fix created ONLY for ecclientpreflight.exe, which was packed by PAR
# and without open pragma as dependency. My BEGIN code loading open pragma ONLY
# if that's possible
# use open ":utf8";
# use open IO => ":utf8";
BEGIN {
    eval {
        require "open.pm";
        1;
    } and do {
        open::import('open', ":encoding(UTF-8)");
        open::import('open', IO => ":encoding(UTF-8)");
    }
}



if (!defined ECSCM::Base::Cfg) {
    require ECSCM::Base::Cfg;
}

####################################################################
# Object constructor for ECSCM::Base::Driver
#
# Inputs
#    cmdr     previously initialized ElectricCommander handle
#    cfg      an object derived from ECSCM::Base::Cfg
####################################################################
sub new {
    my $class = shift;

    my $self = {
        _cmdr => shift,
        _cfg  => shift,
    };

    bless ($self, $class);

    # if not passed an explicit config, use the base class cfg
    if (!defined $self->{_cfg} || "$self->{_cfg}" eq "") {
        $self->{_cfg} = new ECSCM::Base::Cfg($self->{_cmdr});
    }
    return $self;
}

####################################################################
# getCfg
#
# return the cfg object
####################################################################
sub getCfg {
    my ($self) = @_;
    return $self->{_cfg};
}

####################################################################
# getCmdr
#
# return the cmdr object
####################################################################
sub getCmdr {
    my ($self) = @_;
    return $self->{_cmdr};
}


##########################################################################
# Helper functions that do common tasks most drivers will need
##########################################################################

#-------------------------------------------------------------------------
#  retrieveUserCredential
#
#   Retrieve the user & password from the credential
#   The credential is used to identify a user to the SCM system
#
#   Params:
#       credentialName
#       userName
#       password
#
#   Returns:
#       A list containing the updated userName and password
#
#-------------------------------------------------------------------------
sub retrieveUserCredential {

    # Load the starting values for the fields
    my $self = shift;
    my $scmUserCredential = shift;
    my $userName = shift;
    my $password = shift;

    # Load the credential info if defined
    if ( defined $scmUserCredential && $scmUserCredential ne "") {
        $self->debug("Attempting to get user/password from credential $scmUserCredential");
        my ($success, $xPath,$msg) =
                $self->InvokeCommander({SuppressLog=>1, IgnoreError=>1} ,
                    "getFullCredential", "$scmUserCredential");
        if ($success) {
            $userName = $xPath->findvalue('//userName');
            $password = $xPath->findvalue('//password');
        } else {
            my $errMsg = $self->getCmdr()->checkAllErrors($xPath);
            print "Credential error:$errMsg\n";
        }
    }
    return ($userName, $password);
}

#-------------------------------------------------------------------------
#  issueWarningMsg
#
#   Print a warning message and set a warning outcome
#   This is designed to work with or without postp
#
#   Parameters:
#       msgText     -   Optional text to display
#                       This function will add a generic warning line
#                       that can trigger postp
#
#   Returns:
#       none
#
#-------------------------------------------------------------------------
sub issueWarningMsg {

    my $self = shift;
    my $warningMsgText = shift;
    print "$warningMsgText\n" if ($warningMsgText);
    if (defined $ENV{COMMANDER_JOBSTEPID} && $ENV{COMMANDER_JOBSTEPID} ne "") {
        $self->InvokeCommander({SuppressLog=>1}, "setProperty", "outcome", "warning",
                    {"jobStepId" => $ENV{COMMANDER_JOBSTEPID}} );
    }
}

#-------------------------------------------------------------------------
#  PrintEnv - print the environment
#-------------------------------------------------------------------------
sub PrintEnv {

    my $self = shift;
    my $key;
    foreach $key (sort keys %ENV)
    {
        print "env: $key  =  $ENV{$key}\n";
    }
}

#-------------------------------------------------------------------------
#  get test mode (memory only)
#-------------------------------------------------------------------------
sub isTestMode {
    my $self = shift;
    return $self->{testmode};
}

#-------------------------------------------------------------------------
#  set test mode (memory only)
#-------------------------------------------------------------------------
sub setTestMode {
    my $self = shift;
    my $flag = shift;
    my $oldflag = $self->{testmode};
    $self->{testmode} = $flag;
    return $oldflag;
}

#------------------------------------------------------------------------------
# error
#
#       Print an error message.
#
# Arguments:
#       message -           The message to display.
#------------------------------------------------------------------------------
sub error($)
{
    my ($self, $message) = @_;

    if (ref $self && $self->can('cleanupHandler')) {
        $self->cleanupHandler('error');
    }

    if ($self->isTestMode()) {
        print(STDERR $message);
        exit 1;
    } else {
        print(STDERR $message);
        exitHandler();
        exit 1;
    }
}


#------------------------------------------------------------------------------
# exitHandler
#
#       Invoked when the program is killed.  Cleans up the clearcase view if
#       it was created.
#------------------------------------------------------------------------------
$SIG{INT} = \&exitHandler;
$SIG{QUIT} = \&exitHandler;
$SIG{TERM} = \&exitHandler;
sub exitHandler()
{
    if (defined &exitDriver) {
        exitDriver();
        return;
    }
}
#-------------------------------------------------------------------------
#  Log and Run a command using the shell and save and report its results
#  Params
#       commandLine     -   command to be run
#       options         -   a hash of optional params
#           IgnoreError
#           LogCommand
#           SuppressResult
#           HidePassword
#           passwordStart
#           passwordLength
#           IgnoreError       optional parameter - if present and non-zero, don't die
#
#   NOTE:
#
#  We have discovered a weird interaction between PERL and Perforce.
#  PERL typically (often/always??) sets an environment variable PWD,
#  nominally set to the current directory.  The P4 command line is
#  sensitive to this variable, and prefers it to the actual current
#  directory.  The problem is that when PERL executes "use FindBin;",
#  it apparently damages PWD and leaves it set to the directory that
#  the current script is running from.
#
#  There are a couple of workarounds to this problem.  We thought about
#  adding them to this function (just in case it was calling P4), but
#  decided to hold off implementing them because of potential for causing
#  other problems.
#    1.  In PERL, call "getcwd()".  This seems to restore the value of PWD.
#    2.  undef $ENV{PWD}  Who really wants this thing anyway?
#    3.  when calling P4, add "-d directory".  This overrides the PWD setting.
#
#  Looks at the environment variable ECSCM_SIMULATE_RUNCOMMAND.  If true,
#  it calls a test function instead of running a command in the shell.
#-------------------------------------------------------------------------
sub RunCommand {

    my ($self, $commandLine, $options) = @_;

    my $bLogCommand     = "$options->{LogCommand}";
    my $bLogResult      = "$options->{LogResult}";
    my $bIgnoreError    = "$options->{IgnoreError}";
    my $bDieOnError     = "$options->{DieOnError}";
    my $bHidePassword   = "$options->{HidePassword}";
    my $input           = "$options->{input}";
    my $replacements    = $options->{Replacements};

    # Redirect errors according to the "dieOnError" option.

    # check for options to suppress the password
    my $printableCommandLine = $commandLine;
    my $passwordStart = 0;
    my $passwordLength = 0;
    if ($bHidePassword && defined $options->{passwordStart} &&
                          defined $options->{passwordLength} &&
                          $options->{passwordLength} > 0) {

        $passwordStart  = $options->{passwordStart};
        $passwordLength = $options->{passwordLength};
        substr $printableCommandLine, $passwordStart, $passwordLength,
                    "****";
    }

    if ($bLogCommand) {
        my $logLine = "Log Command: $printableCommandLine\n";
        print $self->makeReplacements($logLine, $replacements);

        # Print the length of the password for testing mode.  It shows that it
        #   was correctly retrieved, without revealing it
        if ($ENV{ECSCM_SIMULATE_RUNCOMMAND}  &&  ($passwordLength > 0) ) {
            print "Log Password - Length = $passwordLength\n";
        }
    }

    # Redirect errors according to the "dieOnError" option.
    my $errorFile;
    if ($bDieOnError) {
        $errorFile = File::Spec->tmpdir . "/_err" . $ENV{COMMANDER_JOBSTEPID};
        $commandLine .= " 2>\"$errorFile\"";
    } else {
        $commandLine .= " 2>&1";
    }

    $self->cpf_debug("running command["
        . $self->makeReplacements($commandLine, $replacements)
        . "] die[$bDieOnError]");

    # If standard input is provided, open a pipe to the command and print
    # the input to the pipe.  Otherwise, just run the command.

    my $commandResult;

    if ($ENV{ECSCM_SIMULATE_RUNCOMMAND}) {
        $commandResult =  $self->SimulateRunCommand($commandLine);
    } elsif (defined($input) && length($input) > 0) {
        my (undef, $outputName) =
                File::Temp::tempfile("ecout_XXXXXX", OPEN => 0,
                DIR => File::Spec->tmpdir);
        open(PIPE, "|-", "$commandLine >\"$outputName\"")
                 or $self->error("Cannot open pipe to \"$outputName\": $!");
        print(PIPE $input);
        close(PIPE);
        open(FILE, $outputName)
                or $self->error("Cannot open file \"$outputName\": $!");
        my @fileContents = <FILE>;
        $commandResult = join("", @fileContents);
        close(FILE);
        unlink($outputName);
    } else {
        $commandResult = `$commandLine`;
    }

    # process return
    if ($? && !$bIgnoreError) {
        my $exit = $? >> 8;
        if ($bDieOnError) {
            my $err = "";
            open(ERR, $errorFile) or $self->error("Cannot open file \"$errorFile\": $!");
            my @contents = <ERR>;
            $err = join("", @contents);
            close(ERR);
            unlink($errorFile);
            if ($exit != 0 || $err ne "") {
                $self->error("Command \""
                    . $self->makeReplacements($commandLine,$replacements)
                    . "\" failed with exit code $exit and errors:\n$err");
            }
        } else {
            warn "Error: Return ($exit) from RunCommand.";
            if (defined $commandResult) {
                print $self->makeReplacements($commandResult,$replacements) . "\n";
            }
            return undef;
        }
    }

    # Log the result
    if ($bLogResult) {
        my $printableResult = $commandResult;
        chomp($printableResult);
        $printableResult =~ s/\n/\n           : /g unless ($bCleanLog);
        print " Log Result: " . $self->makeReplacements($printableResult,$replacements)
            . "\n" unless ($bSuppressResult);
    }

    # Return the result
    return $commandResult;
}


#-------------------------------------------------------------------------
#  SimulateRunCommand - Simulate running a shell command during internal testing
#
#-------------------------------------------------------------------------
sub SimulateRunCommand($) {

    my ($self, $commandLine) = @_;

    # Print the environment so that special settings can be tested
    if ($ENV{ECSCM_SHOWENV}) {
        $self->PrintEnv();
    }

    #  Get the pre-packaged response
    my ($success, $xPath) = $self->InvokeCommander({SuppressLog=>1, IgnoreError=>1},
                                                   "logMessage", $commandLine);
    return "" unless defined $xPath;
    my $retValue = $xPath->findvalue('//commandOutput')->value();
    $retValue = "" unless defined $retValue;

    return $retValue;
}


#-------------------------------------------------------------------------
#  Run an ElectricCommander function using the Perl API
#
#  Params
#       optionFlags - hash of options flags. "AllowLog" or "SuppressLog" or "SuppressResult"
#                     combined with "IgnoreError"
#                          IgnoreError = undef  Set (abort on error = 1)
#                          IgnoreError = 1      Ignore all errors  (abort on error=0)
#                          IgnoreError = text   Ignore the erorr "text"  (abort on error=0)
#       commanderFunction
#       Variable Parameters
#           The parameters required by the Commander function according to the Perl API
#               (the functions and paramenter are based on "ectool" - run it for documentation)
#
#  Returns
#       success     - 1 if no error was detected
#       xPath       - an XML::XPath object with the result.
#       errMsg      - a message string extracted from Commander on error
#
#-------------------------------------------------------------------------
sub InvokeCommander {
    my $self = shift;
    my $opts = shift;
    my $commanderFunction = shift;
    my $xPath;
    my $success = 1;

    my $bSuppressLog    = $opts->{SuppressLog};
    my $bSuppressResult = $opts->{SuppressResult};
    my $IgnoreError     = $opts->{IgnoreError};
    $bSuppressResult = $bSuppressLog || $bSuppressResult;

    ###########################
    ###$bSuppressLog = $bSuppressResult = 0;
    ###########################



    #  Run the command
    $self->debug("Invoking function $commanderFunction");

    my $oldAbort = $self->getCmdr()->{abortOnError};

    if ($IgnoreError) {
        $self->getCmdr()->abortOnError(0);
    } else {
        $self->getCmdr()->abortOnError(1);
    }

    # Log the request before running
    print "Request to Commander: $commanderFunction\n" unless ($bSuppressLog);

    $xPath = $self->getCmdr()->$commanderFunction(@_);
    $self->getCmdr()->abortOnError($oldAbort);
    $self->debug("function completed");


    # Check for error return
    my $errMsg = $self->getCmdr()->getError();
    if (defined($errMsg) && $errMsg ne "") {
        # it failed, so return 0
        # now decide if we should say something
        $success = 0;
        if (!defined($IgnoreError) || $IgnoreError eq "" ||
            ($IgnoreError ne "1" && index($errMsg, $IgnoreError) >= 0)) {

            my $xmlString = $xPath->findnodes_as_string("/");
            # Remove passwords before printing
            $xmlString =~ s/<password>.*?<\/password>/<password>\*\*\*\*<\/password>/g;
            print "Return data from Commander:\n$xmlString\n";
        }
    }


    # Log the result if it is not suppressed
    if ($xPath && ! $bSuppressResult) {

        my $xmlString = $xPath->findnodes_as_string("/");

        # Remove passwords before printing
        $xmlString =~ s/<password>.*?<\/password>/<password>\*\*\*\*<\/password>/g;

        print "Return data from Commander:\n$xmlString\n";
    }

    if ($functionName =~ m/(putFile|getFile)/) {
        # A special API has been invoked, and XPath element is returned.
        # If it was called, nothing is returned.  The sender is deleted as a
        # workaround for some cleanup issues.  TODO: replace this with the
        # disconnect/shutdown call when it's implemented.
        delete $self->getCmdr()->{sender};
    }

    # Return the result
    return ($success, $xPath, $errMsg);
}


###############################################################################
# extractOption
#
#       Invoked when processing options to extract the value of a variable from
#       either the arguments file or an environment variable.  May error out
#       if the value is required but not found.  The value is stored back in
#       the variable; nothing is returned.
#
# Arguments:
#       opts -              A reference to the hash with values
#       element -           The name of the element to extract opts
#       properties -        (Optional) A hash of supported properties:
#       * env -             The name of an environment variable to check
#                           for the value if it isn't in opts.
#                           The value is stored in the environment variable
#                           once it's found.  Undefined by default.
#       * required -        Whether or not the element is required.  If it is
#                           and no value is found, an error will be thrown,
#                           0 by default.
###############################################################################
sub extractOption($$;$)
{
    my ($self, $opts, $element, $properties) = @_;


    $self->debug("extracting $element from options");
    my $errorMsg = "Required element \"$element\" is empty or absent in "
            . "the provided options";

    my $envVar = undef;
    if (defined($properties->{env})) {
        $envVar = $properties->{env};
        $errorMsg .= " and the environment variable \"$envVar\"";
    }
    my $required = 0;
    if (defined($properties->{required})) {
        $required = $properties->{required};
    }
    my $value = undef;
    if (defined($opts->{$element}) && $opts->{$element} ne "") {
        $value = $opts->{$element};
    }
    if ("$value" eq "") {
        if (defined($envVar) && defined($ENV{$envVar}) && $ENV{$envVar} ne "") {
            $self->debug("getting value from environment");
            $value = $ENV{$envVar};
        } elsif ($required) {
            print "Error: Could not find required option $element. Aborting.\n";
            exit 1;
        } else {
            $self->debug("value is empty");
            $value = undef;
        }
    }
    if (defined($envVar) && defined($value)) {
        $self->debug("setting env variable");
        $ENV{$envVar} = $value;
    }
    $opts->{$element} = $value;
    if ( !($element =~ /password/)) {
        $self->debug("value=$value");
    }
}

##########################################################################
# Functions to aid in loading drivers
##########################################################################

#-------------------------------------------------------------------------
# loadAllDrivers
#
# Results:
#       loads SCM drivers from properties into files or current
#       context#
#
# Arguments:
# Returns
#
#-------------------------------------------------------------------------
sub loadAllDrivers {
    my $self = shift;

    my $ec = $self->getCmdr();

    # make list of modules
    %scmlist = $self->getCfg()->getRegisteredSCMList();
    print "==== Loading SCM drivers from plugins =========\n";
    foreach my $scmPlugin (keys %scmlist) {
        print "Loading $scmPlugin\n";
        $self->load_driver($scmPlugin);
    }
    print "===============================================\n";
}
#-------------------------------------------------------------------------
# load_driver
#
# Results:
#   Load the ::Cfg and ::Driver packages for an SCM system
#
# Arguments:
#   scm - the name o the SCM driver
# Returns
#   The name of the driver if success, undef otherwise
#
#-------------------------------------------------------------------------
sub load_driver {
    my $self = shift;
    my $scmPlugin = shift;

    my $p = $self->load_package($scmPlugin,"Cfg");
    if (!defined $p) { return undef; }
    $p = $self->load_package($scmPlugin, "Driver");
    if (!defined $p) { return undef; }
    my $scmDriver = $scmPlugin;
    $scmDriver =~ s/-/\:\:/;
    $scmDriver .= "::Driver";

    return $scmDriver;
}

#-------------------------------------------------------------------------
# load_package
#
# Results:
#   Package is loaded inline using eval
#
# Arguments:
#   pkg - the name of a package to load from SCM driver registry
# Returns
#   The name of the package if success, undef otherwise
#
#-------------------------------------------------------------------------
sub load_package {
    my $self = shift;
    my $scmPlugin = shift;   # the plugin to use ie. ECSCM-Perforce
    my $pkg = shift;   # the module to load

    if (!defined $scmPlugin || "$scmPlugin" eq "" )
    {
        print "No plugin given to load_package\n";
        return undef;
    }
    if (!defined $pkg || "$pkg" eq "" )
    {
        print "No driver given to load_package\n";
        return undef;
    }


    # ie ECSCM::Perforce::Cfg
    my $driver = $scmPlugin;
    $driver =~ s/-/::/;
    $driver .= "::$pkg";

    # get class code
    my $property = "/plugins/$scmPlugin/project/scm_driver/$driver";
    my $result = ElectricCommander::PropMod::loadPerlCodeFromProperty(
        $self->getCmdr(), $property);
    if (!$result) {
        return undef;
    } else {
        return $pkg;
    }
}

##########################################################################
# Functions for both agentPreflight and clientPreflight (pf_xxxx)
##########################################################################

#------------------------------------------------------------------------------
# readFile
#
#       Read the contents of a file and return them.
#
# Arguments:
#       filename -          The name of the file to read
#------------------------------------------------------------------------------
sub pf_readFile {
    my ($self,$file) = @_;
    open(FILE, "$file") or $self->error("Cannot open file \"$file\": $!.");
    my @fileContents = <FILE>;
    close(FILE);
    return join("", @fileContents);
}

#------------------------------------------------------------------------------
# saveDataToFile
#
#       Writes the contents of a string to a file.
#
# Arguments:
#       filename -          The name of the file to which to write the string.
#       data -              The data to write to the file.
#------------------------------------------------------------------------------
sub pf_saveDataToFile
{
    my ($self,$fileName, $data) = @_;
    open(FILE, ">$fileName") or $self->error("Cannot open file \"$fileName\": $!");
    binmode(FILE);
    print(FILE $data);
    close(FILE);
}

#------------------------------------------------------------------------------
# pf_getCurrentWorkingDir
#
#------------------------------------------------------------------------------
sub pf_getCurrentWorkingDir
{
    my ($self) = @_;
    my $dir = File::Spec->curdir();
    if (!File::Spec->file_name_is_absolute($dir)) {
            $dir = File::Spec->rel2abs($dir);
    }
    return $dir;
}

##########################################################################
# Functions for clientPreflight  (cpf_xxxx)
##########################################################################
#------------------------------------------------------------------------------
# startJob
#
#       Kick off the preflight build by calling runProcedure.  Save the job id
#       for future use.
#------------------------------------------------------------------------------
sub cpf_startJob
{
    my ($self,$opts) = @_;
    $self->cpf_display("Launching the preflight build");

    if (!defined($opts->{procedure_priority}) || $opts->{procedure_priority} eq "") {
        $opts->{procedure_priority} = "normal";
    }

    my ($error, $xpath, $msg) = $self->InvokeCommander({IgnoreError=>0},"runProcedure",
            $opts->{procedure_projectName}, {
                "priority"          => $opts->{procedure_priority},
                "procedureName"     => $opts->{procedure_procedureName},
                "actualParameter"   => \@ {$opts->{procedure_parameters}},
            });
    if ($msg ne "") {
        $self->cpf_error("Error starting job: $msg");
    }
    $opts->{rt_jobId} = $xpath->findvalue("//jobId")->string_value;

    ($error, $xpath, $msg) = $self->InvokeCommander({IgnoreError=>0, SuppressResult=>1},"getJobInfo",
             $opts->{rt_jobId});
     if ($msg ne "") {
         $self->cpf_error("Error getting job info: $msg");
     }

    $self->cpf_display("JOB ID: " . $opts->{rt_jobId} );
    $self->cpf_display("JOB NAME: " . $xpath->findvalue("//jobName")->string_value );
}

#------------------------------------------------------------------------------
# waitForJob
#
#       Invoked by the SCM driver script once it's done uploading deltas.
#       Returns the outcome of the job once it completes.
#------------------------------------------------------------------------------
sub cpf_waitForJob()
{
    my ($self,$opts) = @_;
    if ($opts->{opts_Testing}) {
        $self->cpf_display("Would wait for job");
        return;
    }
    $self->cpf_display("Waiting for the job to complete");
    my ($success, $xpath,$msg) = $self->InvokeCommander({SuppressLog=>1,IgnoreError=>1}, "waitForJob",
            $opts->{rt_jobId}, $opts->{procedure_jobTimeout});
    if (!$success) {
        $self->cpf_error("Error waiting for job [$msg]");
    }
    my $status = $xpath->findvalue("//status")->string_value;
    my $outcome = $xpath->findvalue("//outcome")->string_value;
    if ($status ne "completed") {
        $self->cpf_error("The job did not complete in the given timeout ("
                . $opts->{procedure_jobTimeout} . " " . "seconds)");
    }
    if ($outcome ne "success") {
        $opts->{rt_jobId} = undef;
        $self->cpf_error("The job did not complete successfully");
    }
    $self->cpf_display("The job completed successfully");
    $opts->{rt_WaitedForJob} = 1;
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
# cpf_display
#
#       Prints a given message to stdout and the log.
#
# Arguments:
#       message -           The message to display.
#------------------------------------------------------------------------------
sub cpf_display() {
    my ($self,$message) = @_;
    chomp($message);
    $message =~ s/\.$//;
    $message = "$message.\n";
    if ($opts->{opt_Log}) {
        print(LOG $message);
    }
    print($message);
}

#------------------------------------------------------------------------------
# debug
#
#   prints a debug message if debugging is on
#------------------------------------------------------------------------------
sub debug {
    my ($self,$message) = @_;
    if ($::gDebug) {
        print("$message\n");
    }
}

#------------------------------------------------------------------------------
# cpf_debug
#
#       Prints a given message to the log, and also to stdout if the
#       program was invoked in debug mode.
#
# Arguments:
#       message -           The message to display.
#------------------------------------------------------------------------------
sub cpf_debug() {
    my ($self,$message) = @_;
    chomp($message);
    $message =~ s/\.$//;
    $message = "    $message";
    if ($opts->{opt_Log}) {
        print(LOG $message . "\n");
    }
    $self->debug($message);
}

#------------------------------------------------------------------------------
# cpf_error
#
#       Prints a given error message to the log and stderr, and exits
#       the program.
#
# Arguments:
#       message -           The message to display.
#------------------------------------------------------------------------------
sub cpf_error() {
    my ($self,$message) = @_;
    chomp($message);
    $message =~ s/\.$//;
    $message = "ERROR: $message.\n";
    if ($opts->{opt_Log}) {
        print(LOG $message);
    }
    print(STDERR $message);
    if ($opts->{opt_Log}) {
        close(LOG);
    }
    exit 1;
}

#------------------------------------------------------------------------------
# cpf_checkWaitForStep
#
#       Checks if the "waitForStep" property has been set on the procedure
#       so that the driver script knows if it should upload deltas immediately
#       after starting the job, or wait until it receives the snapshot location
#       and overlay the deltas directly.
#------------------------------------------------------------------------------
sub cpf_checkWaitForStep()
{
    my ($self,$opts) = @_;
    my $project = $opts->{procedure_projectName};
    my $procedure = $opts->{procedure_procedureName};

    $self->cpf_debug("Checking for the waitForStep property on the procedure");
    $opts->{rt_WaitForStep} = 0;
    my $prop = "/projects[$project]/procedures[$procedure]/ec_preflight/waitForStep";
    my ($error, $xpath,$msg) = $self->InvokeCommander({SuppressLog=>1,IgnoreError=>1},
        "getProperty",$prop);
    if (!$error) {
        my $waitForStep = $xpath->findvalue("property/value")->string_value;
        if ($waitForStep) {
            $self->cpf_debug("The waitForStep property was found and is set to true");
            $opts->{rt_WaitForStep} = 1;
        } else {
            $self->cpf_debug("The waitForStep property was found but is set to false");
        }
        return;
    }
    $self->cpf_debug("The waitForStep property was not found");
}

#------------------------------------------------------------------------------
# cpf_saveScmInfo
#
#       Save the given data to a file called ecpreflight_scmInfo, and then add
#       it to the files to be uploaded.
#
# Arguments:
#       data -              SCM information to write to the file.
#------------------------------------------------------------------------------
sub cpf_saveScmInfo()
{
    my ($self,$opts,$data) = @_;

    # Create a file with specific SCM information needed on the agent-side
    # to create the source snapshot.

    $self->cpf_debug("saving scmInfo for agent:$data");
    my $infoFile = $opts->{opt_LogDir} . "/ecpreflight_scmInfo";
    $self->pf_saveDataToFile($infoFile, $data);
    $self->cpf_debug("Adding SCM info file \"$infoFile\" to copy to "
            . "ecpreflight_data/scmInfo");
    $opts->{rt_FilesToUpload}{$infoFile} = "ecpreflight_data/scmInfo";
}

#------------------------------------------------------------------------------
# cpf_findTargetDirectory
#
#       If the preflight is set to wait for the step to complete, then upload
#       a "signal" file, ecpreflight_needTarget, and then wait for the step
#       to return a target directory to which to copy the sources directly.
#------------------------------------------------------------------------------
sub cpf_findTargetDirectory()
{
    my ($self,$opts) = @_;
    # If the job's workspace is marked as available on a network share, then
    # start the job immediately, wait for the preflight step to write out its
    # workspace information via putFiles, and then use that as the root for
    # copying deltas.

    if ($opts->{"rt_WaitForStep"}) {
        if (!$opts->{opt_Testing}) {
            # Kick off the preflight build now since we need the workspace
            # information from the preflight step before we can overlay the
            # sources directly.

            $self->cpf_startJob($opts);
        }

        # Invoke putFiles right away with a special file "needTarget" which
        # signals to the step that it needs to pass back its workspace info.

        my $signalFile = $opts->{rt_LogDir} ."/ecpreflight_needTarget";
        $self->pf_saveDataToFile($signalFile, "");
        $opts->{rt_FilesToUpload}{$signalFile} = "ecpreflight_data/needTarget";
        if (!$opts->{opt_Testing}) {
            $self->InvokeCommander({},"putFiles",
                $opts->{rt_jobId}, \%{$opts->{rt_FilesToUpload}} );

            # Call getFiles immediately, expecting the workspace information
            # to be uploaded by the step.

            $self->InvokeCommander({}, "getFiles", {
                    "jobId" => $opts->{rt_jobId},
                    "channel" => "workspace",
                    "baseDir" => $opts->{opt_LogDir} });
        }

        # Read the workspace information and select the appropriate entry
        # based on the client's OS.

        my $wsInfo = readFile($opts->{opt_LogDir} . "/ecpreflight_targetInfo");
        $wsInfo =~ m/(.*)\n(.*)\n/;
        $opts->{rt_TargetDirectory} = isWindows() ? $1 : $2;
    }
}

#------------------------------------------------------------------------------
# cpf_createManifestFiles
#
#       Create a couple of files: ecpreflight_deletes and ecpreflight_deltas
#       which will be used to store a lists of deletes and deltas for the
#       agent script to overlay on top of the source tree.
#------------------------------------------------------------------------------
sub cpf_createManifestFiles()
{
    my ($self,$opts) = @_;

    # Create a file used to collect all files which need to be deleted from
    # the source snapshot.

    my $deleteFileName = $opts->{opt_LogDir} . "/ecpreflight_deletes";
    open(DELETES, ">$deleteFileName") or $self->cpf_error("Couldn't create a delete "
            . "manifest file: $!");
    binmode(DELETES);

    # Create a file which will contain a list of delta files for the agent to
    # retrieve and copy over the source snapshot.

    my $deltasFileName = $opts->{opt_LogDir} . "/ecpreflight_deltas";
    open(DELTAS, ">$deltasFileName") or $self->cpf_error("Couldn't create a delta "
            . "manifest file: $!");
    binmode(DELTAS);

    # Create a file which will contain a list of directories for the agent to
    # create in the source tree.

    my $directoriesFileName = $opts->{opt_LogDir} . "/ecpreflight_directories";
    open(DIRECTORIES, ">$directoriesFileName") or $self->cpf_error("Couldn't create a "
            . "directory manifest file: $!");
    binmode(DIRECTORIES);
}

#------------------------------------------------------------------------------
# cpf_closeManifestFiles
#
#       Close the deltas and deletes manifest files created earlier, and add
#       them to the list of files to be uploaded to the agent.
#------------------------------------------------------------------------------
sub cpf_closeManifestFiles()
{
    my ($self,$opts) = @_;

    # Add the deletes manifest to the putFiles operation.

    close(DELETES);
    $self->cpf_debug("Adding deletes file \"" . $opts->{opt_LogDir} . "/ecpreflight_deletes\" "
            . "to copy to ecpreflight_data/deletes");
    $opts->{rt_FilesToUpload}{$opts->{opt_LogDir} . "/ecpreflight_deletes"}
            = "ecpreflight_data/deletes";

    # Add the deltas manifest to the putFiles operation.

    close(DELTAS);
    $self->cpf_debug("Adding deltas file \"" . $opts->{opt_LogDir} . "/ecpreflight_deltas\" "
            . "to copy to ecpreflight_data/deltas");
    $opts->{rt_FilesToUpload}{$opts->{opt_LogDir} . "/ecpreflight_deltas"}
            = "ecpreflight_data/deltas";

    # Add the directories manifest to the putFiles operation.

    close(DIRECTORIES);
    $self->cpf_debug("Adding directories file "
            . "\"" . $opts->{opt_LogDir} . "/ecpreflight_directories\" "
            . "to copy to ecpreflight_data/directories");
    $opts->{rt_FilesToUpload}{$opts->{opt_LogDir} . "/ecpreflight_directories"}
            = "ecpreflight_data/directories";
}

#------------------------------------------------------------------------------
# cpf_addDelta
#
#       Depending on whether a target directory has been defined or not, either
#       copy the file straight there or add it to the list of files to be
#       uploaded to the agent.
#
# Arguments:
#       source -            The source file.
#       dest -              The destination path, relative to the source tree.
#------------------------------------------------------------------------------
sub cpf_addDelta()
{
    my ($self,$opts,$source, $dest) = @_;
    $opts->{rt_FilesToCommit}{$source} = 1;
    if (defined($opts->{rt_TargetDirectory}) && $opts->{rt_TargetDirectory} ne "") {
        # Copy the file directly to the network share.
        $self->cpf_debug("Copying \"$source\" to \"" . $opts->{rt_TargetDirectory} . "/$dest\"");
        mkpath(dirname($opts->{rt_TargetDirectory} . "/$dest"));
        unlink($opts->{rt_TargetDirectory} . "/$dest");
        copy($source, $opts->{rt_TargetDirectory} . "/$dest");
    } else {
        # Add the file to the putFiles call.
        $self->cpf_debug("Adding \"$source\" to copy to "
                . "\"ecpreflight_files/$dest\"");
        $opts->{rt_FilesToUpload}{$source} = "ecpreflight_files/$dest";
    }
    $self->cpf_display("    Copying \"$dest\"");
    print(DELTAS "$dest\n");

    # Save the latest timestamp for comparison purposes before auto-
    # commiting (so any changes to the files can be detected).

    my $timestamp = stat($source);
    if (defined($timestamp) && $timestamp->mtime > $opts->{rt_LatestTimestamp}) {
        $opts->{rt_LatestTimestamp} = $timestamp->mtime;
    }
}

#------------------------------------------------------------------------------
# cpf_addDelete
#
#       Add a file to the delete manifest so the agent script deletes it after
#       creating the snapshot.
#
# Arguments:
#       dest -              The destination path, relative to the source tree.
#------------------------------------------------------------------------------
sub cpf_addDelete()
{
    my ($self,$dest) = @_;
    $self->cpf_display("    Deleting \"$dest\"");
    print(DELETES "$dest\n");
}

#------------------------------------------------------------------------------
# cpf_addDirectory
#
#       Depending on whether a target directory has been defined or not, either
#       create the directory straight there or add it to a list of directories
#       uploaded to the agent
#
# Arguments:
#       dest -              The destination directory, relative to the source
#                           tree.
#------------------------------------------------------------------------------
sub cpf_addDirectory()
{
    my ($self,$dest) = @_;
    $self->cpf_display("    Adding directory \"$dest\"");
    print(DIRECTORIES "$dest\n");
}

#------------------------------------------------------------------------------
# cpf_uploadFiles
#
#       Start the job if we haven't already, and upload the collected data
#       and deltas to the agent via putFiles.
#------------------------------------------------------------------------------
sub cpf_uploadFiles()
{
    my ($self,$opts) = @_;

    if (!$opts->{opt_Testing}) {
        if (!$opts->{rt_WaitForStep}) {
            # Kick off the preflight build.
            $self->cpf_startJob($opts);
        }

        # Call putFiles with all of the collected files and information.

        $self->cpf_display("Uploading new and modified files");
        $self->InvokeCommander({},"putFiles", $opts->{rt_jobId},
            \%{$opts->{rt_FilesToUpload}} ) ;
    }
}

#------------------------------------------------------------------------------
# cpf_checkTimestamps
#
#       Compare the timestamps of all deltas with the latest timestamp stored
#       before uploading them, and error out if any files have been modified
#       since the preflight was started.
#------------------------------------------------------------------------------
sub cpf_checkTimestamps()
{
    my ($self,$opts) = @_;

    foreach my $fileName (keys % { $opts->{rt_FilesToCommit} } ) {
        my $timestamp = stat($fileName);
        if (defined($timestamp) && $timestamp->mtime > $opts->{rt_LatestTimestamp}) {
            $self->cpf_error("Changes have been made to \"$fileName\" since the "
                    . "preflight build was launched");
        }
    }
}

##########################################################################
# Functions for agentPreflight  (apf_xxxx)
##########################################################################

#------------------------------------------------------------------------------
# downloadFiles
#
#       Download files from the server using the getFiles API.
#------------------------------------------------------------------------------

sub apf_downloadFiles {
    my ($self,$opts) = @_;
    print "Waiting to download files...\n";
    if (!$self->isTestMode()) {
        my $err;
        $self->getCmdr()->getFiles({error => \$err});
        if ($err) {
            $self->error("There was a problem receiving files on the agent: $err\n");
        }
    } else {
        print("Invoking getFiles.\n");
    }
}

#------------------------------------------------------------------------------
# transmitTargetInfo
#
#       If the client requests a target directly to which deltas can be written
#       directly, then upload a file with the information.
#------------------------------------------------------------------------------

sub apf_transmitTargetInfo
{
    my ($self,$opts) = @_;
    if (-e "ecpreflight_data/needTarget") {
        # Pass the step's workspace information to the client so it can copy
        # the deltas directly there.

        my $signalFile = "ecpreflight_targetInfo";
        my $xpath = $self->getCmdr()->getJobStepDetails($::ENV{COMMANDER_JOBSTEPID});
        my $winShare = $xpath->findvalue("//workspace/winUNC")->string_value;
        my $unixShare = $xpath->findvalue("//workspace/unix")->string_value;
        my $data = "$winShare/$opts->{delta}\n"
                . "$unixShare/$opts->{delta}\n";
        print("Workspace data passed to client:\n$data\n");
        $self->pf_saveDataToFile($signalFile, $data);
        my %files = ($signalFile => "ecpreflight_targetInfo");
        if (!$self->isTestMode()) {
            $self->getCmdr()->putFiles($ENV{COMMANDER_JOBID}, \%files,
                    {"channel" => "workspace"});
        } else {
            print("Invoking putFiles.\n");
        }
        $self->apf_downloadFiles();
    }
}

#------------------------------------------------------------------------------
# deleteFiles
#
#       Delete all files marked for deletion on the client side.
#------------------------------------------------------------------------------

sub apf_deleteFiles {
    my ($self,$opts) = @_;
    my $oldUmask = umask;
    umask(0000);
    if (-e "ecpreflight_data/deletes" && -s "ecpreflight_data/deletes" > 0) {
        print("Deleting file list received from client:\n");
        open(DELETES, "ecpreflight_data/deletes")
                or $self->error("Cannot open ecpreflight_data/deletes: $!.");
        while (<DELETES>) {
            my $target = $_;
            chomp($target);
            print("Deleting: \"$opts->{dest}/$target\"\n");
            chmod(0777, "$opts->{dest}/$target");
            if (-d "$opts->{dest}/$target") {
                rmtree("$opts->{dest}/$target") or
                        $self->error("Failed to delete \"$opts->{dest}/$target\"\n");
            } elsif (-e "$opts->{dest}/$target") {
                unlink("$opts->{dest}/$target") or
                        $self->error("Failed to delete \"$opts->{dest}/$target\"\n");
            }
        }
        close(DELETES);
        print("\n");

        # Delete all empty subdirectories.
        # The need to delete empty subdirectories is something that may be
        # unique to perforce.  It is not necessary in Accurev for example.
        # Should move this into perforce agent driver.
        finddepth(sub{rmdir}, "$opts->{dest}");
    }
    umask($oldUmask);
}

#------------------------------------------------------------------------------
# overlayDeltas
#
#       Overlay the deltas transmitted by the client on top of the source tree.
#------------------------------------------------------------------------------

sub apf_overlayDeltas {
    my ($self,$opts) = @_;
    if (-e "ecpreflight_data/deltas" && -s "ecpreflight_data/deltas" > 0) {
        print("Overlaying file list received from client:\n");
        open(DELTAS, "ecpreflight_data/deltas")
                or $self->error("Cannot open ecpreflight_data/deltas: $!.");
        while (<DELTAS>) {
            my $fileName = $_;
            chomp($fileName);
            my $targetDir = $opts->{dest} ."/" . dirname($fileName);
            mkpath($targetDir);
            if (-e "$opts->{delta}/$fileName") {
                if (-e "$opts->{dest}/$fileName") {
                    print("Overwriting: \"$opts->{dest}/$fileName\"\n");
                    $self->apf_copyAndPreserve("$opts->{delta}/$fileName",
                            "$opts->{dest}/$fileName");
                    unlink("$opts->{delta}/$fileName");
                } else {
                    print("Moving: \"$opts->{delta}/$fileName\" to "
                            . "\"$targetDir\"\n");
                    move("$opts->{delta}/$fileName", $targetDir) or
                            $self->error("Failed to move "
                            . "\"$opts->{delta}/$fileName\" "
                            . "to \"$targetDir\": $!\n");
                }
            }
        }
        close(DELTAS);
        print("\n");

        # Delete the delta location directory.
        rmtree("$opts->{delta}") or
                $self->error("Couldn't remove directory $opts->{delta}: $!\n");
    }
}

#------------------------------------------------------------------------------
# copyAndPreserve
#
#       Copy a delta over the original version while preserving the file
#       permissions.
#------------------------------------------------------------------------------

sub apf_copyAndPreserve {
    my ($self,$from, $to) = @_;
    my $in = new IO::File "<$from" or $self->error("Couldn't open file \"$from\" for "
            . "reading: $!.");
    my $out = new IO::File ">$to";
    my $originalMode = -1;

    # just needed for this function
    if ($^O eq "MSWin32") {
        eval{
            require Win32::IntAuth;
            import Win32::IntAuth;
            require Win32::OLE;
            import Win32::OLE;
        };
        if ($@) {
            die "Could not load Win32 perl modules $!";
        }
    }

    if (!$out) {
        # The file is probably marked read-only, or is protected.  Open up the
        # permissions and try again.

        if ($^O eq "MSWin32") {
            # Grant the current user write permissions on the file.

            my $auth  = Win32::IntAuth->new();
            my $username = $auth->get_username();
            $self->RunCommand("cacls \"$to\" /E /G \"$username\":W");

            # Turn off the read-only bit.

            my $objFSO = Win32::OLE->new('Scripting.FileSystemObject');
            my $objFile = $objFSO->GetFile($to);
            if ($objFile->Attributes && 1) {
                $objFile->{Attributes} = $objFile->Attributes - 1;
            }
        } else {
            # Remember the current mode and then modify the file so it's
            # world-writable.

            print("Unlocking file \"$to\".\n");
            my $stat = stat($to);
            $originalMode = $stat->mode & 0777;
            chmod(0666, $to);
        }

        # Now, try to open the file again.  Error out if it fails this time.

        $out = new IO::File ">$to" or $self->error("Couldn't open file \"$to\" for "
                . "writing: $!.");
    }

    # Copy the contents in chunks.

    binmode($in);
    binmode($out);

    unless ( copy $in, $out) {
        $out->close();
        $in->close();
        $self->error("Failed to copy contents from \"$from\" to \"$to\"");
    }

    if(!$out->close()) {
        $in->close();
        print("WARNING: Failed to close file \"$to\".\n");
    }

    # Restore the original file mode on UNIX systems (if we had it saved).

    if (!($^O eq "MSWin32") && $originalMode >= 0) {
        chmod($originalMode, $to);
    }

    return 1;
}

#------------------------------------------------------------------------------
# createDirectories
#
#       Creates all new directories specified by the client.
#------------------------------------------------------------------------------

sub apf_createDirectories {
    my ($self,$opts) = @_;
    my $oldUmask = umask;
    umask(0000);
    if (-e "ecpreflight_data/directories"
            && -s "ecpreflight_data/directories" > 0) {
        print("Creating directory list received from client:\n");
        open(DIRECTORIES, "ecpreflight_data/directories")
                or $self->error("Cannot open ecpreflight_data/directories: $!.");
        while (<DIRECTORIES>) {
            my $dirName = $_;
            chomp($dirName);
            if (! -d "$opts->{dest}/$dirName") {
                print("Creating: \"$opts->{dest}/$dirName\"\n");
                mkpath("$opts->{dest}/$dirName") or
                        $self->error("Failed to create dir "
                        . "\"$opts->{dest}/$dirName\"\n");
            }
        }
        close(DIRECTORIES);
        print("\n");
    }
    umask($oldUmask);
}


##########################################################################
# Functions that derived classes need to implement
##########################################################################

####################################################################
##### SPECIFIC SCM OBJECTS SHOULD OVERRIDE THESE METHODS ##########
#
#   isImplemented   - used to determine what functionality an
#                     SCM plugin has implemented
#   getSCMTag       - used by CI server ElectricSentry
#   checkoutCode    - used to checkout code
#   apf_driver      - used for preflight
#   cpf_driver      - used for preflight
#
####################################################################


####################################################################
# isImplemented
####################################################################
sub isImplemented {
    my ($self, $method) = @_;

    return 0;
}

####################################################################
# getSCMTag
####################################################################
sub getSCMTag {
    my ($self, $opts) = @_;

    print "SCM Tag not supported.\n";
    return (undef,undef);
}

####################################################################
# code checkout for snapshot
####################################################################
sub checkoutCode {
    my ($self, $opts) = @_;

    if ($opts->{test}) { $self->setTestMode(1); }
    print "Code checkout not supported.\n";
}

####################################################################
# agent preflight functions
####################################################################
sub apf_driver {
    my ($self, $opts) = @_;

    if ($opts->{test}) { $self->setTestMode(1); }
    print "Agent Preflight not supported.\n";
}

####################################################################
# client preflight functions
####################################################################
sub cpf_driver {
    my ($self, $opts) = @_;

    if ($opts->{test}) { $self->setTestMode(1); }
    print "Client Preflight not supported.\n";
}

####################################################################
# cleanup
####################################################################
sub cleanup {
    my ($self, $opts) = @_;

    if ($opts->{test}) { $self->setTestMode(1); }
}

###   ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^  ##########
#####  SPECIFIC SCM OBJECTS SHOULD OVERRIDE THESE METHODS ##########
####################################################################


################## Utility Functions ###############################
#-------------------------------------------------------------------------
#  sentryTimeConvert
#
#
#   Params:
#       timeDateString  -   format is currently designed to handle
#                           StarTeam, but could be adapted to others
#                                US -  5/29/08 5:21:14 PM PDT
#
#   Returns:
#       timeStamp
#
#-------------------------------------------------------------------------
sub sentryTimeConvert
{
    my $self = shift;
    my $timeDateString = shift;

    my $timeStamp = "";
    if ($timeDateString =~ m'(\d+)/(\d+)/(\d+) (\d+):(\d+):(\d+) (\w{2}) (\w{3})') {

        my $year    = $3;
        my $month   = $1;
        my $day     = $2;

        my $hours   = $4;
        my $minutes = $5;
        my $seconds = $6;

        if ($7 =~ /PM/i  &&  ($hours < 12) ) {
            $hours += 12;
        }
        if ($7 =~ /AM/i  &&  ($hours == 12) ) {
            $hours = 0;
        }
        $timeStamp = timelocal($seconds, $minutes, $hours, $day, $month-1, $year);
    }

    return $timeStamp;

}

####################################################################
# Helper function for SCM change logs
####################################################################

####################################################################
# getGrandParentStepId
#
# Side Effects:
#
# Arguments:
#   self -              the object reference
#
# Returns:
#   The step id of the grand parent or "".
#
####################################################################
sub getGrandParentStepId
{
    my ($self) = @_;

    my ($success, $xpath, $msg) = $self->InvokeCommander({SuppressLog=>1,IgnoreError=>1}, "getProperty", "/myParent/jobStepId", {jobStepId => $ENV{COMMANDER_JOBSTEPID}});

    if (!$success) {
        print "WARNING: Could not retrieve parent's jobStepId\n";
        return "";
    }

    my $parentStepId = $xpath->findvalue('//value')->value();

    my ($success, $xpath, $msg) = $self->InvokeCommander({SuppressLog=>1,IgnoreError=>1}, "getProperty", "/myParent/jobStepId", {jobStepId => $parentStepId});

    if (!$success) {
        if ($self->inPipeline) {
            print "Could not retrieve grandparent's jobStepId from inside a pipeline\n";
            return '';
        }
        print "WARNING: Could not retrieve grandparent's jobStepId\n";
        return "";
    }

    my $grandParentStepId = $xpath->findvalue('//value')->value();

    return $grandParentStepId;
}


#-------------------------------------------------------------------------
#
#  Find the name of the Project of the current job and the
#  Schedule that was used to launch it
#
#  Params
#       None
#
#  Returns
#       projectName  - the Project name of the running job
#       scheduleName - the Schedule name of the running job
#       procedureName - the name of the procedure of the running job
#  Notes
#       scheduleName will be an empty string if the current job was not
#       launched from a Schedule
#
#-------------------------------------------------------------------------

sub getProjectAndScheduleNames
{
    my $self = shift;

    # Call Commander to get info about the current job
    my ($success, $xPath) = $self->InvokeCommander({SuppressLog=>1},
            "getJobInfo", $ENV{COMMANDER_JOBID});

    # Find the schedule name in the properties
    my $scheduleName = $xPath->findvalue('//scheduleName') || "";
    my $projectName = $xPath->findvalue('//projectName') || "";
    my $procedureName = $xPath->findvalue('//procedureName') || "";

    return ($projectName, $scheduleName, $procedureName);
}


####################################################################
# updateLastGoodAndLastCompleted
#
# Side Effects:
#   If the current job outcome is "success" copy the current
#   revision from the job level property to the "lastGood"
#   property and the "lastCompleted" property.  If not success,
#   only copy the current revision to the "lastCompleted" property.
#
# Arguments:
#   self -              the object reference
#   opts -              A reference to the hash with values
#
# Returns:
#   nothing.
#
####################################################################
sub updateLastGoodAndLastCompleted
{
    my ($self, $opts) = @_;

    my $prop = "/myJob/outcome";
    my ($success, $xpath, $msg) = $self->InvokeCommander({SuppressLog=>1,IgnoreError=>1}, "getProperty", $prop);

    if ($success) {

        my $grandParentStepId = "";
        $grandParentStepId = $self->getGrandParentStepId();

        if (!$grandParentStepId || $grandParentStepId eq "") {
            print "WARNING: Could not get the grand parent step id\n";
            return;
        }

        my $properties = $self->getPropertyNamesAndValuesFromPropertySheet("/myJob/ecscm_snapshots");

        foreach my $key ( keys %{$properties}) {
            my $snapshot = $properties->{$key};

            if ("$snapshot" ne "") {

                $prop = "/myProcedure/ecscm_snapshots/$key/lastCompleted";
                $self->InvokeCommander({SuppressLog=>1,IgnoreError=>1}, "setProperty", "$prop", "$snapshot", {jobStepId => $grandParentStepId});

                my $val = $xpath->findvalue('//value')->value();

                if ($val eq "success") {
                    $prop = "/myProcedure/ecscm_snapshots/$key/lastGood";
                    $self->InvokeCommander({SuppressLog=>1,IgnoreError=>1}, "setProperty", "$prop", "$snapshot", {jobStepId => $grandParentStepId});
                }
            } else {
                print "Property /myJob/ecscm_snapshots/$key has an empty value \n";
            }
        }
    } else {
        print "Could not retrieve property $prop from Commander\n";
    }
}

####################################################################
# getPropertyNamesAndValuesFromPropertySheet
#
# Side Effects:
#   Extracts propertyNames and values from the specified property sheet.
#
# Arguments:
#   self -              the object reference
#   propertySheet -     the property sheet to parse
#
# Returns:
#   A reference to a hash of propertyNames and values.
####################################################################
sub getPropertyNamesAndValuesFromPropertySheet
{
    my ($self, $propertySheet) = @_;

    my $properties = {};

    my ($success, $xpath, $msg) = $self->InvokeCommander({SuppressLog=>1,IgnoreError=>1}, "getProperties", {recurse => "1", path => "$propertySheet"});

    if ($success) {

       my $results = $xpath->find('//property');
       if (!$results->isa('XML::XPath::NodeSet')) {
                print "WARNING: Could not get the nodeset\n";
       }

       foreach my $context ($results->get_nodelist) {
            my $name = $xpath->find('./propertyName', $context);
            my $value = $xpath->find('./value', $context);
		    $properties->{$name} = $value;
       }
    } else {
       print "Could not retrieve property sheet $propertySheet\n";
    }

    return $properties;
}

####################################################################
# getStartForChangeLog
#
# Side Effects:
#   Check a property for the lastGood snapshot.  If that does
#   not exist, check for the lastCompleted.
#
#   Procedure property sheet: ecscm_snapshots
#     SCM (1) property sheet: <scm type>
#         SCM (1) property sheet (1)
#             Property key = lastCompleted, value =
#             Property key = lastGood, value =
#         SCM (1) property sheet (n)
#
#     SCM (n) property sheet: ..
#
# Arguments:
#   self -              the object reference
#   scmKey -
#
# Returns:
#   The last snapshot or "".
#
####################################################################
sub getStartForChangeLog
{
    my ($self, $scmKey) = @_;

    my $grandParentStepId = "";
    $grandParentStepId = $self->getGrandParentStepId();

    if (!$grandParentStepId || $grandParentStepId eq "") {
        if ($self->inPipeline) {
            print "Could not get the grandparent stepId from inside a pipeline\n";
            return '';
        }
        print "WARNING: Could not get the grandparent stepId\n";
        return "";
    }

    my $from = "";

    # try to get the lastGood snapshot
    my $prop = "/myProcedure/ecscm_snapshots/$scmKey/lastGood";

    $from = $self->getSnapshotFromProperty($prop, $grandParentStepId);

    if ($from eq "") {
        # try get the lastCompleted snapshot
        my $prop = "/myProcedure/ecscm_snapshots/$scmKey/lastCompleted";
        return $self->getSnapshotFromProperty($prop, $grandParentStepId);
    }

    return $from;
}

####################################################################
# getLastSnapshotId
#   Get revision of last snapshot fetched for repository identified
#   by scmkey argument.
#
# Side Effects:
#
# Arguments:
#   self -              the object reference
#   scmKey  -           the scm type followed by something to identify
#                       the code base within the scm system.
#                       e.g. for subversion:
#                       Subversion-<translated subversion url>
#
# Returns:
#   The start for the change log or "".
#
####################################################################
sub getLastSnapshotId
{
    my ($self, $scmKey) = @_;
    my ($projectName, $scheduleName, $procedureName) = $self->getProjectAndScheduleNames();

    my @filter = (
        {"propertyName" => "projectName",
                "operator"     => "equals",
                "operand1"     => $projectName
        },
        {"propertyName" => "liveProcedure",
                "operator"     => "equals",
                "operand1"     => $procedureName
        },
        {"propertyName" => "status",
                "operator"     => "equals",
                "operand1"     => "completed"
        },
        {"propertyName" => "outcome",
                "operator"     => "equals",
                "operand1"     => "success"
    });

    # If procedure is running from schedule, narrow search criteria
    # to jobs, launched only for that schedule
    if (length($scheduleName)) {
        push(@filter,
            {
                    "propertyName" => "liveSchedule",
                    "operator"     => "equals",
                    "operand1"     => $scheduleName
        });
    } else {
        push(@filter,
            {
                    "propertyName" => "liveSchedule",
                    "operator"     => "isNull"
        });
    }

    # Search for completed jobs of procedure, that contains
    # ECSCM's checkout step
    my $xpath = $self->getCmdr()->findObjects("job",
        {
            maxIds => 1,
            numObjects => 1,
            filter => \@filter,
            select => [{propertyName => "ecscm_snapshots", recurse => 1}],
            sort => [{propertyName  => "finish", order  => "descending"}]
        }
    );

    # return /ecscm_snapshots/$scmKey job's property
    return $xpath->findvalue("//property[propertyName='$scmKey']/value")->value() || "";
}


####################################################################
# getSnapshotFromProperty
#
# Side Effects:
#
# Arguments:
#   self -              the object reference
#   prop -              the property to query for
#   grandParentStepId - the jobStepId to use
#
# Returns:
#   The property value or "".
#
####################################################################
sub getSnapshotFromProperty
{
    my ($self, $prop, $grandParentStepId) = @_;

    my ($success, $xpath, $msg) = $self->InvokeCommander({SuppressLog=>1,IgnoreError=>1}, "getProperty", $prop, {jobStepId => $grandParentStepId});

    if ($success) {
        return $xpath->findvalue('//value')->value();
    } else {
        print "Could not retrieve property: $prop\n";
        return "";
    }
}

####################################################################
# setPropertiesOnJob
#
# Side Effects:
#   Stores the changelog in a property.
#   Sets a job level property with the current revision.
#
# Arguments:
#   self -              the object reference
#   scmKey -
#   snapshot -
#   changeLog -
#   url -               optional, repository url
#
# Returns:
#   nothing
#
####################################################################
sub setPropertiesOnJob
{
    my ($self, $scmKey, $snapshot, $changeLog, $url) = @_;

    my $prop = "/myJob/ecscm_changeLogs/$scmKey";
    my $opts = {SuppressLog=>1,IgnoreError=>1};

    $changeLog = HTML::Entities::encode($changeLog);

    my ($success, $xpath, $msg) = $self->InvokeCommander($opts, "setProperty", $prop, $changeLog);

    if (!$success) {
        print "WARNING: Could not set the property $prop to $changeLog\n";
    }

    $prop = "/myJob/ecscm_snapshots/$scmKey";

    my ($success, $xpath, $msg) = $self->InvokeCommander($opts, "setProperty", $prop, $snapshot);

    if (!$success) {
        print "WARNING: Could not set the property $prop to $snapshot\n";
    }

    # Set repository url property, if any
    if(length($url)) {
        $prop = "/myJob/ecscm_repositoryUrls/$scmKey";
        my ($success, $xpath, $msg) = $self->InvokeCommander($opts, "setProperty", $prop, $url);

        if (!$success) {
            print "WARNING: Could not set the property $prop to $url\n";
        }
    }
}

####################################################################
# createLinkToChangelogReport
#
# Side Effects:
#   If /myJob/ecscm_changelogs exists, create a report-urls link
#
# Arguments:
#   self -              the object reference
#   reportName -        the name of the report
#
# Returns:
#   Nothing.
####################################################################
sub createLinkToChangelogReport {
    my ($self, $reportName) = @_;

    my $name = $self->getCfg()->getSCMPluginName();

    my ($success, $xpath, $msg) = $self->InvokeCommander({SuppressLog=>1,IgnoreError=>1}, "getProperty", "/plugins/$name/pluginName");
    if (!$success) {
        print "Error getting promoted plugin name for $name: $msg\n";
        return;
    }

    my $root = $xpath->findvalue('//value')->string_value;

    my $jobId = $ENV{COMMANDER_JOBID};
    my $prop = "/myJob/report-urls/$reportName";
    my $target = "/commander/pages/$root/reports?jobId=" . $jobId;

    print "Creating link to change log $target\n";

    ($success, $xpath, $msg) = $self->InvokeCommander({SuppressLog=>1,IgnoreError=>1}, "setProperty", "$prop", "$target");

    if (!$success) {
        print "Error trying to set property $prop: $msg\n";
    }
}

####################################################################
# dumpOpts
#
####################################################################
sub dumpOpts
{
   my ($self, $opts) = @_;

   print "\n-------------start opts------------\n";

   foreach my $e (keys % {$opts}) {

       print "  key=$e, val=$opts->{$e}\n";
    }
   print "\n-------------end opts------------\n";
}


#################################
# makeReplacements
# Inputs: textToCensor, output from a 3rd party tool
# hash reference, where the key is the string to match and the value is the replacement text
#
# This function iterates through the hash and looks for the key and replaces it with the value
#
# Side Effects:
# No ordering guarantee
#
#################################
sub makeReplacements
{
  my ($self, $textToCensor, $hashRef) = @_;

  return $textToCensor unless defined($hashRef);

  # Iterate over hash keys
  foreach (keys %{$hashRef})
  {
    my $match = quotemeta($_);
    my $replace = $hashRef->{$_};
    $textToCensor =~ s|$match|$replace|g;
  }
  return $textToCensor;
}

sub inPipeline {
    my ($self) = @_;

    my ($success, $xpath, $error) = $self->InvokeCommander({SuppressLog => 1, IgnoreError => 1}, 'getProperty', '/myPipelineStageRuntime');
    return $success ? 1 : 0;
}


1;



