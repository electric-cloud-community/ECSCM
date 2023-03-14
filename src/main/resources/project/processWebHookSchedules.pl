use strict;
use warnings;
use ElectricCommander;
use JSON;
use Data::Dumper;
use subs qw(info debug error);
use Digest::MD5 qw(md5_hex);
use File::Path;
use Encode qw(encode);

print 'Using Plugin @PLUGIN_NAME@' . "\n";

my $ec = ElectricCommander->new;
my $webhookData = $ec->getProperty('ec_webhookData')->findvalue('//value')->string_value;
my $rawSearchParams = $ec->getProperty('ec_webhookSchedulesSearchParams')->findvalue('//value')->string_value;

eval {
    my $processor = EC::ECSCM::ProcessWebHookSchedules->new(
        ec => $ec,
        webhookData => $webhookData,
        rawSearchParams => $rawSearchParams,
    );
    $processor->processSchedules();
    1;
} or do {
    my $err = $@;
    print "[ERROR] $err\n";
    $ec->setProperty('/myJobStep/summary', "Error occured: $err");
    exit 1;
};


package EC::ECSCM::ProcessWebHookSchedules;
use strict;
use warnings;
use JSON;
use Digest::MD5 qw(md5_hex);
use File::Path;
use Encode qw(encode);


sub new {
    my ($class, %params) = @_;

    my $self = { %params };
    $self->{webhookData} or die 'No webhook data is provided';
    $self->{rawSearchParams} or die 'No schedules search params are provided';
    $self->{ec} or die 'No ec object is provided';
    # my $webhookData = $ec->getProperty('ec_webhookData')->findvalue('//value')->string_value;
    # my $rawSearchParams = $ec->getProperty('ec_webhookSchedulesSearchParams')->findvalue('//value')->string_value;
    # ec_webhookPayload

    return bless $self, $class;
}

sub ec {
    return shift->{ec};
}


sub processSchedules {
    my ($self) = @_;

    $self->logger->info("WebHook Data: " . prettyJson(decode_json($self->{webhookData})));

    my $searchParams = eval { decode_json($self->{rawSearchParams}) };
    if ($@) {
        die "ec_webhookSchedulesSearchParams must be a valid JSON: $@";
    }
    $self->logger->info("Schedules Search Parameters: " . prettyJson($searchParams));
    my $schedules = $self->findSchedules();

    unless(@$schedules) {
        $self->logger->info("No schedules were found for the provided search parameters");
    }
    for my $schedule (@$schedules) {
        eval {
            $schedule->launch($self->{webhookData});
            1;
        } or do {
            my $err = $@;
            $self->logger->error("Failed to launch schedule " . $schedule->name . ", error: $err");
        };
    }

    unless ($self->{skipCleanup}) {
        $self->cleanup();
    }
}


sub findSchedules {
    my ($self) = @_;

    my $chunkSize = 10;
    my $start = 0;

    my $chunk;
    my $hasMore = 1;
    my $retval = [];
    my $counter = 0;
    my $searchParams = decode_json($self->{rawSearchParams});

    while($hasMore) {
        $chunk = $ec->findObjects('schedule', {
            numObjects => $chunkSize,
            firstResult => $start,
        });
        $start += $chunkSize;
        $hasMore = 0;
        for my $rawSchedule ($chunk->findnodes('//schedule')) {
            $hasMore = 1;
            $counter++;
            my $schedule = EC::ECSCM::Schedule->new($rawSchedule, $self->ec);


            unless($schedule->isWebhookSchedule()) {
                $self->logger->debug("Not a webhook schedule: " . $schedule->name);
                next;
            }

            if ($schedule->matches($searchParams)) {
                push @$retval, $schedule;
            }
            else {
                $self->logger->info($schedule->name . ' does not match search parameters');
            }
        }
    }
    return $retval;
}

sub logger {
    return EC::Plugin::Logger->getInstance();
}


sub prettyJson {
    my ($object) = @_;

    return JSON->new->utf8->pretty->encode($object);
}


