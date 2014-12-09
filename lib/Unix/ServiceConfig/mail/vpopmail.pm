######################################################################
#
# Unix/ServiceConfig/mail/vpopmail.pm
#
# Copyright (C) 2006-2014 David Lundgren. All Rights Reserved
#
# MIT License
#
######################################################################

=pod

=head1 NAME

Unix::ServiceConfig::mail::vpopmail - vpopmail 5.4.10+ Configuration Interface Class

=head1 SYNOPSIS

	use Unix::ServiceConfig;

	my @args = [ 'test_user' ];

	my $db = Unix::ServiceConfig::new(
		-type    => 'mail'
		-file    => 'file.conf',
		-action  => 'add');

	$db->execute(@args);

=cut

package Unix::ServiceConfig::mail::vpopmail;

no warnings 'portable';
use 5.6.0;
use strict;
use warnings;

use vars qw(@ISA);

=head1 REQUIRES

perl5.005, Term::ANSIColor, Mail::vpopmail, vpopmail 5.4.10+, Unix::ServiceConfig

=cut

#use Apache::Admin::Config;
use Term::ANSIColor;
use Unix::ServiceConfig;
use vpopmail;

@ISA = qw(Unix::ServiceConfig);

my $VERSION   = '0.01';
my $REVISION  = sprintf("%d.%02d", q$Revision: 1.3 $ =~ /(\d+)\.(\d+)/);

=head1 CLASS VARIABLES

=over

=item B<$valid_actions>

The valid actions for this class are: add, del, delete, edit, 
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
  Usage    : my $sc = Unix::ServiceConfig->new(
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
		'check'     => 'Qmail+Vpopmail',
		'me'        => 'mail',
		'class'     => 'vpopmail',
		'base_type' => 'domain',
		'debug'     => 0,
		'main'      => 1,
		'commands'  => [ $config{'command-restart'} ],
		'error'     => {
			'exists' => 0,
			'msg'    => '',
		},
		'log'       => {
			'action' => 'unknown',
			'what'   => 'mail',
			'status' => 'unknown',
			'args'   => '',
		}
	};

	bless($self, $class);
	
	return($self);
} #new

=head2 FUNCTIONS: internal

=item B<_is_in_hosts>

  Title    : _is_in_hosts
  Usage    : $self->_is_in_hosts(@args);
  Function : Checks if the domain exists in QMAILDIR/control/rcpthosts or in
             QMAILDIR/control/morercpthosts.
  Returns  : an array (found, _line)
  Args     : $domain : The domain to search for.

=cut

sub _is_in_hosts($)
{
	my ($self, $domain) = @_;
	my ($found, $_line, $file);
	
	$found = 0;
	
	# check the rcpthosts
	$file            = $self->{'config'}->{'directory-qmail'}
	                   . '/control/rcpthosts';
	($found, $_line) = $self->_file_search($file, $domain) 	if ( -e $file );

	# check the more rcpthosts
	$file            = $self->{'config'}->{'directory-qmail'}
	                   . '/control/morercpthosts';
	($found, $_line) = $self->_file_search($file, $domain) 	
	  if ( (0 == $found) && ( -e $file) );

	return($found, $_line);
} # _is_in_hosts

=item B<sort_files>

  Title    : sort_file
  Usage    : $self->sort_file(@args);
  Function : 
  Returns  : 
  Args     : $domain : The domain to search for.

=cut

sub sort_file($)
{
	my ($self, @args) = @_;
	my ($file) = @args;
	my ($fh);
	
	open($fh, $file);
	my @data = <$fh>;
	close($fh);

	open($fh, ">$file");
	foreach my $d (sort @data)
	{
		print $fh $d;
	}
	close($fh);
} # sort_file

=head2 FUNCTIONS: Module specific

=item B<alias>

  Title    : alias
  Usage    : $self->alias(@args);
  Function : Adds an alias to a domain to vpopmail.
  Returns  : an object
  Args     : @args : an array of the arguments to the function. 
                     0 : action : add or delete an alias.
                     1 : domain : the domain for the alias, required for 
                                  the 'add' action.
                     2 : alias  : the alias to operate on.

=cut

