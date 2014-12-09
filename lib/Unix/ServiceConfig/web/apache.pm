######################################################################
#
# Unix/ServiceConfig/web/apache.pm
#
# Copyright (C) 2006-2014 David Lundgren. All Rights Reserved
#
# MIT License
#
######################################################################

=pod

=head1 NAME

SystemConfig::web::apache - Apache Configuration Interface Class

=head1 SYNOPSIS

	use SystemConfig;

	my @args = [ 'test_user' ];

	my $db = SystemConfig::new(
		-type    => 'web'
		-file    => 'file.conf',
		-action  => 'add');

	$db->execute(@args);

=cut

package Unix::ServiceConfig::web::apache;

no warnings 'portable';
use 5.6.0;
use strict;
use warnings;

use vars qw(@ISA);

use Term::ANSIColor;
use Unix::ServiceConfig;
use Unix::ServiceConfig::web;

@ISA = qw(Unix::ServiceConfig Unix::ServiceConfig::web);

my $VERSION   = '0.01';
my $REVISION  = sprintf("%d.%02d", q$Revision: 1.2 $ =~ /(\d+)\.(\d+)/);

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
	  'delete',
	  'edit',
	  'hold',
	  'list',
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
		
		$mconf = $c{'web'};
		$gconf = $c{'generic'};
	}

	my %config = $pkg->_merge_config('web', $mconf, $gconf);

	my $self = { 
		'config'    => ( \%config ),
		'file'      => $file,
		'actions'   => $actions,
		'main'      => 1,
		'check'     => 'Apache',
		'me'        => 'web',
		'class'     => 'apache',
		'base_type' => 'domain',
		'debug'     => 0,
		'section'   => {
			'extra'     => { },
			'web_stats' => { },
		},
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

=item B<Miscellaneous>

=item B<__edit>

  Title    : __edit
  Usage    : $self->__edit('example.com', '<VirtualHost \"?', 1);
  Function : Locates the "$search $domain" line in the configuration file,
             and then calls the $self->_run_cmd to that line in the file.
  Returns  : an object.
  Args     : $domain : The domain to search for.
             $search : The beginning of the search phrase.
             $check  : Whether or not to check that the domain is valid.

=cut

sub __edit($$$)
{
	my ($self, @args) = @_;
	$self->{'log'}->{'args'}   = \@args;
	$self->{'log'}->{'action'} = 'list';
	my ($domain, $search, $check) = @args;
	my ($fh, %arg, $lineno, $found);
	$check = 0 if (!$check);
	$found = 0;
	
#	$domain = $self->_get_valid_type_input($domain);

	if (1 == $self->{'error'}->{'exists'})
	{
		if ($self->{'error'}->{'msg'} =~ m/on hold/i)
		{
			print("Domain ($domain) is currently on hold.\n");
			my $answer = $self->_get_yesno("Edit ($domain) anyway", 'n', 1);
			exit(0) if (!$self->_is_enabled($answer)); #edit
		}
	}
	

	my $conf = $self->{'config'}->{'apache-conf-file'};
	$conf    = $self->make_path($conf);
	return($self) if ($self->_print_error());

	# we run through the file to find the line that we are going to
	if (!$conf)
	{
		$self->_error('Invalid apache configuration file');
		return(-1);
	}
	
	if ( -e $conf )
	{
		open($fh, $conf);
		$lineno = 0;
		while(my $line = <$fh>)
		{
			$lineno++;
			if ($line =~ /$search $domain/i)
			{
				$found = 1;
				last;
			}
		}
		close($fh);
	}

	# set the arguments
	$arg{'line'} = $lineno;
	$arg{'file'} = $conf;

	if (1 == $found)
	{
		$self->_run_cmd('edit', 0, %arg);
		return($self);
	}
	$self->_die_print('Domain or alias not found'); # __edit
} #__edit

=item B<alias>

  Title    : alias
  Usage    : $self->alias();
  Function : Performs an action on an alias of a domain.
  Returns  : an object
  Args     : @args : first  : The action to perform.
                     second : The domain.
                     third  : The alias for the domain.

=cut

sub alias
{
	my ($self, @args) = @_;
	$self->{'log'}->{'args'} = \@args;
	$self->{'log'}->{'what'} = $self->{'log'}->{'what'} . '-alias';
	$self->{'log'}->{'action'} = 'alias';
	my ($action, $domain, $alias) = @args;
	my $line;

	# actions for aliases
	if ('edit' eq $action)
	{
		$self->__edit($domain, 'ServerAlias', 2);
	}
	elsif ($action !~ m/^(add|del(ete)?|(un)?hold|list)$/i)
	{
		return($self);
	}

	# We need a domain if we are adding
	if ('add' eq $action)
	{
		$domain = $self->_get_valid_type_input($domain);

		if (1 == $self->{'error'}->{'exists'})
		{
			$self->_print_check_start();
			return($self) if ($self->_print_error());
		}
	}
	elsif ('list' eq $action)
	{
		$self->alias_list($domain);
	}
	else
	{
		$alias = $domain;
		$domain = $self->find_domain_from_alias($alias);
	} # we need to find where the alias lives

	my $conf = $self->{'config'}->{'apache-conf-file'};
	$conf    = $self->make_path($conf);

	$self->{'log'}->{'action'} = $action;	
	$alias = $self->get_alias($domain, $alias);

	if (1 == $self->{'error'}->{'exists'})
	{
		$self->_print_check_start();
		return($self) if ($self->_print_error());
	}

	$self->{'section'}->{'extra'}->{'domain'} = $domain;
	$self->{'section'}->{'extra'}->{'alias'}  = $alias;

	my %actions = (
		'add'    => 'Adding',
		'del'    => 'Deleting',
		'delete' => 'Deleting',
		'hold'   => 'Holding',
		'unhold' => 'Unholding',
	);
	my %dir = (
		'add'    => 'to',
		'del'    => 'from',
		'delete' => 'from',
		'hold'   => 'in',
		'unhold' => 'in',	
	);
	my $what = $actions{$action};

	$self->_width_to_status("$what alias ($alias) $dir{$action} ($domain)");

	$self->_print_check_start();
	$line = $self->get_alias_line($domain, $alias);
	return($self) if ($self->_print_error());
	$self->_print_ok();

	# update the data
	$self->_pretty_print_start("$what alias ($alias) $dir{$action} ($domain)");

	$self->_update($domain, $conf, $action, $line, 1);

	return($self) if ($self->_print_error());

	$self->_print_ok();
	
	return($self);
} #alias

=item B<alias_list>

  Title    : alias_list
  Usage    : $self->alias_list($domain);
  Function : Lists any aliases that a domain might have.
  Returns  : 
  Args     : $domain : The domain to list aliases for.

=cut

sub alias_list($)
{
	my ($self, $domain) = @_;
	my ($fh, $dom, $alias, %list);

	$self->_die_print('Domain must be specified.') if (!$domain);
	my $aline = $self->{'config'}->{'regex-alias'};
	$aline    = $self->_regex_transform($aline);
	my $dline = $self->{'config'}->{'regex-start'};
	$dline    =~ s/(\%)data\%/$domain/gi;
	$dline    = $self->_regex_transform($dline);
	my $dend  = $self->{'config'}->{'regex-end'};
	my $file  = $self->{'config'}->{'apache-conf-file'};
	$file     = $self->make_path($file);
	my $fsize = 5;

	if (!$file)
	{
		$self->_set_error('Invalid file specified in configuration.');
		return(-1);
	}
	if ( -e $file )
	{
		open($fh, $file);
		$dom = 0;
		while(my $line = <$fh>)
		{
			if ($line =~ m/$dline/i)
			{
				$dom = 1;
			}
			elsif ( (1 == $dom) && ($line =~ m/$aline/i) )
			{
				$alias = $2;
				chomp($alias);
				$fsize = length($alias) if (length($alias) > $fsize);
				$list{"$alias"}{'held'} = 0;
				$list{"$alias"}{'held'} = 1 if ($line =~ m/\|\-\|/i);
			}
			elsif ($line =~ m/$dend/i)
			{
				$dom = 0;
			}
		}
		close($fh);
	}

	print("Aliases found for ($domain):\n");
	$self->_die_print('  No Aliases found') if (0 == keys(%list)); # list
	my $count = 1;

	foreach my $l (sort keys %list)
	{
		my $d     = sprintf('%-'.$fsize.'s',  $l);
		my $held  = (1 == $list{"$l"}{'held'}) ? '(held)' : '';
		my $line  = sprintf(' %s  %s', $d, $held);
	
		$self->_print_list_line($count, $line, $list{"$l"}{'held'});
		$count++;
	}
	exit(0); # alias_list
} #alias_list

=item B<find_domain_from_alias>

  Title    : find_domain_from_alias
  Usage    : $domain = $self->find_domain_from_alias($alias);
  Function : Finds the domain that the alias belongs to.
  Returns  : a string
  Args     : $alias : The alias to find the domain for.

=cut

sub find_domain_from_alias($)
{
	my ($self, $alias) = @_;
	my ($fh, $dom);

	my $aline  = $self->get_alias_line('', $alias);
	my $domain = $self->{'config'}->{'regex-list'};
	$domain    = $self->_regex_transform($domain);
	my $file   = $self->{'config'}->{'apache-conf-file'};
	$file      = $self->make_path($file);

	if (!$file)
	{
		$self->_set_error('Invalid file specified in configuration.');
		return(-1);
	}

	if ( -e $file )
	{
		open($fh, $file);
		while(my $line = <$fh>)
		{
			if ($line =~ m/$domain/i)
			{
				$dom = $2;
			}
			if ($line =~ m/$aline/i)
			{
				return($dom);
			}
		}
		close($fh);
	}
	return(-1);
} #find_domain_from_alias

=item B<get_alias>

  Title    : get_alias
  Usage    : $self->get_alias('example.com', 'test.example.com');
  Function : Returns the alias for a domain.
  Returns  : a string
  Args     : $domain : The main domain.
             $alias  : The alias for the domain.

=cut

# TODO: add_alias del_alias hold_alias unhold_alias
sub get_alias($$)
{
	my ($self, $domain, $alias) = @_;
	my ($t, $h);
	
	$h = 0;
	my $type = lc($self->{'config'}->{'type'});
	my $what = lc($self->{'log'}->{'action'});
	
	if ('unknown' eq $what)
	{
		$self->_set_error("Invalid Command: $what.");
		return(1);
	}

	if (!$alias)
	{
		do
		{
			$alias = $self->_get_input("Alias to $what", 'sub.example.com');
		} while ('' eq $alias);
	}
	
	($t, $h) = $self->type_exists($domain, $alias);
	
	if (2 == $h)
	{
		$self->_set_error("Domain is on hold ($domain).");
		return(1);
	} # nothing else matters
	elsif (1 != $self->_is_valid_input($alias, $self->{'config'}->{"regex-domain"}))
	{
		$self->_set_error("A valid domain is required ($alias).");
		return(1);
	}
	elsif ( ('add' eq $what) && ('exists' eq $t) )
	{
		$self->_set_error("Alias already exists in $domain ($alias).");
		return(1);
	}
	elsif ( ('add' ne $what) && ('' eq $t) )
	{
		$self->_set_error("Alias doesn't exist in $domain ($alias).\n");
		return(1);
	}
	elsif ( (1 == $h) && ($what ne 'unhold') )
	{
		$self->_set_error("Alias is on hold for $domain ($alias).");
		return(1);
	}
	elsif ( (0 == $h) && ($what eq 'unhold') )
	{
		$self->_set_error("Alias is already active for $domain ($alias).\n");
		return(1);
	}
	else
	{
		return($alias);
	}
	
	# keep going until we get a valid domain alias
	return($self->get_alias($domain, $alias));
} #get_alias

=item B<get_alias_line>

  Title    : get_alias_line
  Usage    : $self->get_alias_line();
  Function : Returns the line that an alias is on.
  Returns  : an integer
  Args     : $domain : The domain the alias is in.
             $alias  : The alias for the domain.

=cut

sub get_alias_line($$)
{
	my ($self, $domain, $alias) = @_;
	my $line;

	if ($self->{'config'}->{'alias-template'})
	{
		$line = join('', 
		  $self->_file_get_template($self->{'config'}->{'alias-template'}));
		# replacements
		$line =~ s/\%domain%/$domain/gi;
		$line =~ s/\%alias%/$alias/gi;
	}
	else
	{
		$line = $self->{'config'}->{'alias-directive'};
	}
	return($line);
} #get_alias_line

=item B<Filled Stubs>

=item B<add>

  Title    : add
  Usage    : $self->add(@args);
  Function : Adds a domain to apache.
  Returns  : an object
  Args     : @args : an array of the arguments to the function. 
                     The first argument must be the domain, if it doesn't
                     exist it will ask for one.
                     The second argument is where it is going, to a user or
                     to a special directory

=cut

sub add
{
	my ($self, @args) = @_;
	$self->{'log'}->{'args'}   = \@args;
	$self->{'log'}->{'action'} = 'add';
	my ($domain, $location) = @args;
	my ($user, $user_dir);

	# get the domain
	$domain = $self->_get_valid_type_input($domain);

	if (1 == $self->{'error'}->{'exists'})
	{
		$self->_print_check_start();
		return($self) if ($self->_print_error());
	}

	# force a location to be set
	($location, $user, $user_dir) = $self->check_location($location, 'domain',
	  $self->{'config'}->{'directory-user'});

	$self->_width_to_status("Adding ($domain)");

	$self->_print_check_start();
	return($self) if ($self->_print_error());

	# Where are we adding the directives
	my $conf = $self->{'config'}->{'apache-conf-file'};
	$conf    = $self->make_path($conf);
	return($self) if ($self->_print_error());

	# what are the directives
	my $tpl = join('', $self->_file_get_template($self->{'config'}->{'apache-template'}));

	# we have several replacements
	my $_vhn = $self->{'config'}->{'virtualhost-name'};
	$_vhn =~ s/(\%)domain%/$domain/gi;
	my $_sn = $self->{'config'}->{'server-name'};
	$_sn =~ s/(\%)domain%/$domain/gi;
	my $_logs = $self->{'config'}->{'directory-logs'};	
	$_logs =~ s/(\%)location\%/$location/gi;
	$_logs =~ s/(\%)domain%/$domain/gi;
	$_logs =~ s/(\%)user_name\%/$user/gi     if (0 < length($user));
	$_logs =~ s/(\%)user_home\%/$user_dir/gi if (0 < length($user_dir));
	$_logs =~ s/(\%)[^\%]*\%//gi;              # cleanup the logs % 
	$_logs =~ s/\/\//\//gi;

	# add the information to the data for the run sections
	$self->{'section'}->{'extra'}->{'user_name'} = $user;
	$self->{'section'}->{'extra'}->{'domain'}    = $domain;
	$self->{'section'}->{'extra'}->{'log_dir'}   = $_logs;

	$self->_make_log_directory($_logs, $user); # make sure the dir exists
	if ($self->_is_enabled($self->{'config'}->{'use-chroot'}))
	{
		my $chroot = $self->{'config'}->{'directory-chroot'};
		$_logs    =~ s/^$chroot//i;
		$location =~ s/^$chroot//i;
	}

	$tpl =~ s/(\%)log_dir%/$_logs/gi;
	$tpl =~ s/(\%)domain%/$domain/gi;
	$tpl =~ s/(\%)documentroot%/$location/gi;
	$tpl =~ s/(\%)servername%/$_sn/gi;
	$tpl =~ s/(\%)virtualhostname%/$_vhn/gi;

	$self->_print_ok();

	$self->_pretty_print_start("Adding ($domain)");
	#
	# TODO: handle var-([-a-z0-9]*) replacement
	#
	$self->_file_append($conf, $tpl);
	return($self) if ($self->_print_error());
	$self->_print_ok();

	return($self);
} #add

=item B<ask_action>

  Title    : ask_action
  Usage    : $self->ask_action();
  Function : Determines what to ask the user if this is being called as
             an extra section to the main one.
  Returns  : 
  Args     : $action : The action to perform.
             @args   : The arguments to the action.

=cut

sub ask_action
{
	my ($self, $action) = @_;
	my ($do, @args);
	return($self) if (!$self->{'data'});
	return($self) if (!$self->{'data'}->{'domain'});
	my $domain    = $self->{'data'}->{'domain'};

	push(@args, $ARGV[0]) if ($action =~ m/^alias$/i);
	push(@args, $domain);
	push(@args, $self->{'data'}->{'alias'}) 
	  if ( ($action =~ m/^alias$/i)
	    && ($self->{'data'}->{'alias'})
	     );
	push(@args, $self->{'data'}->{'user_name'}) 
	  if ( ($action =~ m/^add$/i)
	    && ($self->{'data'}->{'user_name'})
	     );

	$self->{'main'} = 0;

	$self->_print_section_run();

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
		$self->add(@args)    if ($action =~ /^add$/);
		$self->del(@args)    if ($action =~ /^del(ete)?$/);
		$self->hold(@args)   if ($action =~ /^hold$/);
		$self->unhold(@args) if ($action =~ /^unhold$/);
	}

	return($self);
} #ask_action

