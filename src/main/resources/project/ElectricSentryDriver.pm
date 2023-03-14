###########################################################
# ElectricSentry::Driver.pm
#
# This is the Perl package that installs and runs ElectricSentry
# It provides continuous integration builds for ElectricCommander
#
# Copyright (c) 2006-2009 Electric Cloud, Inc.
# All rights reserved

package ElectricSentry::Driver;

#use strict;
use ElectricCommander;
use Cwd;
use XML::XPath;
use Time::Local;
use File::Basename;
use HTTP::Date(qw {str2time time2str time2iso time2isoz});
use Data::Dumper;

if ( !defined ECSCM::Base::Driver ) {
    require ECSCM::Base::Driver;
}

#
# ElectricSentry stores and retrieves configuration from several places
# These helper classes manage the configuration. They must be loaded
# dynamically from properties
#

# /projects/Electric Cloud/schedules/SentryMonitor/ElectricSentrySettings
if ( !defined ElectricSentry::GlobalCfg ) {
    require ElectricSentry::GlobalCfg;
}

# /projects/Electric Cloud/schedules/SentryMonitor/ElectricSentrySettings/EC-Examples/Run Demo
if ( !defined ElectricSentry::ScheduleCfg ) {
    require ElectricSentry::ScheduleCfg;
}

# /projects/EC-Examples/Run Demo
if ( !defined ElectricSentry::TriggerCfg ) {
    require ElectricSentry::TriggerCfg;
}

# /jobs/#/SentrySchedules/proj/sched
if ( !defined ElectricSentry::JobCfg ) {
    require ElectricSentry::JobCfg;
}

####################################################################
# Object constructor for ElectricSentry::Driver
#
# Inputs
#    cmdr     previously initialized ElectricCommander handle
####################################################################
sub new {
    my $class = shift;

    my $self = {
        _cmdr    => shift,
        _logging => shift,
    };

    bless( $self, $class );
    $self->{_ecscm} = new ECSCM::Base::Driver( $self->{_cmdr} );

    return $self;
}

####################################################################
# getECSM
#
#
# Return
#   Reference to the ECSCM::Base::Driver member
####################################################################
sub getECSCM {
    my $self = shift;
    return $self->{_ecscm};
}

####################################################################
# getCmdr
#
#
# Return
#   Reference to the ECSCM::Base::Driver member
####################################################################
sub getCmdr {
    my $self = shift;
    return $self->{_cmdr};
}

####################################################################
# logging
#
# Inputs
#   value  - if provide, logging is set to this value
#
# Return
#   returns the current value of logging (before new value applied)
####################################################################
sub logging {
    my $self  = shift;
    my $value = shift;

    my $old = $self->{_logging};
    if ( defined $value ) {
        $self->{_logging} = $value;
    }
    return $old;
}

#-------------------------------------------------------------------------
# Display debugging info
#-------------------------------------------------------------------------
sub setup {
    my $self = shift;

    # Display the environment for the log
    $self->PrintEnv();
}