sub cleanup {
    my ($self) = @_;

    my @filters = ();

    push @filters , {
        propertyName => 'projectName',
        operator => 'equals',
        operand1 => '@PLUGIN_NAME@'
    };

    push @filters, {
        propertyName => 'procedureName',
        operator => 'equals',
        operand1 => '$[/myProcedure/procedureName]'
    };

    push @filters, {
        propertyName => 'status',
        operator => 'equals',
        operand1 => 'completed'
    };

    # Only successfull runs
    push @filters, {
        propertyName => 'outcome',
        operator => 'equals',
        operand1 => 'success'
    };

    my $jobs = $self->ec()->findObjects('job', {numObjects => '500', filter => \@filters});
    for my $job ($jobs->findnodes('//job')) {
        my $jobId = $job->findvalue('jobId')->string_value;
        $self->ec()->deleteJob({jobId => $jobId});
        my $jobName = $job->findvalue('jobName')->string_value;
        $self->deleteWorkspace($job);
        $self->logger->info("Deleted Job: $jobName");
    }
}

sub deleteWorkspace {
    my ($self, $job) = @_;

    my $jobId = $job->findvalue('jobId')->string_value;
    my $details = $self->ec()->getJobInfo({jobId => $jobId});

    my $osIsWindows = $^O =~ /MSWin/;
    for my $ws ($details->findnodes('//job/workspace')) {
        my $workspace;
        if ($osIsWindows) {
            $workspace = $ws->findvalue('./winUNC')->string_value;
            $workspace =~ s/\/\//\\\\/g;
        }
        else {
            $workspace = $ws->findvalue('./unix')->string_value;
        }
        if ( $workspace =~ /[-_][\d]+$|[-_][0-9a-f]{8}(?:-[0-9a-f]{4}){4}[0-9a-f]{8}$/ ) {
            rmtree( [$workspace] ) unless ( $ENV{SENTRY_SIMULATE_DELETE} );
            $self->logger->info("Deleted workspace - $workspace");
        }
    }
}



1;


package EC::ECSCM::Schedule;
use strict;
use warnings;
use DateTime;


sub new {
    my ($class, $xpath, $ec) = @_;

    $xpath or die 'No xpath is provided';
    my $scheduleName = $xpath->findvalue('scheduleName')->string_value;
    my $projectName = $xpath->findvalue('projectName')->string_value;

    my $self = {
        scheduleName => $scheduleName,
        projectName => $projectName,
        ec => $ec,
        raw => $xpath,
        procedureName => $xpath->findvalue('procedureName')->string_value,
        pipelineName => $xpath->findvalue('pipelineName')->string_value,
        releaseName => $xpath->findvalue('releaseName')->string_value,
    };

    return bless $self, $class;
}

sub scheduleName { return shift->{scheduleName} }

sub projectName { return shift->{projectName} }

sub procedureName { return shift->{procedureName} }

sub pipelineName { return shift->{pipelineName} }

sub releaseName { return shift->{releaseName} }

sub name {
    my ($self) = @_;
    return $self->projectName . ':' . $self->scheduleName;
}

sub ec {
    return shift->{ec};
}

sub isWebhookSchedule {
    my ($self) = @_;

    my $webhook = 0;
    eval {
        my $xpath = $self->ec()->getProperty({
            propertyName => 'ec_triggerType',
            scheduleName => $self->scheduleName,
            projectName => $self->projectName,
        });

        if ($xpath->findvalue('//value')->string_value eq 'webhook') {
            $webhook = 1;
        }
    };
    return $webhook;
}


