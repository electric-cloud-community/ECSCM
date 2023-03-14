####################################################################
#
# ECSCM::Base::Cfg: A base class for specifc SCM other drivers.
#             Also contains generic config information such as a
#             registry of all installed SCM plugins
#
####################################################################
package ECSCM::Base::Cfg;
@ISA = (ElectricCommander::PropDB);
use ElectricCommander::PropDB;

####################################################################
# Object constructor for ECSCM::Base::Cfg
#
# Inputs
#   cmdr  = a previously initialized ElectricCommander handle
#   name  = a name for this configuration
####################################################################
sub new {
    my $class = shift;

    my $cmdr = shift;
    my $name = shift;

    # set the database
    my($self) = new ElectricCommander::PropDB(
        $cmdr, "/plugins/ECSCM/project/scm_cfgs");

    #store the row name
    $self->{_name} = $name;

    bless ($self, $class);
    return $self;
}


####################################################################
# Get name
####################################################################
sub getName {
    my ($self) = @_;
    return ($self->{_name});
}

####################################################################
# Generic routines to get/set configuration settings
####################################################################
sub get {
    my ($self, $setting) = @_;

    return $self->getCol($self->getName(), "$setting");
}
sub set {
    my ($self, $setting, $name) = @_;
    return $self->setCol($self->getName(), "$setting", "$name");
}


####################################################################
# server
#    The name of the SCM server (DNS or IP)
####################################################################
sub getServer {
    my ($self) = @_;
    return $self->get("server");
}
sub setServer {
    my ($self, $name) = @_;
    return $self->set("server", "$name");
}

####################################################################
# user
#    The name of the SCM user
####################################################################
sub getUser {
    my ($self) = @_;
    return $self->get("user");
}
sub setUser {
    my ($self, $name) = @_;
    return $self->set("user", "$name");
}

####################################################################
# password
#    The name of the SCM password
####################################################################
sub getPassword {
    my ($self) = @_;
    return $self->get("password");
}
sub setPassword {
    my ($self, $name) = @_;
    return $self->set("password", "$name");
}

####################################################################
# scmPlugin
#    The name of the SCM driver
####################################################################
sub getSCMPluginName {
    my ($self) = @_;
    return $self->get("scmPlugin");
}
sub setSCMPluginName {
    my ($self, $name) = @_;
    return $self->set("scmPlugin", "$name");
}


####################################################################
# credential
#    The name of the SCM credential
####################################################################
sub getCredential {
    my ($self) = @_;
    return $self->get("credential");
}
sub setCredential {
    my ($self, $name) = @_;
    return $self->set("credential", "$name");
}

######################## GLOBAL CONFIG ITEMS ######################
## these will be run without a specific context

####################################################################
# createCfg
#    Create a new config for a driver
####################################################################
sub createCfg {
    my ($self, $cfg, $scmPlugin, $desc) = @_;
    if (!defined ($desc) || "$desc" eq "") {
        $desc = $scmPlugin;
    }
    if ($self->setRow("$cfg", "$desc") ) {
        return undef;
    }
    if ($self->setCol($cfg,"scmPlugin","$scmPlugin") != 0 ) {
        return undef;
    }
    $self->{_name} = "$cfg";
    return $cfg;
}

####################################################################
# deleteCfg
#    Delete an SCM config
####################################################################
sub deleteCfg {
    my ($self, $cfg) = @_;
    return $self->delRol("$cfg");
}

####################################################################
# getRegisteredSCMList
#    gets all plugins that start with ECSCM-
####################################################################
sub getRegisteredSCMList {
    my ($self) = @_;
    my %results;
    my $xPath = $self->getCmdr()->getPlugins();
    my $nodeset = $xPath->find('//response/plugin/pluginKey');
    foreach my $node ($nodeset->get_nodelist) {
        my $name = $node->string_value();
        if ( $name =~ m/^ECSCM-/) {
            $results{$name}="plugin";
            print "adding $name to registered plugin list\n";
        }
    }
    return %results;
}

1;