#-------------------------------------------------------------------------
#
#  Enumerate all of the schedules in all of the projects to find the ones that
#  are enabled to be auto-run by Sentry
#
#
#-------------------------------------------------------------------------
sub findSentrySchedules {
    my $self = shift;

    my $projectListParameter = "";
    my @projectList          = ();
    my @projectFilter        = ();
    my @filter               = ();

    # Check for a parameter to the procedure that defines a list of projects
    #   Note - this is retrieved, rather than passed on the command line because
    #          it can be multi-line
    my ( $success, $xPath ) =
      $self->getECSCM()
      ->InvokeCommander( { SuppressLog => 1, IgnoreError => 1 },
        "getProperty", "/myCall/projectList",
        { "jobStepId" => $ENV{COMMANDER_JOBSTEPID} } );
    if ($success) {
        $projectListParameter = $xPath->findvalue('//value');
    }

    #  Split the parameter into projects and add them to a list of filters
    for my $projectName ( split( "\n", $projectListParameter ) ) {
        push(
            @projectFilter,
            {
                "propertyName" => "projectName",
                "operator"     => "equals",
                "operand1"     => $projectName
            }
        );
        print "Scanning schedules for project '$projectName'\n";
    }

    # Create a filter to look for all the projects if there are any
    if ( scalar @projectFilter ) {
        push(
            @filter,
            {
                "operator" => "or",
                "filter"   => \@projectFilter
            }
        );
    }
    else {

        # If the project list is empty, this is the default instance
        # Get the names of projects to exclude
        print "*** This is the Default Sentry instance ***\n";
        print "\tThis instance should monitor all Projects not monitored by any other Sentry instance\n";
        @projectList = $self->findNonDefaultProjects();

        #  Split the parameter into projects and add them to a list of filters
        if ( scalar @projectList ) {
            for my $projectName (@projectList) {
                push(
                    @projectFilter,
                    {
                        "propertyName" => "projectName",
                        "operator"     => "equals",
                        "operand1"     => $projectName
                    }
                );
            }

            # Create a filter that excludes all of the non-default projects
            push(
                @filter,
                {
                    "operator" => "not",
                    "filter"   => [
                        {
                            "operator" => "or",
                            "filter"   => \@projectFilter
                        }
                    ]
                }
            );
        }
    }

    # Retrieve all schedules from the specified projects
    my $retrieveChunkSize = 1000;
    $retrieveChunkSize = $ENV{SENTRY_FINDCHUNKSIZE}
      if ( defined $ENV{SENTRY_FINDCHUNKSIZE} );
    my $numProcessed = 0;
    my ( $success, $xPath ) = $self->getECSCM()->InvokeCommander(
        { SuppressLog => 1 },
        "findObjects",
        "schedule",
        {
            filter     => \@filter,
            numObjects => $retrieveChunkSize
        }
    );

    # Build a list of all object IDs
    my @allSchedulesList = ();
    my $objectNodeset    = $xPath->find('//response/objectId');
    foreach my $node ( $objectNodeset->get_nodelist ) {
        my $objectId = $node->string_value();
        push( @allSchedulesList, $objectId );
    }

    #  Process the IDs in chunks
    my $totalCount = scalar @allSchedulesList;
    while ( $numProcessed < $totalCount ) {

        # Retrieve the next chunk of objects (skip the first time)
        if ( $numProcessed > 0 ) {
            my $startingIndex = $numProcessed;
            my $endingIndex   = $startingIndex + $retrieveChunkSize - 1;
            $endingIndex = $totalCount - 1 if ( $endingIndex >= $totalCount );
            my @objectList =
              @allSchedulesList[ $startingIndex .. $endingIndex ];
            ( $success, $xPath ) =
              $self->getECSCM()->InvokeCommander( { SuppressLog => 1 },
                "getObjects", { objectId => \@objectList } );
        }

        # Process the current chunk of objects
        my $scheduleNodeset = $xPath->find('//response/object/schedule');
        foreach my $node ( $scheduleNodeset->get_nodelist ) {

            my $projectName  = $xPath->findvalue( 'projectName',  $node );
            my $scheduleName = $xPath->findvalue( 'scheduleName', $node );
            $numProcessed++;

            # Look for the special trigger property
            my $tCfg =
              new ElectricSentry::TriggerCfg( $self->getCmdr(), $projectName,
                $scheduleName );
            my $bTriggerFlag = $tCfg->isSetTriggerFlag();
            if ($bTriggerFlag) {

                # Skip schedule names with unsupported characters
                my $specialCharacterString = "";
                if ( $scheduleName =~ /\// ) {
                    $specialCharacterString = "'/'";
                }
                elsif ( $scheduleName =~ /\[|\]/ ) {
                    $specialCharacterString = "'[' or ']'";
                }

                if ($specialCharacterString) {
                    $self->getECSCM()
                      ->issueWarningMsg(
"*** Skipping schedule - '$scheduleName' in project '$projectName'\n"
                          . "    It contains an unsupported special character ($specialCharacterString)"
                      );
                    next;
                }

                # Save the Project & Schedule, along with a default value that
                # can be changed in later steps to prevent execution
                print
"Monitoring schedule - '$scheduleName' in project '$projectName'\n";
                $self->SaveProjectandSchedule( $projectName, $scheduleName,
                    "SentrySchedule" );
            }
        }
    }
}

