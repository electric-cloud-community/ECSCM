
use strict;


$::gBuildDirectory = "";

push (@::gMatchers,
    # Perforce files added
	#     //XXProj/main/Source/structs.h#2 - added as C:\x407\SOURCE\structs.h
	{
		id =>               "PerforceAdd",
	    pattern =>          q{ - added as },
	    action =>           q{incValueWithString("summary", "Perforce has added 0 files" );},
	},
	# Perforce files that could not be clobbered
    #     Can.t clobber writable file C:\x407\exe\components\Liquid.html
	{
		id =>               "PerforceNoClobber",
	    pattern =>          q{Can.t clobber},
	    action =>           q{incValue("warnings");	diagnostic ("P4 Sync", "warning");},
	},
	# Perforce change logs
    #     Change 19398 by jj@jj-sentry on 2006/09/26 14:53:15
    #
	{
		id =>              "PerforceChangeLog",
	    pattern =>          q{^Change ([0-9]+) },
	    action =>           q{incValueWithString("summary", "0 changes since last build" );
	                        diagnostic ("Change $1", "info", 0, forwardTo("^Affected files")-1 );},
	},

);

# Matchers to work with ElectricSentry (Continuous Integration)
push (@::gMatchers,
    #    ElectricSentry has started a procedure
    #       ElectricSentry has started .Test Sentry:-StartMain. from schedule .Release Debug.
    #
    {
        id =>              "ElectricSentryStarted",
        pattern =>          q{ElectricSentry has started a (job|pipeline|release)},
        action =>           q{countStartedJobs($1);
                            diagnostic ("ElectricSentry Job", "info");},
    },
);

#-------------------------------------------------------------------------
# incValueWithString
#
#      This function is typically invoked in the action for a matcher.
#      It increments a member of $::gProperties.
#      This version operates a strings values of the form:
#               123 followed by other data
#
# Results:
#      None.
#
# Arguments:
#      name -          Name to element of $::gProperties to increment.
#      patternString - String containing a numeric field that will be replaced
#      increment -     (optional) How much to increment the value; defaults
#                      to 1.
#-------------------------------------------------------------------------

sub incValueWithString($;$$) {
    my ($name, $patternString, $increment) = @_;

    $increment = 1 unless defined($increment);

    my $localString = (defined $::gProperties{$name}) ? $::gProperties{$name} :
                                                        $patternString;

    $localString =~ /([^\d]*)(\d+)(.*)/;
    my $leading = $1;
    my $numeric = $2;
    my $trailing = $3;

    $numeric += $increment;
    $localString = $leading . $numeric . $trailing;

    setProperty ($name, $localString);
}

#-------------------------------------------------------------------------
# countStartedJobs
# this function counts started jobs/pipelines/releases by matching ef logs
#-------------------------------------------------------------------------

my $counter = {};
sub countStartedJobs {
    my ($what) = @_;

    my $number = $counter->{$what} ||= 0;
    $number++;
    $counter->{$what} = $number;

    my @parts = ();
    for my $element (qw/job pipeline release/) {
        if ($counter->{$element}) {
            my $notionString = "$counter->{$element} $element";
            if ($counter->{$element} > 1) {
                # Plural
                $notionString .= 's';
            }
            push @parts, $notionString;
        }
    }
    my $last = shift @parts;
    my $summary = '';
    if (scalar @parts) {
        $summary = "ElectricSentry has started " . join(", ", @parts) . " and $last";
    }
    else {
        $summary = "ElectricSentry has started $last";
    }
    setProperty('summary', $summary);
}