# We are expecting to have a set of properties on schedule matching a set of properties passed by webhook
# E.g. webhook launches the procedure with searchParams = {param1: 'value', param2: 'value2'}
# We are looking for the schedules with ec_customEditorData/param1 == 'value' AND ec_customEditorData/param2 = 'value2'
# A wildcard * can be used instead of value
sub matches {
    my ($self, $searchParams) = @_;

    unless(scalar keys %$searchParams) {
        die "No search parameters are provided";
    }
    my $projectName = $self->projectName;
    my $scheduleName = $self->scheduleName;

    my $scheduleParams = {};
    eval {
        my $xpath = $self->ec->getProperties({
            path => "ec_customEditorData",
            projectName => $projectName,
            scheduleName => $scheduleName,
        });
        for my $node ($xpath->findnodes('//property')) {
            my $name = $node->findvalue('propertyName')->string_value;
            my $value = $node->findvalue('value')->string_value;
            $scheduleParams->{$name} = $value;
        }
        1;
    } or do {
        $self->logger->error("Cannot get schedule parameters for $projectName:$scheduleName: $@");
    };

    $self->logger->debug("Schedule " . $self->name . " parameters: " . JSON->new->utf8->pretty->encode($scheduleParams));

    unless($scheduleParams) {
        return 0;
    }

    for my $paramName (keys %$searchParams) {
        my $paramValue = $searchParams->{$paramName};
        if (ref $paramValue) {
            $self->logger->debug("Param value object is not suported yet");
            next;
        }
        my $scheduleParameter = $scheduleParams->{$paramName};
        unless($scheduleParameter) {
            $self->logger->debug("Schedule " . $self->name . ' does not have a parameter ' . $paramName);
            return 0;
        }
        if ($scheduleParameter ne '*' && $scheduleParameter ne $paramValue) {
            $self->logger->debug('Schedule ' . $self->name . " does not match $scheduleParameter -> $paramValue");
            return 0;
        }
    }

    my $triggerFlag = $scheduleParams->{TriggerFlag};
    unless(defined $triggerFlag) {
        $self->logger->error("Schedule " . $self->name . ' does not have TriggerFlag field');
        return 0;
    }

    if ($triggerFlag == 0) {
        $self->logger->info('Schedule ' . $self->name . ' is disabled');
        return 0;
    }

    if ($triggerFlag != 3) {
        $self->logger->error('Schedule ' . $self->name . " is invalid: TriggerFlag = $triggerFlag");
        return 0;
    }

    $self->logger->info("Schedule " . $self->name . " matches the webhook");
    return 1;
}


sub getParameter {
    my ($self, $paramName, $default) = @_;

    my $retval;
    eval {
        my $xpath = $self->ec->getProperty({
            propertyName => "ec_customEditorData/$paramName",
            projectName => $self->projectName,
            scheduleName => $self->scheduleName,
        });
        $retval = $xpath->findvalue('//value')->string_value;
        if ($retval =~ /^\d+$/) {
            $retval += 0;
        }
    };
    unless(defined $retval) {
        $retval = $default;
    }
    return $retval;
}

sub alreadyRunning {
    my ($self) = @_;

    my @filterList = ();
    push(
        @filterList,
        {
            "propertyName" => "status",
            "operator"     => "notEqual",
            "operand1"     => "completed"
        },
        {
            propertyName => 'projectName',
            operator => 'equals',
            operand1 => $self->projectName,
        },
        {
            propertyName => 'scheduleName',
            operator => 'equals',
            operand1 => $self->scheduleName,
        }
    );
    my $xpath = $self->ec()->findObjects('job', {filter => \@filterList});
    if ($xpath->findnodes('//job')) {
        return 1;
    }

    @filterList = ();
    push(
        @filterList,
        {
            "propertyName" => "completed",
            "operator"     => "notEqual",
            "operand1"     => "1"
        },
        {
            propertyName => 'projectName',
            operator => 'equals',
            operand1 => $self->projectName,
        },
        {
            propertyName => 'liveSchedule',
            operator => 'equals',
            operand1 => $self->scheduleName,
        }
    );

    $xpath = $self->ec->findObjects('flowRuntime', {filter => \@filterList});
    if ($xpath->findnodes('//flowRuntime')) {
        return 1;
    }

    return 0;
}


sub ensureProject {
    my ($self, $projectName, $description) = @_;

    eval {
        $self->ec->createProject({projectName => $projectName, description => $description});
        $self->logger->info("Project $projectName has been created");
        1;
    };
}