#-------------------------------------------------------------------------
#   findNonDefaultProjects
#
#   Find all projects that are NOT part of the default project set.
#   The strategy for doing this is to locate other schedules in the same
#   project that call the same procedure.  Extract their "projectList"
#   actualParameter to get all projects that are explicitly handled by
#   another schedule.
#
# Results:
#      Returns a list of Project Names
#
# Arguments:
#      None
#
#-------------------------------------------------------------------------
sub findNonDefaultProjects() {
    my $self = shift;

    my @objectFilter;
    my %nonDefaultProjects;

    # Get the current project and procedure
    my ( $sentryProjectName, $sentryScheduleName, $sentryProcedureName ) =
      $self->ECSentryGetProjectAndScheduleNames();

    print "The Schedule that this job ran from is: \"$sentryScheduleName\"\n";

    # BSH: Use the retrieved projectName and scheduleName to get the source
    # schedule's details and extract the procedureName from the schedule. This
    # form of the procedureName should match the procedureName from other
    # Sentry schedules and allow findObjects to find them.

    # Call Commander to get info about the Schedule that launched this job
    my ( $success, $xPath ) = $self->getECSCM()->InvokeCommander(
        { SuppressLog => 1 }, "getSchedule",
        "$sentryProjectName", "$sentryScheduleName"
    );

    # Find the procedureName from the Schedule
    my $procedureNameFromSchedule = $xPath->findvalue('//procedureName');

    $sentryProcedureName = "$procedureNameFromSchedule";

    print "Searching for other Sentry schedules...\n";
    print "\twhere projectName = $sentryProjectName\n";
    print "\tand procedureName = $sentryProcedureName\n";

    # Find all schedules that refer to the running procedure
    push(
        @objectFilter,
        {
            "propertyName" => "projectName",
            "operator"     => "equals",
            "operand1"     => $sentryProjectName
        }
    );
    push(
        @objectFilter,
        {
            "propertyName" => "procedureName",
            "operator"     => "equals",
            "operand1"     => $sentryProcedureName
        }
    );
    my ( $success, $xPath ) =
      $self->getECSCM()->InvokeCommander( { SuppressLog => 1 },
        "findObjects", "schedule", { "filter" => \@objectFilter, } );

    # Count how many other Sentry Schedules were found
    my $scheduleCount = $xPath->find('count(//response/object/schedule)');
    print "FOUND $scheduleCount other Sentry Schedules\n";

    # Loop over the returned schedules
    my $scheduleNodeset = $xPath->find('//response/object/schedule');
    foreach my $node ( $scheduleNodeset->get_nodelist ) {

        # Skip if the schedule is myself
        my $scheduleName = $xPath->findvalue( 'scheduleName', $node );
        print "found Sentry schedule named: \"$scheduleName\"\n";
        if ( $scheduleName eq $sentryScheduleName ) {
            print "\tthis is my own Schedule... skipping\n";
            next;
        }

        # Retrieve the actualParameter from the schedule
        my $projectName = $xPath->findvalue( 'projectName', $node );
        my ( $success2, $xPath2 ) = $self->getECSCM()->InvokeCommander(
            { SuppressLog => 1, IgnoreError => 1 },
            "getActualParameter",
            "projectList",
            {
                "projectName"  => $projectName,
                "scheduleName" => $scheduleName,
            }
        );

        # Get the value (which can be multi-line) and split it into projects
        if ($success2) {
            my $projectList = $xPath2->findvalue('//value');
            print "\t\tfound projectList: $projectList\n";
            for my $projectName ( split( "\n", $projectList ) ) {

                # Set the project names in a hash to eliminate duplicates
                next unless ($projectName);
                $nonDefaultProjects{$projectName} = 1;
                print "Default schedule - excluding project '$projectName' "
                  . "found in schedule '$scheduleName'\n";
            }
        }
    }
    return ( sort keys %nonDefaultProjects );
}

#-------------------------------------------------------------------------
#  Eliminate from the execution list any Schedules that have an
#  associated running job
#
#  NOTE - Possible settings for job status are
#           pending
#           runnable
#           running
#           completed
#         We want to eliminate all but completed
#-------------------------------------------------------------------------
sub checkforRunningJobs {
    my $self = shift;
    my $nodeset;

    # Get all running (or nearly running) tasks and build a list of them
    # limiting to 100 jobs
    my %runningSchedules;
    my @filterList;
    push(
        @filterList,
        {
            "propertyName" => "status",
            "operator"     => "notEqual",
            "operand1"     => "completed"
        }
    );
    my ( $success, $xPath ) =
      $self->getECSCM()
      ->InvokeCommander( { SuppressLog => 1 },
        "findObjects", "job", { filter => \@filterList } );

    $nodeset = $xPath->find('//job');
    foreach my $node ( $nodeset->get_nodelist ) {
        my $projectName  = $xPath->findvalue( 'projectName',  $node );
        my $scheduleName = $xPath->findvalue( 'scheduleName', $node );
        my $key          = "$projectName/$scheduleName";
        $runningSchedules{$key} = 1;
    }


    # Checking for pipelines
    @filterList = ();
    push(
        @filterList,
        {
            "propertyName" => "completed",
            "operator"     => "notEqual",
            "operand1"     => "1"
        }
    );
    my ( $success, $xPath ) =
      $self->getECSCM()
      ->InvokeCommander( { SuppressLog => 1 },
        "findObjects", "flowRuntime", { filter => \@filterList } );
    $nodeset = $xPath->find('//flowRuntime');


    foreach my $node ( $nodeset->get_nodelist ) {
        my $projectName  = $xPath->findvalue( 'projectName',  $node );
        my $scheduleName = $xPath->findvalue( 'liveSchedule', $node );
        my $key          = "$projectName/$scheduleName";
        # If schedule and pipeline are in different projects
        if ($scheduleName =~ m/\//) {
            $key = $scheduleName;
            $key =~ s/\/projects\///;
            $key =~ s/\/schedules//;
        }
        $runningSchedules{$key} = 1;
    }

    my $jCfg =
      new ElectricSentry::JobCfg( $self->getCmdr(), $ENV{COMMANDER_JOBID}, "",
        "" );
    my %sched = $jCfg->getAllSchedules();

    foreach my $entry ( sort keys %sched ) {
        my $projectName  = $sched{$entry}{project};
        my $scheduleName = $sched{$entry}{schedule};
        my $value        = $sched{$entry}{value};


        # get all args from trigger schedule
        my $tCfg = new ElectricSentry::TriggerCfg( $self->getCmdr(), $projectName, $scheduleName );
        my %config = $tCfg->getAllProps();
        my $runDuplicates = $config{runDuplicates};


        # Only run the check for Schedules that are runnable
        if ( $value eq "SentrySchedule" ) {
            my $key = "$projectName/$scheduleName";
            if ( exists $runningSchedules{$key} ) {

                # Already running - Update the status
                if (!$runDuplicates) {
                    $self->SaveProjectandSchedule( $projectName, $scheduleName, "Running" );
                    print "Checking schedule - $projectName:$scheduleName (running)\n";
                }
                else {
                    print "Checking schedule - $projectName:$scheduleName (running, but will run anyway)\n";
                }
            }
            else {
                print "Checking schedule - $projectName:$scheduleName\n";
            }
        }
    }
}

