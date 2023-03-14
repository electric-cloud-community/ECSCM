
use strict;


$::gBuildDirectory = "";


# Matchers to work with ElectricSentry (Continuous Integration)
push (@::gMatchers,
	#    ElectricSentry has started a procedure
    #       ElectricSentry has started .Test Sentry:-StartMain. from schedule .Release Debug.
    #
	{
		id =>              "WebhookStarted",
	    pattern =>          q{"Launched (procedure|pipeline|release) from the schedule (.+)"},
	    action =>           q{
            updateSummary($1, $2);
            diagnostic ("WebHook Processor Job", "info");
        },
	},
);

my $launchedSchedules = 0;

sub updateSummary {
    my ($what, $schedule) = @_;
    $launchedSchedules ++;
    setProperty("summary", "Launched $launchedSchedules schedules");
}

