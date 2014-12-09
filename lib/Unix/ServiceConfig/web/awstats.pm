######################################################################
#
# Unix/ServiceConfig/web/awstats.pm
#
# Copyright (C) 2006-2014 David Lundgren. All Rights Reserved
#
# MIT License
#
######################################################################

=pod

=head1 NAME

Unix::ServiceConfig::web::awstats - Awstats Configuration Interface Class

=head1 SYNOPSIS

	use SystemConfig;

	my @args = [ 'test_user' ];

	my $db = Unix::ServiceConfig::new(
		-type    => 'stats'
		-file    => 'file.conf',
		-action  => 'add');

	$db->execute(@args);

=cut

package Unix::ServiceConfig::web::awstats;

no warnings 'portable';
use 5.6.0;
use strict;
use warnings;

use vars qw(@ISA);

#use Apache::Admin::Config;
use Term::ANSIColor;
use Unix::ServiceConfig;
use Unix::ServiceConfig::web;

@ISA = qw(Unix::ServiceConfig Unix::ServiceConfig::web);

my $VERSION   = '0.01';
my $REVISION  = sprintf("%d.%02d", q$Revision: 1.3 $ =~ /(\d+)\.(\d+)/);

=head1 CLASS VARIABLES

=over

=item B<$valid_actions>

The valid actions for this class are: add, alias, del, delete, edit, 
hold, list, unhold.

=back

=cut

my $actions = [
	'add',
	'alias',
	'del',
	'edit',
	'list',
	'hold',
	'unhold',
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
		
		$mconf = $c{'stats'};
		$gconf = $c{'generic'};
	}

	my %config = $pkg->_merge_config('web', $mconf, $gconf);

	my $self = { 
		'config'    => ( \%config ),
		'file'      => $file,
		'actions'   => $actions,
		'me'        => 'web',
		'class'     => 'awstats',
		'base_type' => 'domain',
		'check'     => 'awstats',
		'main'      => 1,
		'debug'     => 0,
		'commands'  => [ $config{'command-restart'} ],
		'error'     => {
			'exists' => 0,
			'msg'    => '',
		},
		'log'       => {
			'action' => 'unknown',
			'what'   => 'web',
			'status' => 'unknown',
			'args'   => '',
		}
	};

	bless($self, $class);
	
	return($self);
} #new

=item B<alias>

  Title    : ask_action
  Usage    : $self->add(@args);
  Function : Adds a domain as a HostAlias to $domain awstats configuration.
  Returns  : an object
  Args     : $action : whether to add or delete.
             $domain : The domain to to add the alias to
             $alias  : The alias to add to the domain

=cut