#-------------------------------------------------------------------------
#  Eliminate from the execution list any Schedules whose sources have not
#  changed since the last attempt
#-------------------------------------------------------------------------
sub checkforNewSources {
    my $self = shift;

    my $jCfg =
      new ElectricSentry::JobCfg( $self->getCmdr(), $ENV{COMMANDER_JOBID}, "",
        "" );
    my %sched = $jCfg->getAllSchedules();

    foreach my $entry ( sort keys %sched ) {
        my $projectName  = $sched{$entry}{project};
        my $scheduleName = $sched{$entry}{schedule};
        my $value        = $sched{$entry}{value};

        # Only run the check for Schedules that are runnable
        if ( $value eq "SentrySchedule" ) {
            print "Checking schedule - $projectName:$scheduleName\n";

            my ( $bNewSource, $bQuietPeriodMet, $scmTag, $previousTag ) = eval {
                $self->CheckOneSchedule( $projectName, $scheduleName );
            };

            if($@) {
                print "Error checking schedule $projectName:$scheduleName: " . $@ . "\n";
            }
            else {

                if ( !defined $bNewSource ) {
                    print "Warning: An ElectricSentry schedule was skipped.\n";
                }
                elsif ( !$bNewSource ) {

                    # No new sources - no change to status
                    print " (nothing new)\n\n";
                }
                elsif ( !$bQuietPeriodMet ) {
                    $self->SaveProjectandSchedule( $projectName, $scheduleName,
                        "WaitingForQuiet" );
                    print " (waiting for quiet time)\n\n";
                }
                else {
                    $self->SaveProjectandSchedule( $projectName, $scheduleName,
                        "Execute\n$scmTag\n$previousTag" );
                    print " (ready to execute)\n\n";
                }
            }
        }
    }
}

