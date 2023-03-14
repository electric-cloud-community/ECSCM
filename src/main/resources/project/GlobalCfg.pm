####################################################################
#
# ElectricSentry::GlobalCfg: Object definition of sentry configuration
#
# This config models the global Sentry settings on a sentry 
# schedule.
#
####################################################################
package ElectricSentry::GlobalCfg;
@ISA = (ElectricCommander::PropDB);
require ElectricCommander::PropDB;


####################################################################
# Object constructor for ElectricSentry::GlobalCfg
#
# Inputs
#   cmdr         = a previously initialized ElectricCommander handle
#   sentryProj   = The sentry project
#            i.e. Electric Cloud
#   sentrySched  = a name for this configuration (path to schedule)
#            i.e. SentryMonitor
####################################################################
sub new {
    my $class = shift;

    my $cmdr  = shift;
    my $sentryProj = shift;
    my $sentrySched = shift;

    # set the database 
    my($self) = ElectricCommander::PropDB->new($cmdr,"/projects/$sentryProj/schedules/$sentrySched");
    bless ($self, $class);
    return $self;
}

####################################################################
# Generic routines to get/set configuration settings
####################################################################
sub get {
    my ($self, $setting) = @_;
    
    return $self->getCol("ElectricSentrySettings", "$setting");
}
sub set {
    my ($self, $setting, $name) = @_;
    return $self->setCol("ElectricSentrySettings", "$setting", "$name");
}


####################################################################
# QuietTime
#    The QuietTimeMinutes setting
####################################################################
sub getQuietTime {
    my ($self) = @_;
    return $self->get("QuietTimeMinutes");
}
sub setQuietTime {
    my ($self, $name) = @_;
    return $self->set("QuietTimeMinutes", "$name");
}

####################################################################
# saveJobs
#    The saveJobs setting
####################################################################
sub getSaveJobs {
    my ($self) = @_;
    return $self->get("SaveJobs");
}
sub setSaveJobs {
    my ($self, $name) = @_;
    return $self->set("SaveJobs", "$name");
}
1;
