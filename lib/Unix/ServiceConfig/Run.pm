######################################################################
#
# Unix/ServiceConfig/Run.pm
#
# Copyright (C) 2006-2014 David Lundgren. All Rights Reserved
#
# MIT License
#
######################################################################

package Unix::ServiceConfig::Run;

no warnings 'portable';
use 5.6.0;
use strict;
use warnings;

use vars qw(@ISA);

use Term::ScreenColor;
use Unix::ServiceConfig;
@ISA = qw(Unix::ServiceConfig);

my $VERSION   = '0.01';
my $REVISION  = sprintf("%d.%02d", q$Revision: 1.2 $ =~ /(\d+)\.(\d+)/);

my $actions = [
	'ask_action',
	];

=head1 CLASS FUNCTIONS

=over

=item B<new>

  Title    : new
  Usage    : my $sc = SystemConfig->new(
                -type    => 'user',
                -file    => 'file.conf',
                -action  => 'add')
  Function : Returns an object of the type requested. If config or 
             generic are not defined then it will read the 
             configuration information from the file that was passed
             in.
  Returns  : A new object.
  Args     : -type    : The type of object to create 
                        (dns, web, mail, db, or user).
             -file    : The configuration filename.
             -action  : The action that the object is expected to perform.
             -config  : The configuration for the type. [optional]
             -generic : The generic configuration.      [optional]

=cut

sub new {
	my($pkg, $mconf, $gconf, $file) = @_;
	my $class = ref($pkg) || $pkg;

	if ( (!$mconf) || (!$gconf) )
	{
		# we load both if one is missing
		my %c = $pkg->_parse_configuration($file);
		
		$mconf = $c{'mail'};
		$gconf = $c{'generic'};
	}
	
	my %config = $pkg->_merge_config('mail', $mconf, $gconf);

	my $self = { 
		'config'    => ( \%config ),
		'file'      => $file,
		'actions'   => $actions,
		'me'        => 'RUN',
	};

	bless($self, $class);

	if ('user' eq $self->{'config'}->{'type'})
	{
		# the first argument to a user type is a username
		$self->{'section'}->{'extra'}->{'user_name'} = $ARGV[0];
	}
	elsif ('domain' eq $self->{'config'}->{'type'})
	{
		# the first argument to a domain type is a domain name
		$self->{'section'}->{'extra'}->{'domain'}    = $ARGV[0];
		# the second argument to a domain type is an alias or user name
		# since we can't tell we put ARGV[1] into both
		$self->{'section'}->{'extra'}->{'alias'}     = $ARGV[1];
		$self->{'section'}->{'extra'}->{'user_name'} = $ARGV[1];
	}

	return($self);
} #new

=item B<do_sections>

  Title    : do_sections
  Usage    : $run->do_sections($action);
  Function : Runs the sections specified in the configuration.
  Returns  : 
  Args     : $action : What the action is
  
=cut

sub ask_action
{
	my ($self, @args) = @_;
	my ($action) = @_;

	$self->usage() if (!$self->{'config'}->{'type'});
	
	if ('user' eq $self->{'config'}->{'type'})
	{
		# the first argument to a user type is a username
		$self->{'section'}->{'extra'}->{'user_name'} = $ARGV[0];
	}
	elsif ('domain' eq $self->{'config'}->{'type'})
	{
		# the first argument to a domain type is a domain name
		$self->{'section'}->{'extra'}->{'domain'}    = $ARGV[0];
		# the second argument to a domain type is an alias or user name
		# since we can't tell we put ARGV[1] into both
		$self->{'section'}->{'extra'}->{'alias'}     = $ARGV[1];
		$self->{'section'}->{'extra'}->{'user_name'} = $ARGV[1];
	}

#	$self->_run_sections($action);

	exit(0);
} # do_sections

1;