#-------------------------------------------------------------------------
#  CheckOneSchedule
#
#  Check the sources tree associated and compare it with the last attempted
#  build to detect changes.  It will determine which SCM system is
#  configured for
#  client view.
#
#   Params:
#       projectName
#       scheduleName
#
#   Returns:
#       A list containg:
#           bNewSource          - 1 if new sources exist
#           bQuietPeriodMet     - 1 if the last change is old enough
#           scmTag              - a string describing the state of the
#                                 sources in the SCM system
#           previousTag         - the previous saved state of the SCM system
#
#-------------------------------------------------------------------------
sub CheckOneSchedule {
    my ( $self, $projectName, $scheduleName ) = @_;

    my $lastAttempted = $self->GetLastAttempted( $projectName, $scheduleName );

    # get all args from trigger schedule
    my $tCfg =
      new ElectricSentry::TriggerCfg( $self->getCmdr(), $projectName,
        $scheduleName );
    my %Args = $tCfg->getAllProps();
    if (!%Args) {
        die "could not get properties on trigger schedule";
    }
    my $scmArgs = \%Args;

    # Determine the SCM plugin and driver for this SCM configuration
    my $scmConfig = $Args{'scmConfig'};
    my ( $scmPlugin, $scmDriver, $scm ) = $self->loadSCMSystem($scmConfig);
    $self->getECSCM->debug("SCM driver=$scmPlugin   Configuration=$scmConfig");

    # add global flags in case the driver needs them
    #
    $scmArgs->{LASTATTEMPTED} = $lastAttempted;

    my $changesetNumber = undef;
    my $changeTimeStamp = undef;

    if ( !defined $scmDriver ) {
        warn "Could not load driver $scmDriver";
    }
    else {

        # get the numeric change tag and the time it last changed
        # (for some SCM's this may be the same value)
        ( $changesetNumber, $changeTimeStamp ) = $scm->getSCMTag($scmArgs);
    }

    #  undef return from getSCMTag signifies an error
    #    either the configuration was bad, or the command returned an error
    if ( !defined $changesetNumber || !defined $changeTimeStamp ) {
        return ( undef, undef, undef, undef );
    }
    else {
        $self->getECSCM->debug("SCMTag=$changesetNumber, $changeTimeStamp");
    }

    #  null values from getSCMTag signifies no new data since the last
    #  attempted.
    #  NOTE - this will only be returned from SOME SCM systems.  Many of them
    #  will ALWAYS report last change info even if there is nothing new
    if ( $changesetNumber eq "" || $changeTimeStamp == 0 ) {
        return ( 0, 0, "", "" );
    }

    #  Check for changeset number not equal to the last attempted
    my $bNewSource      = 0;
    my $bQuietPeriodMet = 0;
    if ( defined $changesetNumber && $changesetNumber ne $lastAttempted ) {

        #  There are new sources
        $bNewSource = 1;

        # Enforce a quiet time if one exists
        $bQuietPeriodMet = 1;
        my $quietTimeMinutes = $Args{'QuietTimeMinutes'};
        $quietTimeMinutes = "5" unless ( length($quietTimeMinutes) > 0 );
        if (   $quietTimeMinutes > 0
            && defined $changeTimeStamp
            && $changeTimeStamp > 0 )
        {

            my $currentTimestamp = time();

            # Check for a test time of the form "2007/05/20 22:33:00"
            if ( defined $ENV{SENTRY_CURRENTTIME} ) {
                $currentTimestamp = str2time( $ENV{SENTRY_CURRENTTIME} );
            }
            my $deltaMinutes =
              int( ( $currentTimestamp - $changeTimeStamp ) / 60 );

   # If delta is less than the quiet time, timeout is not met
   # Also, if delta is negative (allowing for one minute of slop),
   # there is inconsistency in time e.g., different time zones - just call it OK
            if ( $deltaMinutes > -1 && $deltaMinutes < $quietTimeMinutes ) {
                $bQuietPeriodMet = 0;
            }
        }
    }

    return ( $bNewSource, $bQuietPeriodMet, $changesetNumber, $lastAttempted );
}

#-------------------------------------------------------------------------
#  loadSCMSystem
#
#  Based on an SCM configuration,
#       find the plugin and the driver
#       load the driver
#       instantiate the driver, based on the configuraton
#
#  Configuration, driver, and instance will both be cached, so that multiple
#  trigger schedules that use the same configuration, or just the same
#  driver, will only load once.
#
#   Params:
#       scmConfig               - name of the SCM Configuration
#
#   Returns:
#       A list containg:
#           scmPlugin           - name of the plugin
#           scmDriver           - name of the driver
#           scm                 - an instance of the driver based on the config
#
#   Side Effects
#       The driver will be loaded, but only if it is not already loaded
#
#-------------------------------------------------------------------------
%::gSentryLoadedPluginsByConfig = ();
%::gSentryLoadedSCMsByConfig    = ();
%::gSentryLoadedDriversByPlugin = ();

sub loadSCMSystem {
    my ( $self, $scmConfig ) = @_;

    my $scmPlugin = $::gSentryLoadedPluginsByConfig{$scmConfig};
    my $scm       = $::gSentryLoadedSCMsByConfig{$scmConfig};
    my $scmDriver = $::gSentryLoadedDriversByPlugin{$scmPlugin};

    # Return cached version of Configuration
    if ( defined $scmPlugin ) {
        return ( $scmPlugin, $scmDriver, $scm );
    }

    # Look up and cache the plugin name based on ECSCM Configuration properties
    my $cfgs = new ECSCM::Base::Cfg( $self->getCmdr(), $scmConfig );
    $scmPlugin = $cfgs->getSCMPluginName();
    $::gSentryLoadedPluginsByConfig{$scmConfig} = $scmPlugin;
    $scmDriver = $::gSentryLoadedDriversByPlugin{$scmPlugin};

    # Create and cache the Driver if not cached
    if ( !defined $scmDriver ) {

        # Load and cache the driver for this SCM
        if ( $ENV{SENTRY_DRIVERISPRELOADED} ) {
            $scmDriver = $scmPlugin;
            $scmDriver =~ s/-/\:\:/;
            $scmDriver .= "::Driver";
            print "Test load of $scmDriver\n";
        }
        else {
            $scmDriver = $self->getECSCM()->load_driver("$scmPlugin");
        }
        $::gSentryLoadedDriversByPlugin{$scmPlugin} = $scmDriver;
    }

    # init and cache the SCM driver based on this Configuration
    my $scm = $scmDriver->new( $self->getCmdr(), $scmConfig );
    $::gSentryLoadedSCMsByConfig{$scmConfig} = $scm;

    return ( $scmPlugin, $scmDriver, $scm );

}


