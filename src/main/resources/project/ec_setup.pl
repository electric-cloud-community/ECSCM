
##################################################### !!!WARNING!!! ######################################################
#  This setup sequence contains strange at the first glance logic of enabling/disabling sentry schedule.                 #
#  For example, see: FLOWPLUGIN-3414.                                                                                    #
#  This issue has been created because the behavior that were descrbed in the FLOWPLUGIN-3414 looked like a valid bug.   #
#  But the thing is that it was not. It is happened that we're enabling the schedule at plugin promote/upgrade because   #
#  are disabling the schedule at demote/uninstall.                                                                       #
#  If we just fixing disable/enable we will get into the following situation:                                            #
#  During server upgrade we're installing new plugin. (schedule is not enabled because it was disabled).                 #
#  The worst part about that is we can't distinguish between manual disabling and demote disabling.                      #
#  In case of manual disabling we should not enable it after upgrade. But in case of demoting we should.                 #
#  To distinguish between these 2 scenarios we added new property, that is being created at demote:                      #
#      "/projects/$sentryProject/schedules/$sentrySched/disabledByDemote"                                                #
#  If this property is set to 1, we assume that this schedule has been disabled during demote, so we can                 #
#  safely re-enable it during next upgrade.                                                                              #
#  This behavior is backward-compatible.                                                                                 #
##################################################### !!!WARNING!!! ######################################################
my $sentryProject = 'Electric Cloud';
my $sentrySched = 'ECSCM-SentryMonitor';
my $adminGroup = 'SCMAdmins';
my $disabledByDemotePropertyPath = "/projects/$sentryProject/schedules/$sentrySched/disabledByDemote";


if ($promoteAction eq 'promote') {
    # Register Sentry & preflight publishedCustomTypes
    $batch->setProperty(
        "/server/ec_ui/publishedCustomTypes/schedule/continuousIntegration",
        { value => '$[/plugins/ECSCM/project/scm_ui/publishedCustomTypes/schedule/continuousIntegration]' });

    $batch->setProperty(
        "/server/ec_ui/publishedCustomTypes/step/preflight",
        { value => '$[/plugins/ECSCM/project/scm_ui/publishedCustomTypes/step/preflight]'});

    # Create the sentry monitor schedule in the Electric Cloud project if
    # necessary
    my $query = $commander->newBatch();
    my $project = $query->getProject($sentryProject);
    my $sentrySchedule = $query->getSchedule($sentryProject, $sentrySched);
    local $self->{abortOnError} = 0;

    # get mainClientDriver contents
    my $code = $query->getProperty(
        "/projects/$pluginName/scm_driver/mainClientDriver");
    $query->submit();

    # Create the Electric Cloud project
    if ($query->findvalue($project, 'code') =~ m'^NoSuch.*') {
        $batch->createProject($sentryProject,
            {description => "Electric Cloud Procedures"});
    }
    my $needToEnable = 0;
    eval {
        my $disabledByDemoteProperty = $commander->getProperty($disabledByDemotePropertyPath);
        if ($disabledByDemoteProperty->findvalue("//value")->string_value()) {
            $needToEnable = 1;
        }
        1;
    };

    # Create the monitor schedule
    if ($query->findvalue($sentrySchedule, 'code') =~ m'^NoSuch.*') {
        $batch->createSchedule($sentryProject, $sentrySched, {
            procedureName => '/plugins/ECSCM/project/procedures/ElectricSentry',
            description => "Periodically locate ECSCM sentry schedules to run",
            interval => 5,
            intervalUnits => 'minutes',
            startTime => '07:00',
            stopTime => '23:00',
            timeZone => 'America/Los_Angeles',
            actualParameter => {
                actualParameterName => 'sentryResource',
                value => 'local'
            },
        });
        $needToEnable = 1;
    }
    if ($needToEnable) {
        $batch->modifySchedule($sentryProject, $sentrySched, {
            scheduleDisabled => 0
        });
        eval {
            $batch->deleteProperty($disabledByDemotePropertyPath);
        };
    }
    # Create the SCM admin group if necessary
    my $xpath = $commander->getGroup($adminGroup);
    if ($xpath->findvalue('//code') eq 'NoSuchGroup') {
        $batch->createGroup($adminGroup);
    }

    # Create the Source Control subtab
    $view->add(["Administration", "Source Control"],
               { url => 'pages/ECSCM/configurations' });

    my $driver = $query->findvalue($code,'//value');
    $batch->setProperty( "/server/ec_preflight/mainClientDriver",
        { value => "$driver", expandable => 0});


    # grantPermissionsForServiceAccounts();


} elsif ($promoteAction eq 'demote') {
    # remove publishedCustomTypes
    $batch->deleteProperty(
        "/server/ec_ui/publishedCustomTypes/schedule/continuousIntegration");
    $batch->deleteProperty(
        "/server/ec_ui/publishedCustomTypes/step/preflight");

    # disable sentry
    local $self->{abortOnError} = 0;

    # Now we need to get if schedule is disabled
    # If the schedule is disabled we need to do nothing with disabling.
    my $needToDisable = 1;
    my $xpath = $commander->getSchedule($sentryProject, $sentrySched);
    eval {
        if ($xpath->findvalue('//scheduleDisabled')->string_value()) {
            $needToDisable = 0;
        }
    };
    if ($needToDisable && $xpath->findvalue('//code') eq '') {
        $batch->modifySchedule($sentryProject, $sentrySched, {
            scheduleDisabled => 1
        });
        # now, when sentry has been disabled by demote, we need to add a property
        # to the sentry schedule which will mark it as disabled by demote:
        eval {
            $batch->setProperty($disabledByDemotePropertyPath, 1);
        };
    }
    # remove tab
    $view->remove(["Administration", "Source Control"]);
}