sub alias
{
	my ($self, @args) = @_;
	$self->{'log'}->{'args'}   = \@args;
	my ($action, $domain, $alias) = @args;
	$self->{'log'}->{'action'} = $action;

	return($self) if ($action !~ m/^(add|del(ete)?|list|(un)?hold)$/i);

	return($self) if ( ('list' eq $action) && (!$alias) );
	# make sure we have an alias and a domain
	$alias = $self->_get_valid_type_input($alias, 'Alias')  if (!$alias);

	if    ('hold'   eq $action)
	{
		return($self->hold($alias, 1));
	}
	elsif ('unhold' eq $action)
	{
		return($self->unhold($alias, 1));
	}

	# domain is only required for adding not for deleting, otherwise
	# we treat them as domains
	my %arg;
	$arg{'alias'} = $alias;
	$domain = $self->_get_valid_type_input($domain,'',%arg) 
	  if ('add' eq $action);

	$self->_width_to_status("Adding alias ($alias) to ($domain).") 
	  if ($domain);
	$self->_width_to_status("Removing alias ($alias).");

	$self->_print_check_start();
	return($self) if ($self->_print_error());
	$self->_print_ok();

	my $ret;
	if    ('list'     eq $action)
	{
		$self->alias_list($alias); # treat as a domain
	} # list domain aliases
	elsif ('add'      eq $action)
	{
		$self->_pretty_print_start("Adding alias ($alias) to ($domain)");
		$ret = vpopmail::vaddaliasdomain($alias, $domain);
	} # add the alias
	elsif ( ('delete' eq $action)
	     || ('del'    eq $action)
	      )
	{
		$self->_pretty_print_start("Removing alias ($alias).");
		$ret = vpopmail::vdeldomain($alias);
	} # delete user

	if ($ret)
	{
		$self->_set_error(vpopmail::verror($ret));
		return($self) if ($self->_print_error());
	}
	$self->_print_ok();
} # alias

=item B<alias_list>

=cut

sub alias_list($)
{
	my ($self, $domain) = @_;
	my ($fh, %list, %alist);
	my $asize = 0;
	my $file  = $self->{'config'}->{'file-users-assign'};
	$file     = $self->make_path($file);

	# get a list of the domains
	#  vpopmail::vlistdomains didn't get a complete list of every domain
	#  just the real domains. we want to get both
	if ( -e $file )
	{
		open($fh, $file);
		while(my $line = <$fh>)
		{
			chomp($line);
			if ($line =~ m/^\+([^\-]*?)\-:$domain:/)
			{
				my $alias                = $1;
				if ($alias ne $domain)
				{
					my $found                = 0;
					$list{"$alias"}{'held'} = 0;
					$asize = length($alias)  if ( length($alias)  > $asize);
					$alias =~ s/\./\\\./g;
					($found, $line) = $self->_is_in_hosts('^'.$alias.'$');
					$alias =~ s/\\\./\./g;
					$list{"$alias"}{'held'}  = 1      if (-1 == $found);
				}
			} # valid line
		}
		close($fh);
	}

	$self->_print('', "Aliases found for ($domain):");
	$self->_die_print('  No domains found') if (0 == keys(%list)); # list
	my $count = 1;
	foreach my $l (sort keys %list)
	{
		next if ($list{"$l"}{'alias'});
		my $a     = sprintf('%-'.$asize.'s',  $l);
		my $held  = (1 == $list{"$l"}{'held'}) ? '(held)' : '';
		my $line  = sprintf(' %s  %s', $a, $held);

		$self->_print_list_line($count, $line, $list{"$l"}{'held'});
		$count++;
	}
	exit(0);
} #alias_list
=head2 FUNCTIONS: Filled in Stubs

=item B<add>

  Title    : add
  Usage    : $self->add(@args);
  Function : Adds a domain to vpopmail.
  Returns  : an object
  Args     : @args : an array of the arguments to the function. 
                     The first argument must be the domain, if it isn't supplied
                     it will ask for one.

=cut

