####################################################################
#
# ElectricSentry::ScheduleCfg
#
# This config models the Sentry settings for a particular schedule
#
####################################################################
package ElectricSentry::ScheduleCfg;
@ISA = (ElectricCommander::PropDB);
require ElectricCommander::PropDB;


####################################################################
# Object constructor for ElectricSentry::ScheduleCfg
#
# Inputs
#   cmdr        = a previously initialized ElectricCommander handle
#   sentryProj  = The sentry project
#        i.e. Electric Cloud
#   sentrySched = The sentry schedule
#        i.e. SentryMonitor
#   proj        = a project that holds the sched to run
#   sched       = the sched to run for this trigger
####################################################################
sub new {
    my ($class, $cmdr, $sentryProj, $sentrySched,$proj, $sched) = @_;

    # set the database 
    my($self) = ElectricCommander::PropDB->new($cmdr,"/projects/$sentryProj/schedules/$sentrySched/$proj");
    $self->{_sched} = $sched;
    $self->{_proj}  = $proj;

    bless ($self, $class);
    return $self;
}

####################################################################
# Generic routines to get/set configuration settings
####################################################################
sub get {
    my ($self, $setting) = @_;
    
    return $self->getCol($self->{_sched}, "$setting");
}
sub set {
    my ($self, $setting, $name) = @_;
    return $self->setCol($self->{_sched}, "$setting", "$name");
}



####################################################################
# LastAttempted
#    The LastAttemptedSnapshot setting
####################################################################
sub getLastAttempted {
    my ($self) = @_;
    return $self->get("LastAttemptedSnapshot");
}
sub setLastAttempted {
    my ($self, $name) = @_;
    return $self->set("LastAttemptedSnapshot", "$name");
}

1;