sub executeSchedule {
    my ($self, $projectName, $scheduleName) = @_;

    my $general = { SuppressLog => 1, IgnoreError => 1 };
    my ($success, $xPath, $errMsg);
    my $schedule = $self->getCmdr()->getSchedule({projectName => $projectName, scheduleName => $scheduleName});
    my $procedureName = $schedule->findvalue('//procedureName')->string_value();
    if ($procedureName) {
        ($success, $xPath, $errMsg) = $self->getECSCM()->InvokeCommander(
            $general,
            'runProcedure',
            $projectName, {scheduleName => $scheduleName}
        );
        return ($success, $xPath, $errMsg, 'job');
    }

    my $pipelineName = $schedule->findvalue('//pipelineName')->string_value();
    if ($pipelineName) {
        ($success, $xPath, $errMsg) = $self->getECSCM()->InvokeCommander(
            $general,
            'runPipeline',
            $projectName, {
                scheduleName => $scheduleName,
                pipelineName => $pipelineName,
            }
        );
        return ($success, $xPath, $errMsg, 'pipeline');
    }

    my $releaseName = $schedule->findvalue('//releaseName')->string_value();
    if ($releaseName) {
        ($success, $xPath, $errMsg) = $self->getECSCM()->InvokeCommander(
            $general,
            'startRelease',
            $projectName, {
                scheduleName => $scheduleName,
                releaseName  => $releaseName,
            }
        );
        return ($success, $xPath, $errMsg, 'release');
    }
    return (0, undef, "Cannot run schedule $scheduleName of project $projectName: neither procedure name nor pipeline name nor release name were found in the schedule");
}

#-------------------------------------------------------------------------
#  Execute any Schedules that need running
#-------------------------------------------------------------------------
sub executeProcedures {
    my $self         = shift;
    my $readyCount   = 0;
    my $startedCount = 0;
    my $exitCode     = 0;

    my $jCfg =
      new ElectricSentry::JobCfg( $self->getCmdr(), $ENV{COMMANDER_JOBID}, "",
        "" );
    my %sched = $jCfg->getAllSchedules();

    foreach my $entry ( sort keys %sched ) {
        my $projectName  = $sched{$entry}{project};
        my $scheduleName = $sched{$entry}{schedule};
        my $value        = $sched{$entry}{value};

        # Execute the Schedules that are runnable
        if ( $value =~ /^Execute\n(.*)\n(.*)/ ) {
            my $snapshot         = $1;
            my $previousSnapshot = $2;

            #  Save the Snapshot first, so that the procedure can access it
            $self->SetLastAttempted( $projectName, $scheduleName, $snapshot );

            # Run the procedure and check the result
            $readyCount++;
            my ($success, $xPath, $errMsg, $what) = $self->executeSchedule($projectName, $scheduleName);
            if ($success) {
                print "ElectricSentry has started a $what based on the "
                  . "'$scheduleName' schedule in the "
                  . "'$projectName' project.\n";
                $startedCount++;
            }
            else {

                # Show an error
                print "ElectricSentry has encountered an error executing the "
                  . "'$scheduleName' schedule in the "
                  . "'$projectName' project.\n";

                my $messageOnly;
                if ($xPath) {
                    $messageOnly = $xPath->findvalue('//responses/error/message');
                }

                my $printableErrMsg = $messageOnly;
                $printableErrMsg = $errMsg unless ($printableErrMsg);
                chomp($printableErrMsg);
                $printableErrMsg =~ s/\n/\n         : /g;
                print "    Error: $printableErrMsg\n";

                # Reset the snapshot so that it will be run again
                $self->SetLastAttempted( $projectName, $scheduleName,
                    $previousSnapshot );

                # Indicate an error
                $exitCode = 10;
            }
        }
    }
    if ($startedCount) {
        ## can this be stored using JobCfg?
        $self->getECSCM()->InvokeCommander(
            { SuppressLog => 1 }, "incrementProperty",
            "/myJob/NumberOfJobsStarted", $startedCount,
            { "jobStepId" => $ENV{COMMANDER_JOBSTEPID} }
        );
    }
    if ( $readyCount == 0 ) {
        print "ElectricSentry did not start any procedures.\n";
    }
    exit $exitCode if ($exitCode);
}