sub queueLaunch {
    my ($self, $quietTimeMinutes, $webhookData) = @_;

    # Creating one-time schedule to be launched in quietTimeMinutes from now
    # Or updating if there is already one
    my $scheduleProject = 'Electric Cloud';
    my $projectDescription = 'Electric Cloud Procedures';
    $self->ensureProject($scheduleProject, $projectDescription);

    my $scheduleName = $self->projectName . '-' . $self->scheduleName . '-Webhook-Queue';
    my $exists = 0;
    my $attempts = 0;
    eval {
        my $xpath = $self->ec->getSchedule({
            projectName => $scheduleProject,
            scheduleName => $scheduleName
        });
        $exists = 1;
    };

    my $timeZone = 'America/Los_Angeles';
    my $now = DateTime->now(time_zone => $timeZone);
    my $beginDate = $now->ymd;
    my $endDate = $now->add(days => 1)->ymd;

    my $startTime = $now->add(minutes => $quietTimeMinutes)->strftime('%H:%M');

    my $actualParameter = [
        {actualParameterName => 'ec_webhookData', value => $webhookData},
        {actualParameterName => 'ec_scheduleName', value => $self->scheduleName},
        {actualParameterName => 'ec_projectName', value => $self->projectName},
        # {actualParameterName => 'ec_webhookPayload', value => 'todo'}, # maybe will be needed in future
    ];


    if ($exists) {
        my $scheduleProperties = $self->ec->getProperties({
            projectName => $scheduleProject,
            scheduleName => $scheduleName,
        });

        my $props = {};
        for my $node ($scheduleProperties->findnodes('//property')) {
            $props->{ $node->findvalue('propertyName')->string_value } = $node->findvalue('value')->string_value;
        }
        $attempts = $props->{ec_attempts} || 0;
        if ($props->{ec_launched} && $props->{ec_launched} eq 'true') {
            # If it was launched, we don't count it
            $attempts = 0;
        }

        $self->ec->deleteSchedule({
            projectName => $scheduleProject,
            scheduleName => $scheduleName,
        });
    }

    my $maxAttempts = $self->getParameter('ec_maxRetries') || 0;
    if ($maxAttempts && $attempts >= $maxAttempts) {
        $self->logger->info("Max attempts for queue reached, launching anyway");
        return 0;
    }

    # Creating one-time schedule (will be cleaned later by the procedure ProcessQueuedWebhook)
    $self->ec->createSchedule({
        projectName => $scheduleProject,
        scheduleName => $scheduleName,
        beginDate => $beginDate,
        endDate => $endDate,
        startTime => $startTime,
        procedureName => '/plugins/@PLUGIN_KEY@/project/procedures/ProcessQueuedWebhook',
        timeZone => $timeZone,
        actualParameter => $actualParameter,
        description => 'Queued webhook launch, created by $[/myProject/projectName]:$[/myProcedure/procedureName]',
    });

    $attempts ++;
    $self->ec->setProperty({
        propertyName => 'ec_attempts',
        projectName => $scheduleProject,
        scheduleName => $scheduleName,
        value => $attempts
    });
    $self->logger->info("Created queued launch for schedule " . $self->name . ", will be launched at $startTime $timeZone, attempt $attempts");
    return 1;
}

sub isFalse {
    my $val = shift;

    return $val eq '0' || $val eq 'false';
}

sub isTrue {
    return !isFalse(shift);
}