sub add
{
	my ($self, @args) = @_;
	$self->{'log'}->{'args'}   = \@args;
	$self->{'log'}->{'action'} = 'add';
	my ($domain, $location) = @args;
	my $ret;

	# get the domain
	$domain = $self->_get_valid_type_input($domain);

	if (1 == $self->{'error'}->{'exists'})
	{
		$self->_print_check_start();
		return($self) if ($self->_print_error());
	}

	my $main_account = $self->{'config'}->{'postmaster-account'};
	my $main_name    = $self->{'config'}->{'postmaster-name'};
	my $uid          = $self->_get_uid($self->{'config'}->{'vpopmail-uid'}, 
	                               'vpopmail');
	my $gid          = $self->_get_gid($self->{'config'}->{'vpopmail-gid'}, 
	                               'vchkpw');
	my $dir          = $self->{'config'}->{'directory-main'};

	my ($pass, $display_pass, $use_random) = $self->get_password($domain);

	$self->_print_check_start();
	return($self) if ($self->_print_error());
	$self->_print_ok();

	if ($self->_is_enabled($use_random))
	{
		$self->_pretty_print_start('Postmaster password');
		$self->_pretty_print_end('bold blue', $pass);
	}

	# Try adding the domain
	$self->_pretty_print_start("Adding ($domain) to vpopmail");
	if ($ret = vpopmail::vadddomain($domain, $dir, $uid, $gid))
	{
		$self->_set_error(vpopmail::verror($ret));
	}
	return($self) if ($self->_print_error());

	if ($ret = vpopmail::vadduser($main_account, $domain, $pass, $main_name, 0))
	{
		$self->_set_error(vpopmail::verror($ret));
	}
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
	my $domain      = $self->{'data'}->{'domain'};
	
	push(@args, $domain);
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
  Function : Deletes a domain from the vpopmail configuration.
  Returns  : an object
  Args     : @args : an array of the arguments to the function. 
                     The first argument must be the domain, if it is not supplied
                     it will ask for one.

=cut

sub del
{
	my ($self, @args) = @_;
	$self->{'log'}->{'args'} = \@args;
	$self->{'log'}->{'action'} = 'del';
	my ($domain) = @args;
	my ($fh, $ret);

	# get the domain
	$domain = $self->_get_valid_type_input($domain);

	if (1 == $self->{'error'}->{'exists'})
	{
		$self->_print_check_start();
		return($self) if ($self->_print_error());
	}

	if ($self->_is_enabled($self->{'config'}->{'verbose'}))
	{
		print("This will remove all email for ($domain) and\n aliases associated to this domain.\n");
		my $_c = $self->_get_yesno('Continue', 'Y');
		$self->_set_error('Aborted by user') if (!$self->_is_enabled($_c));
	}

	$self->_width_to_status("Removing ($domain) from vpopmail");

	$self->_print_check_start();
	return($self) if ($self->_print_error());
	$self->_print_ok();
	
	$self->_pretty_print_start("Removing ($domain) from vpopmail");
	if ($ret = vpopmail::vdeldomain($domain))
	{
		$self->_set_error(vpopmail::verror($ret));
		return($self) if ($self->_print_error());
	}
	$self->_print_ok();
	
	return($self);
} #del

=item B<extra_domain_checks>

  Title    : extra_domain_checks
  Usage    : $self->extra_domain_checks(@args);
  Function : Performs extra checks on the domain.
  Returns  : an array (found, _line)
  Args     : $domain : The domain to search for.

=cut

sub extra_type_checks($$$$%)
{
	my ($self, $domain, $what, $e, $h, %args) = @_;
	
	if ( (2 == $h) && (1 == $e) && ('unhold' eq $what) )
	{
		$self->_set_error("Primary domain is on hold ($domain).");
		return(2);
	}
	return(0);
} # extra_type_checks

=item B<hold>

  Title    : hold
  Usage    : $self->hold(@args);
  Function : Puts a domain on hold in vpopmail.
  Returns  : an object
  Args     : @args : an array of the arguments to the function. 
                     The first argument must be the domain, if it isn't supplied
                     it will ask for one.

=cut

sub hold
{
	my ($self, @args) = @_;
	$self->{'log'}->{'args'} = \@args;
	$self->{'log'}->{'action'} = 'hold';
	my ($domain, $alias) = @args;
	my ($fh, $th);
	my (@lines, @extras, @errors);
	$alias = 0 if (!$alias);
	$domain = $self->_get_valid_type_input($domain);

	if (1 == $self->{'error'}->{'exists'})
	{
		$self->_print_check_start();
		return($self) if ($self->_print_error());
	}

	if ($self->_is_enabled($self->{'config'}->{'verbose'}))
	{
		print("This will place aliases associated to ($domain) on hold as well.\n");
		my $_c = $self->_get_yesno('Continue', 'y');
		$self->_set_error('Aborted by user') if (!$self->_is_enabled($_c));
	}
	my $file  = $self->{'config'}->{'file-users-assign'};
	$file     = $self->make_path($file);

	$self->_width_to_status("Holding ($domain) in vpopmail");

	$self->_print_check_start();
	return($self) if ($self->_print_error());
	$self->_print_ok();

	$self->_pretty_print_start("Holding ($domain) in vpopmail");
	if (! -e $file )
	{
		$self->_set_error("Error opening ($file): file not found");
		return($self) if ($self->_print_error());
	}

	# get the domain and the aliases
	open($fh, $file);
	while(my $line = <$fh>)
	{
		chomp($line);
		if ($line =~ m/^\+([^\-]*?)\-:([^:]*)/)
		{
			push(@lines, $1) if (lc($2) eq lc($domain));
		} # the domain or an alias
	}
	close($fh);

	# remove from the rcpthosts
	$file  = $self->{'config'}->{'directory-qmail'}.'/control/rcpthosts';
	if (! -e $file)
	{
		$self->_set_error("Error opening ($file): file not found");
		return($self) if ($self->_print_error());
	} # this file must exist

	my $f = 0;
	while(my $line = pop(@lines))
	{
		my ($found, $_line) = $self->_file_search($file, "^$line\$");
		if (-1 != $found)
		{
			$f = 1;
			if (-1 == $self->_file_delete_line($file, $found))
			{
				push(@errors, $line);
				$f = 0 if (!$f);
			}
		} # found it
		else
		{
			push(@extras, $line);
			$f = 0 if (!$f);
		}
	} # search the rcpthosts

	if (1 == $alias)
	{
		my ($found, $_line) = $self->_file_search($file, "^$domain\$");
		if (-1 != $found)
		{
			$f = 1;
			if (-1 == $self->_file_delete_line($file, $found))
			{
				push(@errors, $domain);
				$f = 0 if (!$f);
			}
		} # found the alias
		else
		{
			push(@extras, $domain);
		}
	} # aliases are not found in the above search

	$self->sort_file($file) if (1 == $f);
	
	$file  = $self->{'config'}->{'directory-qmail'}.'/control/morercpthosts';
	if ( ( -e $file ) && (0 < $#extras) )
	{
		# this time we use the extras because they were not found in the 
		# rcpthosts
		$f = 0;
		while(my $line = pop(@extras))
		{
			my ($found, $_line) = $self->_file_search($file, "^$line\$");
			if (-1 != $found)
			{
				if (-1 == $self->_file_delete_line($file, $found))
				{
					push(@errors, $line);
					$f = 0 if (!$f);
				}
				$f = 1;
			}
			else
			{
				push(@errors, $line);
				$f = 0 if (!$f);
			}
			# ignore any errors that this leaves
		} # search the rcpthosts

		# we need to rebuild this file if needed
		$self->_run_cmd('qmail-newmrh') if (1 == $f);
	} # it is not critical if this file doesn't exist

	if (0 < $#errors)
	{
		$self->_set_error("Error removing the following rcpthosts: \n"
		                  . join(', ', @errors));
	} # we had errors
	return($self) if ($self->_print_error());

	$self->_print_ok();
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

	my ($search) = @args;

	my $dcount = my $acount = 1;
	my ($fh, $_line, %list, %alist);
	my $found = my $dsize = my $csize = my $asize = 0;
	my $file  = $self->{'config'}->{'file-users-assign'};
	$file     = $self->make_path($file);

	$self->_print_check_start();
	return($self) if ($self->_print_error());
	$self->_print_ok();

	# get a list of the domains
	#  vpopmail::vlistdomains didn't get a complete list of every domain
	#  just the real domains. we want to get both
	if ( -e $file )
	{
		open($fh, $file);
		while(my $line = <$fh>)
		{
			chomp($line);
			if ($line =~ m/^\+([^\-]*?)\-:([^:]*)/)
			{
				my $domain               = $1;
				my $alias                = $2;
				$found                   = 0;
				$list{"$domain"}{'held'} = 0;

				$dsize = length($domain) if ( length($domain) > $dsize);
				$asize = length($alias)  if ( length($alias)  > $asize);
				
				# make .'s be \.'s
				$domain =~ s/\./\\\./g;
				# check if it is on hold
				($found, $_line) = $self->_is_in_hosts('^'.$domain.'$');

				$domain =~ s/\\\./\./g;
				$list{"$domain"}{'held'}  = 1      if (-1 == $found);
				if ($alias ne $domain)
				{
					$list{"$domain"}{'alias'} = $alias;
					$acount++;
				}
				else
				{
					$dcount++;
				}
			} # valid line
		}
		close($fh);
	}

	# print the list
	$csize = length(keys(%list));
	$csize  = 4 if (4 > $csize);
	$asize  = 9 if (9 > $asize);
	$dsize  = 6 if (6 > $dsize);

	printf("Domains found:\n");
	printf("\%${csize}s  ",  ' ');
	printf("\%-${dsize}s  ", 'Domain');
	printf("Flags\n");
	$self->_die_print('  No domains found') if (0 == $dcount); # list
	$dcount = 1;
	foreach my $l (sort keys %list)
	{
		next if ($list{"$l"}{'alias'});
		my $c     = sprintf('%'.$csize.'s.',  $dcount);
		my $d     = sprintf('%-'.$dsize.'s',  $l);
		my $held  = (1 == $list{"$l"}{'held'}) ? '(held)' : '';
		my $line  = sprintf(' %s  %s', $d, $held);

		$self->_print_list_line($dcount, $line, $list{"$l"}{'held'});
		$dcount++;
		delete($list{"$l"});
	}

	# aliases
	printf("\nAliases found:\n");
	printf("\%${csize}s  ",  ' ');
	printf("\%-${dsize}s  ", 'Domain');
	printf("\%-${asize}s  ", 'Alias For');
	printf("Flags\n");
	$self->_die_print('  No Aliases found') if (0 == $acount); # list
	$acount = 1;
	foreach my $l (sort keys %list)
	{
		my $c     = sprintf('%'.$csize.'s.',  $acount);
		my $a     = sprintf('%-'.$asize.'s', ($list{"$l"}{'alias'}) ? 
		          $list{"$l"}{'alias'} : 
		          ' ');
		my $d     = sprintf('%-'.$dsize.'s',  $l);
		my $held  = (1 == $list{"$l"}{'held'}) ? '(held)' : '';
		my $line  = sprintf(' %s  %s  %s', $d, $a, $held);
		
		$self->_print_list_line($acount, $line, $list{"$l"}{'held'});
		$acount++;
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

sub type_exists($)
{
	my ($self, $domain, %args) = @_;
	my ($fh, $_line);
	my $exists = my $found = my $held = my $dom = my $flag = 0;

	return(-1, -1) if (!$domain);

	if ($args{'sub'} && ('user' == $args{'sub'}) )
	{
		($exists, $held) = $self->_user_exists($domain, $args{'user'});
		return($exists, $held);
	} #operating on an user
	
	if ($args{'alias'})
	{
		$flag = 1; # tell the function to return 2 as the hold type
		
	} #operating on an alias

	# we only test the file that we are given
	my $file = $self->{'config'}->{'file-users-assign'};
	$file    = $self->make_path($file);
#book
	if (!$file)
	{
		$self->_set_error('Invalid file specified in configuration.');
		return(-1, -1);
	}

	if ( -e $file )
	{
		if (!open($fh, $file))
		{
			$self->_set_error('Invalid file specified in configuration.');
			return(-1, -1);
		}
		while(my $line = <$fh>)
		{
			if ($line =~ m/^\+$domain\-:([^:]*)/i)
			{
				$exists = 1;
				($found, $_line) = $self->_is_in_hosts('^'.$domain.'$');
				$held = 1 if (-1 == $found);
				
				# check if the alias is on hold
				if ( ($1 ne $domain) || (1 == $flag) )
				{
					($found, $_line) = $self->_is_in_hosts('^'.$1.'$');
					$held = 2 if (-1 == $found);
				}
				$exists = 2 if (1 == $flag);
				last;
			} # doain exists
		}
		close($fh);
	}
	return ($exists, $held);
} #type_exists

=item B<unhold>

  Title    : unhold
  Usage    : $self->unhold(@args);
  Function : Removes a domain from hold in vpopmail.
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
	my ($domain, $alias) = @args;
	my ($fh, @lines);
	$alias = 0 if (!$alias);

	$domain = $self->_get_valid_type_input($domain);

	if (1 == $self->{'error'}->{'exists'})
	{
		$self->_print_check_start();
		return($self) if ($self->_print_error());
	}

	if ($self->_is_enabled($self->{'config'}->{'verbose'}))
	{
		print("This will place aliases associated to ($domain) on hold as well.\n");
		my $_c = $self->_get_yesno('Continue', 'y');
		$self->_set_error('Aborted by user') if (!$self->_is_enabled($_c));
	}
	my $file  = $self->{'config'}->{'file-users-assign'};
	$file     = $self->make_path($file);

	$self->_width_to_status("Reactivating ($domain) in vpopmail");

	$self->_print_check_start();
	return($self) if ($self->_print_error());
	$self->_print_ok();

	$self->_pretty_print_start("Reactivating ($domain) in vpopmail");
	if (! -e $file )
	{
		$self->_set_error("Error opening ($file): file not found");
		return($self) if ($self->_print_error());
	}

	# get the domain and the aliases
	if (!open($fh, $file))
	{
		$self->_set_error("Error opening ($file): $!");
		return($self) if ($self->_print_error());
	}
	while(my $line = <$fh>)
	{
		chomp($line);
		if ($line =~ m/^\+([^\-]*?)\-:([^:]*)/)
		{
			push(@lines, lc($1)) if (lc($2) eq lc($domain));
		} # the domain or an alias
	}
	close($fh);

	# add to the rcpthosts
	$file  = $self->{'config'}->{'directory-qmail'}.'/control/rcpthosts';
	if (! -e $file)
	{
		$self->_set_error("Error opening ($file): file not found");
		return($self) if ($self->_print_error());
	} # this file must exist
	while(my $line = pop(@lines))
	{
		if (49 > $self->_file_line_count($file))
		{
			my ($found, $_line) = $self->_file_search($file, '^'.$line.'$');
			if (-1 == $found)
			{
				$self->_file_append($file, "$line\n");
				return($self) if ($self->_print_error());
			} # ignore if already active
		} # we can add to the rcpthosts
		else
		{
			push(@lines, $line);
			last;
		} # put it back on the top and then break out of the loop
	}
	if (1 == $alias)
	{
		if (49 > $self->_file_line_count($file))
		{		
			my ($found, $_line) = $self->_file_search($file, "^$domain\$");
			if (-1 == $found)
			{
				$self->_file_append($file, "$domain\n");
				return($self) if ($self->_print_error());
			} # ignore if already active
		} # found the alias
		else
		{
			push(@lines, $domain);
		}
	} # aliases are not found in the above search
	$self->sort_file($file); # just incase it can't hurt that much

	# add them to the morercpthosts
	$file  = $self->{'config'}->{'directory-qmail'}.'/control/morercpthosts';
	if (0 < $#lines)
	{
		while(my $line = pop(@lines))
		{
			my ($found, $_line) = $self->_file_search($file, '^'.$line.'$');
			if (-1 == $found)
			{
				if (!-e $file)
				{
					$self->_file_create($file, "$line\n");
					return($self) if ($self->_print_error());
				} # create the file if needed
				else
				{
					$self->_file_append($file, "$line\n");
					return($self) if ($self->_print_error());
				}
			} # ignore if already active
		} #add to morercpthosts
		# rebuild the mrh
		$self->sort_file($file); # just incase it can't hurt that much
		$self->_run_cmd('qmail-newmrh');
	} # add to the morercpthosts
	return($self) if ($self->_print_error());
	$self->_print_ok();
} #unhold

1;

__END__

=pod

=back

=head2 BASIC MODULE SETUP

Currently there is only a Bind 9 module.
Currently there is only an apache module (tested on apache 2.1.14).
Currently there is only a vpopmail module.
Currently there is only a mysql module (tested on mysql 4.1.16).
Currently there is only a freebsd module. (tested on FreeBSD 6.1-STABLE).

=head1 AUTHOR INFORMATION

Copyright 2006, David R. Lundgren. All rights reserved.

This library is licensed under the SyberIsle Productions License (SIPL).

Address bug reports and comments to: dlundgren@syberisle.net. When sending
bug reports, please provide the version of Unix::ServiceConfig.pm, the version of Perl,
the name and version of any Server that is giving problems, and the name and
version of your operating system. If the problem is based around a Windows
Installation then I cannot provide support as I do not run windows machines.

=head1 CREDITS

Thanks to the following for being (un)willing recipients of the script for
server administration:

=over 4

=item HawaiiLink Internet (http://www.hawaiilink.net)

=item Islands Internet (http://www.islands.net)

=back

=head1 BUGS

Please report any you may find.

=cut