=item B<del>

  Title    : del
  Usage    : $self->del(@args);
  Function : Deletes a domain from the apache configuration.
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
	$domain = $self->_get_valid_type_input($domain);

	$self->{'section'}->{'extra'}->{'domain'}    = $domain;

	$self->_width_to_status("Removing ($domain)");

	$self->_print_check_start();
	return($self) if ($self->_print_error());
	$self->_print_ok();

	# Where are we adding the directives
	my $conf = $self->{'config'}->{'apache-conf-file'};
	$conf    = $self->make_path($conf);
#book

	# now delete the file from the proper file
	$self->_pretty_print_start("Removing ($domain)");
	
	$self->_delete($domain, $conf, 1);
	return($self) if ($self->_print_error());
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

	$domain = $self->_get_valid_type_input($domain);

	$self->__edit($domain,'\<VirtualHost');
	exit(0); # edit
} #edit

=item B<hold>

  Title    : hold
  Usage    : $self->hold(@args);
  Function : Puts a domain on hold in the apache system.
  Returns  : an object
  Args     : @args : an array of the arguments to the function. 
                     The first argument must be the domain, if it doesn't
                     exist it will ask for one.

=cut

sub hold
{
	my ($self, @args) = @_;
	$self->{'log'}->{'args'} = \@args;
	$self->{'log'}->{'action'} = 'hold';
	my ($domain) = @args;
	my $fh;

	# force a domain to be set then transform it into the proper name
	$domain = $self->_get_valid_type_input($domain);

	$self->{'section'}->{'extra'}->{'domain'}    = $domain;
	
	# Where are we adding the directives
	my $conf = $self->{'config'}->{'apache-conf-file'};	
	$conf    = $self->make_path($conf);

	$self->_width_to_status("Putting ($domain) on hold");

	$self->_print_check_start();
	return($self) if ($self->_print_error());
	$self->_print_ok();

	$self->_pretty_print_start("Putting ($domain) on hold");
	$self->_hold($domain, $conf, 0, 1);
	return($self) if ($self->_print_error());
	$self->_print_ok();

	return($self);
} #hold