sub launch {
    my ($self, $webhookData) = @_;

    my $projectName = $self->projectName;
    my $procedureName = $self->procedureName;
    my $scheduleName = $self->scheduleName;
    my $pipelineName = $self->pipelineName;
    my $releaseName = $self->releaseName;

    # Quiet Time
    # Seconds
    my $quietTime = $self->getParameter('ec_quietTime') || 0;
    my $queued = 0;

    if ($quietTime) {
        $queued = $self->queueLaunch($quietTime, $webhookData);
    }
    else {
        # Now two options are mutually exclusive
        # Check for running jobs
        my $runDuplicates = $self->getParameter('ec_runDuplicates', '1');
        if(isFalse($runDuplicates) && $self->alreadyRunning()) {
            $self->logger->info("The schedule " . $self->name . ' is already running, will not run again');
            return;
        }
    }

    if ($queued) {
        $self->logger->info("The schedule has been postponed for $quietTime minutes");
        return;
    }

    my $result;
    my $what;
    if ($procedureName) {
        $what = 'procedure';
        $result = $self->ec()->runProcedure({
            projectName => $projectName,
            webhookData => $webhookData,
            scheduleName => $scheduleName
        });
    }
    elsif ($releaseName) {
        # Schedule lives in the same project
        $what = 'release';
        $result = $self->ec()->startRelease({
            projectName => $projectName,
            releaseName => $releaseName,
            scheduleName => $scheduleName,
            webhookData => $webhookData,
        });
    }
    elsif($pipelineName) {
        $what = 'pipeline';
        $result = $self->ec()->runPipeline({
            projectName => $projectName,
            pipelineName => $pipelineName,
            scheduleName => $scheduleName,
            webhookData => $webhookData,
        });
    }
    else {
        die "Schedule $projectName:$scheduleName lacks procedureName, pipelineName and releaseName";
    }
    $self->logger->info("Launched $what from the schedule $projectName:$scheduleName");
}


sub logger {
    return EC::Plugin::Logger->getInstance();
}



1;


package EC::Plugin::Logger;

use strict;
use warnings;
use Data::Dumper;

use constant {
    ERROR => -1,
    INFO => 0,
    DEBUG => 1,
    TRACE => 2,
};

my $logger;

sub getInstance {
    my ($class, $level, %param) = @_;
    unless($logger) {
        $level ||= 0;
        my $self = {%param, level => $level};
        $logger = bless $self,$class;
    }
    return $logger;
}

sub info {
    my ($self, @messages) = @_;
    $self->_log(INFO, @messages);
}

sub debug {
    my ($self, @messages) = @_;
    $self->_log(DEBUG, '[DEBUG]', @messages);
}

sub error {
    my ($self, @messages) = @_;
    $self->_log(ERROR, '[ERROR]', @messages);
}

sub trace {
    my ($self, @messages) = @_;
    $self->_log(TRACE, '[TRACE]', @messages);
}

sub level {
    my ($self, $level) = @_;

    if (defined $level) {
        $self->{level} = $level;
    }
    else {
        return $self->{level};
    }
}

sub log_to_property {
    my ($self, $prop) = @_;

    if (defined $prop) {
        $self->{log_to_property} = $prop;
    }
    else {
        return $self->{log_to_property};
    }
}


my $length = 40;

sub divider {
    my ($self, $thick) = @_;

    if ($thick) {
        $self->logger->info('=' x $length);
    }
    else {
        $self->logger->info('-' x $length);
    }
}

sub header {
    my ($self, $header, $thick) = @_;

    my $symb = $thick ? '=' : '-';
    $self->logger->info($header);
    $self->logger->info($symb x $length);
}

sub _log {
    my ($self, $level, @messages) = @_;

    return if $level > $self->level;
    my @lines = ();
    for my $message (@messages) {
        if (ref $message) {
            print Dumper($message);
            push @lines, Dumper($message);
        }
        else {
            print "$message\n";
            push @lines, $message;
        }
    }

    if ($self->{log_to_property}) {
        my $prop = $self->{log_to_property};
        my $value = "";
        eval {
            $value = $self->ec->getProperty($prop)->findvalue('//value')->string_value;
            1;
        };
        unshift @lines, split("\n", $value);
        $self->ec->setProperty($prop, join("\n", @lines));
    }
}


sub ec {
    my ($self) = @_;
    unless($self->{ec}) {
        require ElectricCommander;
        my $ec = ElectricCommander->new;
        $self->{ec} = $ec;
    }
    return $self->{ec};
}

1;
