####################################################################
#
# ElectricSentry::TriggerCfg
#
# This config models the Sentry settings on a trigger schedule
#
####################################################################
package ElectricSentry::TriggerCfg;
@ISA = (ElectricCommander::PropDB);
require ElectricCommander::PropDB;

# this trigger value is different than the one used
# by legacy ElectricSentry.pl (1) on purpose. This allows
# legacy sentry to run in parallel with new sentry.
# Only schedules with a trigger of 2 will be picked up by
# this sentry. Think of it as a sentry protocol number.
$::gTriggerValue = "2";

####################################################################
# Object constructor for ElectricSentry::TriggerCfg
#
# Inputs
#   cmdr        = a previously initialized ElectricCommander handle
#   proj  = The sentry project
#   sched = The sentry schedule
####################################################################
sub new {
    my ($class, $cmdr,$proj, $sched) = @_;

    # set the database 
    my ($self) = ElectricCommander::PropDB->new($cmdr,"/projects/$proj/schedules/$sched");
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
    
    return $self->getCol("ec_customEditorData", "$setting");
}
sub set {
    my ($self, $setting, $name) = @_;
    return $self->setCol("ec_customEditorData", "$setting", "$name");
}

####################################################################
# scmConfig
#    The specific cfg 
####################################################################
sub getSCMConfig {
    my ($self) = @_;
    return $self->get("scmConfig");
}
sub setSCMConfig {
    my ($self, $name) = @_;
    return $self->set("scmConfig", "$name");
}

####################################################################
# TriggerFlag
#    The type of TriggerFlag that should process this CI schedule
####################################################################
sub isSetTriggerFlag {
    my ($self) = @_;
    return ($self->get("TriggerFlag") eq "$::gTriggerValue");
}
sub setTriggerFlag {
    my ($self, $name) = @_;
    return $self->set("TriggerFlag", "$::gTriggerValue");
}
sub unSetTriggerFlag {
    my ($self, $name) = @_;
    return $self->set("TriggerFlag", "0");
}

sub getAllProps {
    my ($self) = @_;
    my $tbl = $self->{_table} . "/ec_customEditorData";
    return $self->SUPER::getProps($tbl);
}
1;