#-------------------------------------------------------------------------
#   SetLastAttempted
#
#       An internal function to set/update the last attempted snapshot
#       for a specified trigger schedule
#
# Results:
#      None
#
# Side Effects:
#       A property is set in Commander
#
#
# Arguments:
#      projectName      -   name of the project that contains the schedule
#      scheduleName     -   name of the trigger schedule
#      snapshot         -   data to be stored for the schedul
#-------------------------------------------------------------------------
sub SetLastAttempted {
    my ( $self, $projectName, $scheduleName, $snapshot ) = @_;
    my ( $sentryProjectName, $sentryScheduleName ) =
      $self->ECSentryGetProjectAndScheduleNames();

#print "setting last attempted to [$snapshot]\n";
#print "[$sentryProjectName] [$sentryScheduleName] [$projectName] [$scheduleName]\n";

    my $cfg = new ElectricSentry::ScheduleCfg(
        $self->getCmdr(), $sentryProjectName, $sentryScheduleName,
        $projectName,     $scheduleName
    );

    # Set up quiet time from the schedule
    my $last = $cfg->setLastAttempted("$snapshot");
}

#-------------------------------------------------------------------------
#   GetLastAttempted
#
#       An internal function to get the last attempted snapshot
#       for a specified trigger schedule
#
# Results:
#       lastAttempted - the string that was last set for the specified schedule
#
# Arguments:
#      projectName      -   name of the project that contains the schedule
#      scheduleName     -   name of the trigger schedule
#
#-------------------------------------------------------------------------
sub GetLastAttempted {
    my ( $self, $projectName, $scheduleName ) = @_;

    my ( $sentryProjectName, $sentryScheduleName ) =
      $self->ECSentryGetProjectAndScheduleNames();
    my $cfg = new ElectricSentry::ScheduleCfg(
        $self->getCmdr(), $sentryProjectName, $sentryScheduleName,
        $projectName,     $scheduleName
    );

    # Set up quiet time from the schedule
    my $last = $cfg->getLastAttempted();
    return ($last);
}

#-------------------------------------------------------------------------
# Cleanup
#-------------------------------------------------------------------------
sub cleanup {
    my $self = shift;
    my ( $sentryProjectName, $sentryScheduleName, $sentryProcedureName ) =
      $self->ECSentryGetProjectAndScheduleNames();

    # Save all jobs or just error jobs if flag is set
    my $tCfg =
      new ElectricSentry::GlobalCfg( $self->getCmdr(), $sentryProjectName,
        $sentryScheduleName );

    my $saveJobs = $tCfg->getSaveJobs();
    $saveJobs = lc($saveJobs);
    if ( $saveJobs eq "1" || $saveJobs eq "true" ) {
        return;
    }

    # Check for the OS Type
    my $osIsWindows = $^O =~ /MSWin/;

    #  Find all previous runs of this job
    my @filterList;
    push(
        @filterList,
        {
            "propertyName" => "projectName",
            "operator"     => "equals",
            "operand1"     => "$sentryProjectName"
        }
    );
    push(
        @filterList,
        {
            "propertyName" => "procedureName",
            "operator"     => "equals",
            "operand1"     => "$sentryProcedureName"
        }
    );
    push(
        @filterList,
        {
            "propertyName" => "status",
            "operator"     => "equals",
            "operand1"     => "completed"
        }
    );

  # Delete only the jobs that this SCHEDULE started (unless deleteAll specified)
    if ( $saveJobs !~ /deleteall/ ) {
        push(
            @filterList,
            {
                "propertyName" => "scheduleName",
                "operator"     => "equals",
                "operand1"     => "$sentryScheduleName"
            }
        );
    }

    # Save error jobs if requested
    if ( $saveJobs =~ /error/ ) {
        push(
            @filterList,
            {
                "propertyName" => "outcome",
                "operator"     => "notEqual",
                "operand1"     => "error"
            }
        );
    }

    # Run the Query
    my ( $success, $xPath ) =
      $self->getECSCM()->InvokeCommander( { SuppressLog => 1 },
        "findObjects", "job", { numObjects => "500", filter => \@filterList } );

    # Loop over all returned jobs
    my $nodeset = $xPath->find('//job');
    foreach my $node ( $nodeset->get_nodelist ) {

        #  Find the workspaces (there can be more than one if some steps
        #  were configured to use a different workspace
        my $jobId   = $xPath->findvalue( 'jobId',   $node );
        my $jobName = $xPath->findvalue( 'jobName', $node );
        my ( $success, $xPath ) =
          $self->getECSCM()
          ->InvokeCommander( { SuppressLog => 1 }, "getJobInfo", $jobId );
        my $wsNodeset = $xPath->find('//job/workspace');
        foreach my $wsNode ( $wsNodeset->get_nodelist ) {

            my $workspace;
            if ($osIsWindows) {
                $workspace = $xPath->findvalue( './winUNC', $wsNode );
                $workspace =~ s/\/\//\\\\/g;
            }
            else {
                $workspace = $xPath->findvalue( './unix', $wsNode );
            }

            # Delete the workspace (after checking its name as a sanity test)
            # look for "job_[nnn|UUID]"
            if ( $workspace =~ /[-_][\d]+$|[-_][0-9a-f]{8}(?:-[0-9a-f]{4}){4}[0-9a-f]{8}$/ ) {
                use File::Path;

                rmtree( [$workspace] ) unless ( $ENV{SENTRY_SIMULATE_DELETE} );
                print "Deleted workspace - $workspace\n";
            }
        }

        # Delete the job

        my ( $success, $xPath ) =
          $self->getECSCM()
          ->InvokeCommander( { SuppressLog => 1 }, "deleteJob", $jobId );
        print "Deleted job - $jobName\n";
    }
}

