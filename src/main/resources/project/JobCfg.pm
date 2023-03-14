####################################################################
#
# ElectricSentry::JobCfg
#
# This config models the Sentry settings saved on the sentry
# job itself
#
####################################################################
package ElectricSentry::JobCfg;
@ISA = (ElectricCommander::PropDB);
require ElectricCommander::PropDB;


####################################################################
# Object constructor for ElectricSentry::JobCfg
#
# Inputs
#   cmdr   = a previously initialized ElectricCommander handle
#   proj   = The trigger project
#            i.e. EC-Examples
#   sched  = The trigger schedule
#            i.e. RunDemo
####################################################################
sub new {
    my $class = shift;

    my $cmdr  = shift;
    my $jobid = shift;
    my $proj  = shift;
    my $sched = shift;

    # set the database 
    my($self) = ElectricCommander::PropDB->new($cmdr,"/jobs/$jobid/SentrySchedules");
    $self->{_proj} = $proj;
    $self->{_sched} = $sched;
    bless ($self, $class);
    return $self;
}

####################################################################
# Generic routines to get/set configuration settings
####################################################################
sub get {
    my ($self, $setting) = @_;
    
    return $self->getCol($self->{_proj}, "$setting");
}
sub set {
    my ($self, $setting, $name) = @_;
    return $self->setCol($self->{_proj}, "$setting", "$name");
}


####################################################################
# setState
#    The state of the schedule in sentry processing workflow
####################################################################
sub getState {
    my ($self) = @_;
    return $self->get($self->{_sched});
}
sub setState {
    my ($self, $state) = @_;
    return $self->set($self->{_sched}, "$state");
}

####################################################################
# getAllSchedules
#    Load a hash with all of the schedules stored
#    the proj/sched passed in "new" are ignored for this method
####################################################################
sub getAllSchedules() {
    my $self = shift;
    my %ret;
    
    # get all projects (row in table)
    my %projs = $self->getRows();
    my $count=1;
    # for each project
    foreach my $proj (sort keys %projs) {
        # get all schedules (cell)
        my %scheds = $self->getRow("$proj");
        foreach my $sched (sort keys %scheds) {
            # store value of proj/sched pair
            $ret{$count}{project}=$proj;
            $ret{$count}{schedule}=$sched;
            $ret{$count}{value}=$scheds{$sched};
            $count++;
        }
    }
    return %ret;
}
1;