if ($upgradeAction eq 'upgrade') {
    my $query = $commander->newBatch();
    my $types = $query->getProperty(
        "/plugins/$otherPluginName/project/scm_types");
    my $cfgs = $query->getProperty(
        "/plugins/$otherPluginName/project/scm_cfgs");
    my $creds = $query->getCredentials(
        "\$[/plugins/$otherPluginName]");

    # get mainClientDriver contents
    my $code = $query->getProperty(
        "/projects/$pluginName/scm_driver/mainClientDriver");

    local $self->{abortOnError} = 0;
    $query->submit();

    # Copy registered SCM types
    if ($query->findvalue($types,'code') eq '') {

        # Destination must be empty or clone will fail
        $batch->deleteProperty("/plugins/$pluginName/project/scm_types");

        $batch->clone({
            path => "/plugins/$otherPluginName/project/scm_types",
            cloneName => "/plugins/$pluginName/project/scm_types"
        });
    }

    # Copy configurations from $otherPluginName
    if ($query->findvalue($cfgs,'code') eq '') {

        # Destination must be empty or clone will fail
        $batch->deleteProperty("/plugins/$pluginName/project/scm_cfgs");

        $batch->clone({
            path => "/plugins/$otherPluginName/project/scm_cfgs",
            cloneName => "/plugins/$pluginName/project/scm_cfgs"
        });
    }

    # Copy configuration credentials and attach them to the appropriate steps
    my $nodes = $query->find($creds);
    if ($nodes) {
        my @nodes = $nodes->findnodes('credential/credentialName');
        for (@nodes) {
            my $cred = $_->string_value;


            # Destination must be empty or clone will fail
            $batch->deleteCredential("$pluginName","$cred");

            # Clone the credential
            $batch->clone({
                path => "/plugins/$otherPluginName/project/credentials/$cred",
                cloneName => "/plugins/$pluginName/project/credentials/$cred"
            });

            # Make sure the credential has an ACL entry for the new project principal
            my $xpath = $commander->getAclEntry("user", "project: $pluginName", {
                projectName => $otherPluginName,
                credentialName => $cred
            });
            if ($xpath->findvalue('//code') eq 'NoSuchAclEntry') {
                $batch->deleteAclEntry("user", "project: $otherPluginName", {
                    projectName => $pluginName,
                    credentialName => $cred
                });
                $batch->createAclEntry("user", "project: $pluginName", {
                    projectName => $pluginName,
                    credentialName => $cred,
                    readPrivilege => "allow",
                    modifyPrivilege => "allow",
                    executePrivilege => "allow",
                    changePermissionsPrivilege => "allow"
                });
            }

            # Attach the credential to the appropriate steps
            $batch->attachCredential("\$[/plugins/$pluginName/project]", $cred, {
                procedureName => 'RunMethod',
                stepName => 'runMethod'
            });
            $batch->attachCredential("\$[/plugins/$pluginName/project]", $cred, {
                procedureName => 'ElectricSentry',
                stepName => 'Check for New Sources'
            });
        }
    }

    # update mainClientDriver installed with server
    my $driver = $query->findvalue($code,'//value');
    $batch->setProperty( "/server/ec_preflight/mainClientDriver",
        { value => "$driver", expandable => 0});
}

# Data that drives the create step picker registration for this plugin.
my %cicheckout = (
    label       => "Continuous Integration - Checkout",
    procedure   => "CICheckout",
    description => "Checkout code using a Continuous Integration (CI) configuration.",
    category    => "Source Code Management"
);
@::createStepPickerSteps = (\%cicheckout);


sub grantPermissionsForServiceAccounts  {
    # TODO check version
    my $xpath = $commander->findObjects('serviceAccount');
    for my $svc ($xpath->findnodes('//serviceAccount')) {
        my $name = $svc->findvalue('serviceAccountName')->string_value;
        # TODO filter?
        $batch->createAclEntry({
            principalType => 'serviceAccount',
            projectName => $pluginName,
            procedureName => 'ProcessWebHookSchedules',
            executePrivilege => 'allow',
            principalName => $name,
            objectType => 'procedure',
        });
    }
}