#-------------------------------------------------------------------------
#  CheckQuietTime
#
#
#   Params:
#       quietTimeMinutes
#       changeTimeString
#
#   Returns:
#       Boolean     -   true if quiet time is met
#
#-------------------------------------------------------------------------
sub CheckQuietTime($$) {
    my $self             = shift;
    my $quietTimeMinutes = shift;
    my $changeTimeString = shift;

    my $bQuietPeriodMet = 1;
    if ( length $quietTimeMinutes ) {
        my $changeTimestamp  = str2time($changeTimeString);
        my $currentTimestamp = time();

        # Check for a test time of the form "2007/05/20 22:33:00"

        if ( defined $ENV{SENTRY_CURRENTTIME} ) {
            $currentTimestamp = str2time( $ENV{SENTRY_CURRENTTIME} );
        }

   # If delta is less than the quiet time, timeout is not met
   # Also, if delta is negative (allowing for one minute of slop),
   # there is inconsistency in time e.g., different time zones - just call it OK
        my $deltaMinutes = int( ( $currentTimestamp - $changeTimestamp ) / 60 );
        if ( $deltaMinutes > -1 && $deltaMinutes < $quietTimeMinutes ) {
            $bQuietPeriodMet = 0;
        }
    }

    return $bQuietPeriodMet;
}

#-------------------------------------------------------------------------
#  GetQuietTimeMinutes
#
#   Params:
#       sentryProjectName
#       sentryScheduleName
#
#   Returns:
#       Quiet time in minutes
#-------------------------------------------------------------------------
my $gCachedQuietTimeMinutes = -1;

sub GetQuietTimeMinutes($$;) {
    my ( $self, $sentryProjectName, $sentryScheduleName ) = @_;

    if ( $gCachedQuietTimeMinutes == -1 ) {
        my $cfg =
          new ElectricSentry::GlobalCfg( $self->getCmdr(),
            "/projects/$sentryProjectName/schedules/$sentryScheduleName" );

        # Set up quiet time from the schedule
        $gCachedQuietTimeMinutes = $cfg->getQuietTime();
        if ( !defined $gCachedQuietTimeMinutes
            || $gCachedQuietTimeMinutes eq "" )
        {
            $gCachedQuietTimeMinutes = 5;
        }
    }

    return ($gCachedQuietTimeMinutes);
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
#
#  Notes
#       scheduleName will be an empty string if the current job was not
#       launched from a Schedule
#
#-------------------------------------------------------------------------
my $gCachedScheduleName  = "";
my $gCachedProjectName   = "";
my $gCachedProcedureName = "";

sub ECSentryGetProjectAndScheduleNames {
    my $self = shift;
    if ( $gCachedScheduleName eq "" ) {

        # Call Commander to get info about the current job
        my ( $success, $xPath ) =
          $self->getECSCM()->InvokeCommander( { SuppressLog => 1 },
            "getJobInfo", $ENV{COMMANDER_JOBID} );

        # Find the schedule name in the properties
        $gCachedScheduleName  = $xPath->findvalue('//scheduleName');
        $gCachedProjectName   = $xPath->findvalue('//projectName');
        $gCachedProcedureName = $xPath->findvalue('//procedureName');
    }

    return ( $gCachedProjectName, $gCachedScheduleName, $gCachedProcedureName );

}

#-------------------------------------------------------------------------
#   A private function used to maintain a set of schedules that are set up for Sentry
#
#   Params:
#       projectName
#       scheduleName
#       value
#-------------------------------------------------------------------------

sub SaveProjectandSchedule {
    my ( $self, $projectName, $scheduleName, $value ) = @_;

    my $jCfg = new ElectricSentry::JobCfg(
        $self->getCmdr(), $ENV{COMMANDER_JOBID},
        $projectName,     $scheduleName
    );
    $jCfg->setState("$value");
}

#-------------------------------------------------------------------------
#  PrintEnv - print the environment
#
#-------------------------------------------------------------------------
sub PrintEnv {

    my $self = shift;
    my $key;
    foreach $key ( sort keys %ENV ) {
        print "env: $key  =  $ENV{$key}\n";
    }
}

1;