=item B<list>

  Title    : list
  Usage    : $self->list(@args);
  Function : Lists the domains in the Apache configuration.
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

	my ($type, $search) = @args;
	$type = $self->{'config'}->{'config-files'} if (!$type);

	my ($_c, %list) = $self->_list($type, $search);
	my $count = 1;

	my $fsize = $list{'size'}{'fsize'};
	my $sizet = $list{'size'}{'3size'};
	my $csize = length(keys(%list));
	$csize  = 4 if (4 > $csize);
	$sizet  = 4 if (4 > $sizet);
    delete($list{'size'});

	printf("\%${csize}s  ",  ' ');
	printf("\%-${fsize}s  ", 'Domain');
	printf("\%-${sizet}s  ", 'Port');
	printf("Flags\n");

	$self->_die_print('  No Domains found') if (0 == $_c); # list

	foreach my $l (sort keys %list)
	{
		my $c     = sprintf('%'.$csize.'s.', $count);
		my $d     = sprintf('%-'.$fsize.'s',  $l);
		my $f3    = ($list{"$l"}{'f3'}) ?
		             sprintf('%-'.$sizet.'s',  $list{"$l"}{'f3'}) :
		             '    ';
		my $held  = (1 == $list{"$l"}{'held'}) ? '(held)' : '';
		my $line  = sprintf(' %s  %s  %s', $d, $f3, $held);
		
		print color('yellow'),$c,color('reset');

		my $color = color('green');
		$color    = color('bold red') 
		  if ($self->_is_enabled($list{"$l"}{'held'}));

		print $color, $line, color('reset'),"\n";
		$count++;
	}
	exit(0); # list
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

	$alias = '' if (!$alias);

	# we only test the file that we are given
	my $file = $self->{'config'}->{'apache-conf-file'};
	$file    = $self->make_path($file);

	if (!$file)
	{
		$self->_set_error('Invalid file specified in configuration.');
		return(-1, -1);
	}

	$alias_line = $self->get_alias_line($domain, $alias) if ('' ne $alias);

	if ( -e $file )
	{
		open($fh, $file);
		while(my $line = <$fh>)
		{
			if ($line =~ /\<VirtualHost $domain/i)
			{
				$exists = 1 if ('' eq $alias);
				$dom = 1 if ('' ne $alias);

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
	return ($exists, $held);
} #type_exists

=item B<unhold>

  Title    : unhold
  Usage    : $self->unhold(@args);
  Function : Removes a domain from hold in the apache configuration.
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

	$domain = $self->_get_valid_type_input($domain);

	$self->{'section'}->{'extra'}->{'domain'}    = $domain;

	# Where are we adding the directives
	my $conf = $self->{'config'}->{'apache-conf-file'};	
	$conf    = $self->make_path($conf);

	$self->_width_to_status("Taking ($domain) off hold");

	$self->_print_check_start();
	return($self) if ($self->_print_error());
	$self->_print_ok();

	$self->_pretty_print_start("Taking ($domain) off hold");
	$self->_unhold($domain, $conf, 0, 1);
	return($self) if ($self->_print_error());
	$self->_print_ok();

	return($self);
} #unhold

1;

__END__