sub alias($)
{
	my ($self, @args) = @_;
	$self->{'log'}->{'args'}   = \@args;
	$self->{'log'}->{'action'} = 'alias';
	my ($action, $domain, $alias) = @args;
	my ($option, @list);

	return($self) if ($action !~ m/^(add|del(ete)?|list)$/i);

	# get the domain
	if (1 == $self->{'main'})
	{
		$domain   = $self->_get_valid_type_input($domain);
		$alias    = $self->_get_input_with_check(
		   "Alias for ($domain)",
		   'Must be a valid domain', 
		   0,
		   $alias,
		   $self->{'config'}->{'regex-domain'}) if ('list' ne $action);
		$alias = '' if ('list' eq $action);
	} #

	if (1 == $self->{'error'}->{'exists'})
	{
		$self->_print_check_start();
		return($self) if ($self->_print_error());
	}

	# this makes sure that we have the longest available width to the status
	# message to make things look nice
	$option = 'Unknown';
	$option = 'Adding'   if ('add' eq $action);
	$option = 'Deleting' if ($action =~ m/^del(ete)?$/i);

	$self->_width_to_status("$option ($alias) to ($domain) configuration");

	$self->_print_check_start();
	return($self) if ($self->_print_error());

	my $_dir  = $self->{'config'}->{'directory-config'};
	my $_file = $self->{'config'}->{'file-name'};

	# replace the file with the domain
	$_file =~ s/(\%)domain\%/$domain/gi;

	if (!-e "$_dir/$_file")
	{
		$self->_set_error("Error opening ($_dir/$_file). File not found.");
		return($self) if ($self->_print_error());
	}

	my @data = $self->_file_get("$_dir/$_file");
	my @output;

	# at this point we have the new data but we need to see if the alias exists
	# in the line. If it doesn't we can error out.

	foreach my $line (@data)
	{
		chomp($line);
		if ($line =~ m/^HostAliases/i)
		{
			if ( ($line =~ m/ $alias/i) && ('add' eq $action) )
			{
				$self->_set_error("Alias ($alias) already exists in ($domain).");
				return($self) if ($self->_print_error());
			}
			elsif ( ($line !~ m/ $alias/i) && ($action =~ m/^del(ete)?$/) )
			{
				$self->_set_error("Alias ($alias) does not exist in ($domain).");
				return($self) if ($self->_print_error());			
			}
			if ($line =~ m/\=(\s+)?(\"?)([^\2\"]*?)\2/i)
			{
				my $new = my $orig = $3;
				if ('list' eq $action)
				{
					@list = split(' ', $orig);
				}
				elsif ('add' eq $action)
				{
					$new = "$orig $alias";
				} # add the alias
				elsif ($action =~ m/^del(ete)?$/i)
				{
					$new  =~ s/((^$alias\s+?)|(\s+?$alias))//i;
				} # delete the alias
				$line = "HostAliases=\"$new\"";
			} # the line has the host alias
		}
		push(@output, $line."\n");
	}
	
	$self->_print_ok();
	
	if ('list' eq $action)
	{
		printf("Current aliases for ($domain):\n");
		my $_c =1;
		foreach my $alias (sort @list)
		{
			$self->_print_list_line($_c, $alias,0);
			$_c++;
		}
		exit(0); # alias list (alias)
	}

	$self->_pretty_print_start("$option ($alias) to ($domain) configuration");

	unlink("$_dir/$_file");
	$self->_file_create("$_dir/$_file", join('', @output));
	return($self) if ($self->_print_error());
	$self->_print_ok();

	return($self);
} #alias

=item B<Filled Stubs>

=item B<ask_action>

  Title    : ask_action
  Usage    : $self->add(@args);
  Function : Adds a domain to apache.
  Returns  : an object
  Args     : 

=cut

sub ask_action($)
{
	my ($self, $action, @arg) = @_;
	my (@args, $do);
	
	return($self) if (!$self->{'data'});
	return($self) if (!$self->{'data'}->{'domain'});
	my $domain    = $self->{'data'}->{'domain'};

	$self->_print_section_run();

	my %c = $self->_parse_configuration($self->{'file'});
	$self->{'sconfig'} = $c{'web_stats'};

	$self->{'main'} = 0;

	push(@args, $ARGV[0]) if ($action =~ m/^alias$/i);
	push(@args, $self->{'data'}->{'domain'});
	push(@args, $self->{'data'}->{'alias'}) 
	  if ( ($action =~ m/^alias$/i)
	    && ($self->{'data'}->{'alias'})
	     );
	
	if ($action =~ m/^add$/i)
	{
		push(@args, $self->{'data'}->{'log_dir'});
		push(@args, $self->{'data'}->{'user_name'});
	} # handle adding information

	$do = $self->_get_yesno("Add ($domain) to system", "Yn")
	  if ($action =~ /^add$/);
	$do = $self->_get_yesno("Delete ($domain) from System", "Yn")
	  if ($action =~ /^del(ete)?$/);
	$do = $self->_get_yesno("Hold ($domain) on system", "Yn")
	  if ($action =~ /^hold$/);
	$do = $self->_get_yesno("Re-Activate ($domain) on system", "Yn")
	  if ($action =~ /^unhold$/);

	$self->ask_action_exists($action, ucfirst($self->{'base_type'}), $domain);
	return($self) if ($self->_print_error());
	$self->_print_ok();

	if ($self->_is_enabled($do))
	{
		# Notify the command that we are not to get a username from the user
		$self->{'config'}->{'has_domain'}  = $domain;
#		$self->_print_error();
		$self->add(@args)    if ($action =~ /^add$/);
		$self->del(@args)    if ($action =~ /^del(ete)?$/);
		$self->hold(@args)   if ($action =~ /^hold$/);
		$self->unhold(@args) if ($action =~ /^unhold$/);
	}

	return($self);
} #ask_action

=item B<add>

  Title    : add
  Usage    : $self->add(@args);
  Function : Adds a domain to awstats.
  Returns  : an object
  Args     : 

=cut

sub add
{
	my ($self, @args) = @_;
	$self->{'log'}->{'args'}   = \@args;
	$self->{'log'}->{'action'} = 'add';
	my ($domain, $location, $user) = @args;

	# get the domain
	if (1 == $self->{'main'})
	{
		$domain   = $self->_get_valid_type_input($domain);
		$location = $self->check_location($location);
		$user     = $self->_get_valid_system_user($user,'Username',1)
		  if ($user);
		$user     = '' if (!$user);
	}

	if (1 == $self->{'error'}->{'exists'})
	{
		$self->_print_check_start();
		return($self) if ($self->_print_error());
	}

	# this makes sure that we have the longest available width to the status
	# message to make things look nice
	$self->_width_to_status("Adding ($domain)");

	# main needs to create user log directories
	if ($self->_is_enabled($self->{'main'}))
	{
		my $_dir  =  $self->{'config'}->{'directory-logs'};
		$_dir     =~ s/(\%)user_home\%/$location/gi;
		$_dir     =~ s/(\%)domain\%/$domain/gi;
		$_dir     =~ s/\/\//\//gi;
		$location =  $_dir;
	} # transform location

	$self->_print_check_start();
	if (!-d $location)
	{
		$self->_set_error("Directory ($location) doesn't exist.", 2);
		return($self) if ($self->_print_error());
	}

	if (!-d "$location/archive")
	{
		$self->_mkdir("$location/archive", oct('0755'));
		chmod(oct('0755'), "$location/archive");
	} # make sure that the archive directory exists

	my $_dir  = $self->{'config'}->{'directory-config'};
	my $_file = $self->{'config'}->{'file-name'};

	# replace the file with the domain
	$_file =~ s/(\%)domain\%/$domain/gi;
	my $conf  = "$_dir/$_file";

	if (!-e "$_dir/$_file")
	{
		rename("$_dir/$_file", "$_dir/$_file.orig");
	} # the file can't already exist put it should have been checked earlier

	# what are the directives
	my $tpl = join('',
	  $self->_file_get_template($self->{'config'}->{'template-file-conf'}));

	$tpl =~ s/(\%)domain%/$domain/gi;
	$tpl =~ s/(\%)log_dir%/$location/gi;
	$tpl =~ s/(\%)user_name%/$user/gi;
	
	$self->_print_ok();

	$self->_pretty_print_start("Adding ($domain)");
	#
	# TODO: handle var-([-a-z0-9]*) replacement
	#
	$self->_file_create($conf, $tpl);
	return($self) if ($self->_print_error());
	$self->_print_ok();

	return($self);
} #add

=item B<del>

  Title    : del
  Usage    : $self->del(@args);
  Function : Deletes a domain from the awstats configuration.
  Returns  : an object
  Args     : @args : an array of the arguments to the function. 
                     The first argument must be the domain, if it doesn't
                     exist it will ask for one.

=cut

sub del
{
	my ($self, @args) = @_;
	$self->{'log'}->{'args'} = \@args;
	$self->{'log'}->{'action'} = 'del';
	my ($domain) = @args;
	my $fh;

	# force a domain to be set then transform it into the proper name
	$domain   = $self->_get_valid_type_input($domain)
	  if (1 == $self->{'main'});

	$self->_width_to_status("Removing ($domain)");

	$self->_print_check_start();
	return($self) if ($self->_print_error());
	$self->_print_ok();

	my $_dir  = $self->{'config'}->{'directory-config'};
	my $_file = $self->{'config'}->{'file-name'};

	# replace the file with the domain
	$_file =~ s/(\%)domain\%/$domain/gi;
	my $conf  = "$_dir/$_file";

	# now delete the file from the proper file
	$self->_pretty_print_start("Removing ($domain)");
	
	if (-e "$_dir/$_file")
	{
		if (1 != unlink("$_dir/$_file"))
		{
			return($self) if ($self->_print_error());
		}
	} # remove the 
	else
	{
		$self->_set_error("Error Deleting ($_file). No such file or directory.");
		return($self) if ($self->_print_error());
	}

	$self->_print_ok();

	return($self);
} #del

=item B<edit>

  Title    : edit
  Usage    : $self->edit(@args);
  Function : Calls an edit command to edit the file at the location that the 
             domain is at.
  Returns  : an object
  Args     : @args : an array of the arguments to the function. 
                     The first argument must be the domain, if it doesn't
                     exist it will ask for one.

=cut

sub edit
{
	my ($self, @args) = @_;
	$self->{'log'}->{'args'}   = \@args;
	$self->{'log'}->{'action'} = 'list';
	my ($domain) = @args;

	$domain   = $self->_get_valid_type_input($domain)
	  if (1 == $self->{'main'});

	my $_dir  = $self->{'config'}->{'directory-config'};
	my $_file = $self->{'config'}->{'file-name'};

	# replace the file with the domain
	$_file =~ s/(\%)domain\%/$domain/gi;
	
	my %arg;
	$arg{'file'}  = "$_dir/$_file";

	$self->_run_cmd('edit', 0, %arg);
	
	exit(0); # edit
} #edit

=item B<extra_type_checks>

  Title    : 
  Usage    : $self->();
  Function : 
  Returns  : 
  Args     : 

=cut

sub extra_type_checks($$$$%)
{
	my ($self, $domain, $what, $e, $h, %args) = @_;

	# see if the file already exists
	my $_dir  = $self->{'config'}->{'directory-config'};
	my $_file = $self->{'config'}->{'file-name'};

	# replace the file with the domain
	$_file =~ s/(\%)domain\%/$domain/gi;

	if ( (1 == $e ) && ('alias' eq $what) )
	{
		return(2);
	}
	elsif ( ( -e "$_dir/$_file" ) && ('add' eq $what) )
	{
		$self->_set_error("Awstats is already configured for ($domain).");
		return(2);
	}

	return(0);
} #extra_type_checks

=item B<hold>

  Title    : hold
  Usage    : $self->hold(@args);
  Function : Puts a domain on hold in the awstats system.
  Returns  : an object
  Args     : @args : an array of the arguments to the function. 
                     The first argument must be the domain, if it doesn't
                     exist it will ask for one.

=cut

sub hold
{
	my ($self, @args) = @_;
	$self->{'log'}->{'args'}   = \@args;
	$self->{'log'}->{'action'} = 'hold';
	my ($domain) = @args;
	my $fh;

	# force a domain to be set then transform it into the proper name
	$domain   = $self->_get_valid_type_input($domain)
	  if (1 == $self->{'main'});

	$self->_width_to_status("Putting ($domain) on hold");

	$self->_print_check_start();
	return($self) if ($self->_print_error());
	
	my $_dir  = $self->{'config'}->{'directory-config'};
	my $_file = $self->{'config'}->{'file-name'};

	# replace the file with the domain
	$_file =~ s/(\%)domain\%/$domain/gi;

	if (!-e "$_dir/$_file")
	{
		return($self) if ($self->_print_error());
	}

	$self->_print_ok();

	$self->_pretty_print_start("Putting ($domain) on hold");

	if (-e "$_dir/$_file")
	{
		if (-1 == rename("$_dir/$_file", "$_dir/$_file.hold"))
		{
			return($self) if ($self->_print_error());
		}
	} # move the file

	$self->_print_ok();
	return($self);
} #hold

=item B<list>

  Title    : list
  Usage    : $self->list(@args);
  Function : Lists the domains in the awstats configuration.
  Returns  : an object
  Args     : @args : an array of the arguments to the function. 
                     -type   : The type of domain.
                     -search : The term to search for. [optional]

=cut

sub list
{
	my ($self, @args) = @_;
	$self->{'log'}->{'args'}   = \@args;
	$self->{'log'}->{'action'} = 'list';
	my ($dh, $_c, %list);

	my ($search) = @args;

	my $count = 1;
	my $fsize = 6;

	my $dir = $self->{'config'}{'directory-config'};

	if (!opendir($dh, $dir))
	{
		$self->_set_error("Can't open $dir: $!");
		return(1);
	}
	while (my $entry = readdir($dh))
	{
		if ($entry =~ m/(.*?).conf(\.hold)?/i)
		{
			$fsize              = length($1) if (length($1) > $fsize);
			$list{"$1"}{'held'} = 0;
			$list{"$1"}{'held'} = 1          if ($2);
			$_c++;
		}
	}
	closedir($dh);

	my $csize = length(keys(%list));
	$csize  = 4 if (4 > $csize);

	printf("\%${csize}s  ",  ' ');
	printf("\%-${fsize}s  ", 'Domain');
	printf("Flags\n");

	$self->_die_print('  No Domains found') if (0 == $_c); # list

	$count = 1;
	foreach my $l (sort keys %list)
	{
		my $d     = sprintf('%-'.$fsize.'s',  $l);
		my $held  = (1 == $list{"$l"}{'held'}) ? '(held)' : '';
		my $line  = sprintf(' %s  %s', $d, $held);
		
		$self->_print_list_line($count, $line, $list{"$l"}{'held'});
		$count++;
	}
	exit(0); #list
} #list

=item B<type_exists>

  Title    : type_exists
  Usage    : $self->type_exists(@args);
  Function : Determines if the $type exists in the apache configuration.
  Returns  : an object
  Args     : $domain : The domain to check existence for.
             $alias  : The alias to check for under domain.

=cut

sub type_exists($;$)
{
	my ($self, $domain, $alias) = @_;
	my $fh;
	my $exists = my $held = my $dom = 0;
	my $alias_line = '';
	my $_dir  = $self->{'config'}->{'directory-config'};
	my $_file = $self->{'config'}->{'file-name'};

	# replace the file with the domain
	$_file =~ s/(\%)domain\%/$domain/gi;

	$alias = '' if (!$alias);

	# we only test the file that we are given
	my $file = $self->{'config'}->{'apache-conf-file'};
	if (!$file)
	{
		$self->_set_error('Invalid file specified in configuration.');
		return(-1, -1);
	}
	$file    = $self->make_path($file);
	return(-1, -1) if (1 == $self->{'error'}->{'exists'});

	$alias_line = $self->get_alias_line($domain, $alias) if ('' ne $alias);
	if ( -e $file )
	{
		open($fh, $file);
		while(my $line = <$fh>)
		{
			if ($line =~ /\<VirtualHost $domain/i)
			{
				$exists = 1 if ('' eq $alias);
				$dom    = 1 if ('' ne $alias);
				# check if the domain is held
				if ($line =~ /\|\-\|(.*?)\<VirtualHost/i)
				{
					$held = 1;
					$held = 2 if ( (1 == $held) && ('' ne $alias) );
					last;
				}
			}
			elsif ( (1 == $dom) && ('' ne $alias) )
			{
				my @aliases = split("\n", $alias_line);

				# perhaps in future this will be smart enough
				if ($line =~ /$aliases[0]/i)
				{
					$exists = 1;
					$held = 1 if ($line=~ /\|\-\|(.*?)$aliases[0]/i);
				}
			}
			elsif ($line =~ /\<\/VirtualHost\>/i)
			{
				$dom = 0;
			}
		}
		close($fh);
	}

	if (1 == $exists)
	{
		$held   = 0;
		$exists = 0  if (!-e "$_dir/$_file");
	}
	elsif (0 == $exists)
	{
		$exists = 1  if (-e "$_dir/$_file");
	}

	$exists = 1 if (-e "$_dir/$_file.hold");
	$held = 1   if (-e "$_dir/$_file.hold");

	return ($exists, $held);
} #type_exists

=item B<unhold>

  Title    : unhold
  Usage    : $self->unhold(@args);
  Function : Removes a domain from hold in the awstats configuration.
  Returns  : an object
  Args     : @args : an array of the arguments to the function. 
                     The first argument must be the domain, if it doesn't
                     exist it will ask for one.

=cut

sub unhold
{
	my ($self, @args) = @_;
	$self->{'log'}->{'args'} = \@args;
	$self->{'log'}->{'action'} = 'unhold';
	my ($domain, $user) = @args;
	my $fh;

	$domain   = $self->_get_valid_type_input($domain)
	  if (1 == $self->{'main'});

	$self->_width_to_status("Taking ($domain) off hold");

	$self->_print_check_start();
	return($self) if ($self->_print_error());

	my $_dir  = $self->{'config'}->{'directory-config'};
	my $_file = $self->{'config'}->{'file-name'};
	# replace the file with the domain
	$_file =~ s/(\%)domain\%/$domain/gi;
	
	if (!-e "$_dir/$_file.hold")
	{
		return($self) if ($self->_print_error());
	}

	$self->_print_ok();

	$self->_pretty_print_start("Taking ($domain) off hold");

	if (-e "$_dir/$_file.hold")
	{
		if (-1 == rename("$_dir/$_file.hold", "$_dir/$_file"))
		{
			$self->_set_error("Couldn't reactivate ($domain) in awstats.");
			return($self) if ($self->_print_error());
		}
	} # move the file

	$self->_print_ok();

	return($self);
} #unhold

1;
