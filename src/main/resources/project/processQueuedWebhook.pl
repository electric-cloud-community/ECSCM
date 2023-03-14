use strict;
use warnings;
use ElectricCommander;

my $ec = ElectricCommander->new;
my $processor = EC::ECSCM::ProcessQueuedWebhook->new($ec);
eval {
    $processor->processQueue();
    1;
} or do {
    my $err = $@;
    print "[ERROR] $err\n";
    $ec->setProperty('/myJobStep/summary', "Error occured: $err");
    exit 1;
};


package EC::ECSCM::ProcessQueuedWebhook;
use strict;
use warnings;
use File::Path;


sub new {
    my ($class, $ec) = @_;

    my $self = {ec => $ec};
    return bless $self, $class;
}

sub ec {
    shift->{ec};
}

sub processQueue {
    my ($self) = @_;

    my $projectName = $self->getParameter('projectName');
    my $scheduleName = $self->getParameter('scheduleName');
    my $webhookData = $self->getParameter('webhookData');

    $self->launch($projectName, $scheduleName, $webhookData);
    $self->ec->setProperty('/mySchedule/ec_launched', 'true');
    $self->cleanup();
}


sub getParameter {
    my ($self, $paramName) = @_;

    return $self->ec->getProperty("ec_$paramName")->findvalue('//value')->string_value;
}


sub launch {
    my ($self, $projectName, $scheduleName, $webhookData) = @_;

    my $schedule = $self->ec->getSchedule({
        projectName => $projectName,
        scheduleName => $scheduleName
    });

    my $procedureName = $schedule->findvalue('//procedureName')->string_value;
    my $pipelineName = $schedule->findvalue('//pipelineName')->string_value;
    my $releaseName = $schedule->findvalue('//releaseName')->string_value;

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
    $self->info("Launched $what from the schedule $projectName:$scheduleName");
}



sub cleanup {
    my ($self) = @_;

    my @filters = ({
        propertyName => 'scheduleName',
        operator => 'like',
        operand1 => '%-Webhook-Queue',
    });

    my $xpath = $self->ec->findObjects('schedule', {filter => \@filters});
    for my $schedule ($xpath->findnodes('//schedule')) {
        my $scheduleName = $schedule->findvalue('scheduleName')->string_value;
        my $projectName = $schedule->findvalue('projectName')->string_value;

        my $launched;
        eval {
            my $value = $self->ec->getProperty({
                projectName => $projectName,
                scheduleName => $scheduleName,
                propertyName => 'launched',
            })->findvalue('//value')->string_value;
            $launched = $value eq 'true';
        };

        if ($launched) {
            $self->info("Schedule $projectName:$scheduleName has already been launched, so it is a subject to removal");

            eval {
                $self->cleanJobs($projectName, $scheduleName);
                1;
            } or do {
                my $err = $@;
                $self->info("Failed to clean up jobs: $err");
            };

            if ($scheduleName eq '$[/mySchedule/scheduleName]') {
                $self->info("Will not remove this schedule");
            }
            else {
                eval {
                    $self->ec->deleteSchedule({
                        projectName => $projectName,
                        scheduleName => $scheduleName,
                    });
                    $self->info("Deleted schedule $projectName:$scheduleName");
                    1;
                } or do {
                    my $err = $@;
                    $self->info("Failed to delete schedule $projectName:$scheduleName: $err");
                };
            }
        }
    }
}

sub cleanJobs {
    my ($self, $projectName, $scheduleName) = @_;

    my @filters = ();

    push @filters , {
        propertyName => 'projectName',
        operator => 'equals',
        operand1 => $projectName,
    };

    push @filters, {
        propertyName => 'scheduleName',
        operator => 'equals',
        operand1 => $scheduleName,
    };

    push @filters, {
        propertyName => 'status',
        operator => 'equals',
        operand1 => 'completed'
    };

    my $jobs = $self->ec()->findObjects('job', {numObjects => '500', filter => \@filters});
    for my $job ($jobs->findnodes('//job')) {
        my $jobId = $job->findvalue('jobId')->string_value;
        if ($jobId eq $ENV{COMMANDER_JOBID}) {
            $self->info("Will not remove this job");
        }
        else {
            $self->ec()->deleteJob({jobId => $jobId});
            my $jobName = $job->findvalue('jobName')->string_value;
            $self->deleteWorkspace($job);
            $self->info("Deleted Job: $jobName");
        }
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
            $self->info("Deleted workspace - $workspace");
        }
    }
}



sub info {
    my ($self, $message) = @_;

    print "[INFO] $message\n";
}

1;
