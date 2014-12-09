######################################################################
#
# Unix/ServiceConfig.pm
#
# Copyright (C) 2006-2014 David Lundgren. All Rights Reserved
#
# MIT License
#
######################################################################

=pod

=head1 NAME

Unix::ServiceConfig - Service Configuration Interface Class

=head1 SYNOPSIS

	use Unix::ServiceConfig;

	my $action = 'add';
	my @args = [ 'test.com' ];

	my $ServiceConfig = Unix::ServiceConfig::new(
		-type    => 'dns'
		-file    => 'file.conf',
		-action  => $action);

	$ServiceConfig->execute(@args);

=cut

package Unix::ServiceConfig;

no warnings 'portable';
use 5.6.0;
use strict;
use warnings;

=head1 REQUIRES

perl5.006, Term::ReadKey, Term::ANSIColor

=cut

# Load some key modules
use Term::ReadKey;
use Term::ANSIColor;

=head1 EXPORTS

None.

=head1 DESCRIPTION

This library uses various modules to make it easier to add, hold, unhold, list, 
and delete users or domains from the various services that may be running on a
given system. This package defines the base functions that make up the core.
There are currently the following main packages for system configuration:

=over

=item 1. dns - interacts with the dns system

=item 2. web - interacts with the web system

=over 4

=item 1. apache - apache interface

=item 2. awstats - awstats interface

=back

=item 3. mail - interacts with the mail system

=item 4. db - interacts with the database server

=item 5. user - interacts with the primary system

=back

=head1 USING

No functions are exported.

=head1 CORE FUNCTIONS

These functions form the base of the SystemConfig.

=cut

# Default Information for this module
our $DEBUG    = 1;
our $next;
our $recursion;
my $VERSION   = '0.01';
my $REVISION  = sprintf("%d.%02d", q$Revision: 1.3 $ =~ m/(\d+)\.(\d+)/);
our $actions;

=over 2

=item B<new>

  Title    : new
  Usage    : my $sc = ServiceConfig->new(
                -type    => 'dns',
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

=cut

sub new {
	my($pkg, %hash) = @_;
	my ($ref, $conf, $config, $type, $special_run);

	# determine our global module (dns/mail/web/domain/user/mysql)
	$hash{'type'} =   'generic' if (!$hash{'type'});
	$pkg->usage() if ('generic' eq $hash{'type'});

	# check if we have the configuration variables that are needed
	if ( (!$hash{'config'}) || (!$hash{'generic'}) )
	{
		# we load both if one is missing
		my %c    = $pkg->_parse_configuration($hash{'file'});
		my $type = $hash{'type'};
		$conf    = $c{"$type"};
		$config  = $c{'generic'};
	}
	else
	{
		$conf   = $hash{'config'};
		$config = $hash{'generic'};
	}

	if ($hash{'not_main'})
	{
		$hash{'type'} = ($config->{'base'}) ? 
		                 lc($config->{'base'}) :  $hash{'type'};
		$type         = ($config->{'type'}) ?
		                 lc($config->{'type'}) : 'base';
	}
	else
	{
		$hash{'type'} = ($conf->{'base'}) ? 
		                 lc($conf->{'base'}) :  $hash{'type'};
		$type         = ($conf->{'type'}) ? 
		                 lc($conf->{'type'}) : 'base';
	}

	# Use terminal color or not
	$ENV{ANSI_COLORS_DISABLED} = 1 if (${$config}{'terminal-color'} !~ m/^y/i);

	# setup the name of the class to call
	my $class = 'Unix::ServiceConfig::' . $hash{'type'} . '::' . $type;

	# eval is good on its own but doesn't provide a good error message system
	# to the user, it just prints out that it can't locate it.
	my $cfile = $class;
	
	# We check all the inc directories and the directory-library for
	# the file before we error out
	$cfile    =~ s/::/\//g;
	foreach my $_inc (@INC)
	{
		if (-e "$_inc/$cfile.pm")
		{
			$cfile = "$_inc/$cfile.pm";
			last;
		}
	}
	if (!-e $cfile)
	{
		$cfile    = ${$config}{'directory-library'}.'/'.$cfile.'.pm';
	} # check the directory-library last if $cfile doesn't exist


	$special_run = 0;
	if ( (!-e $cfile) && (${$conf}{'run-sections'}) )
	{
		# We need to run the sections specified and in order to do that
		# we call Unix::ServiceConfig::Run.pm because it is our
		# class for running sections that only have a run-section
		# defined.
		$class          = 'Unix::ServiceConfig::Run';
		$special_run    = $hash{'action'};
		$hash{'action'} = 'ask_action';
		$cfile          = 'RUN';
#		$special_run    = 1;
	} # reddefine the class
	elsif (!-e $cfile)
	{
		$pkg->_error('ERROR; Class not available');
		$pkg->_error("ERROR: ($class) in (".
		             ${$config}{'directory-library'}.")");
		$pkg->usage();
	}

	eval "require $class";

	if(!$@)
	{
		$ref = $class->new($conf, $config, $hash{'file'}, $hash{'action'});
		my $actions = $ref->valid_actions();
		my $valid = 0;

		$ref->usage() if ('usage' eq $hash{'action'});

		if ($hash{'action'} !~ m/^ask_action$/i)
		{
			foreach my $a (@{$actions})
			{
				$valid = 1 if (lc($a) eq lc($hash{'action'}));
			}
		}
		else
		{
			$valid = 1;
		}

		if (1 != $valid)
		{
			my $err = 'Invalid command option specified ('.$hash{'action'}.
			  ").\nAvailable options for the (".$hash{'type'}.') command are '.
			  join(', ', @{$actions})."\n";
			$pkg->_die_print($err); # new
		}
	}
	else 
	{
		warn($@);
		$pkg->_die_print("failed to load $type",0); # new
	}

	if ( (!$hash{'main'}) && ($hash{'extra'}) )
	{
		$ref->_set_extra($hash{'extra'});
	} # set the extras if there are any
	
	if ($special_run)
	{
		$ref->_run_sections($special_run);
		exit(0);
	}
	return($ref);
} #new

=item B<UNFINISHED FUNCTIONS>

=cut

########## NOT DONE FUNCTIONS ##########
# system      :: _run_command
# interaction :: _run_sections

=item B<ask_action_exists>

FILL ME IN!

=cut

sub ask_action_exists($$)
{
	my ($self, $what, $type_display, $data) = @_;
	my ($e, $h) = $self->type_exists($data);

	if ( ('add' eq $what) && (1 == $e) )
	{
		$self->_set_error("$type_display already exists ($data).");
		return($data);
	}
	elsif ( ('add' ne $what) && (1 != $e) )
	{
		$self->_set_error("$type_display doesn't exist ($data).");
		return($data);
	}
	elsif ( (1 == $h) && ($what ne 'unhold') )
	{
		$self->_set_error("$type_display is on hold ($data).");
		return($data);
	}
	elsif ( (1 != $h) && ($what eq 'unhold') )
	{
		$self->_set_error("$type_display is already active ($data).");
		return($data);
	}

} # ask_action_exists

=item B<_print_section_run>

FILL ME IN!

=cut

sub _print_section_run
{
	my ($self) = @_;
	
	print("\n");
	my $output = 'Running Section: ' . $self->{'check'};
	my $color = 'Running Section: '
	           . color('bold blue')
	           . $self->{'check'}
	           . color('reset');

	$self->_pretty_print_start($color, length($color)-length($output));
} #_print_section_run

=item B<_run_command>

  Title    : _run_command
  Usage    : $sc->_run_command($action)
  Function :
  Returns  :
  Args     : none

=cut

sub _run_command
{
	my ($self) = @_;
	my ($output);

	return(-1) if (!$self->{'config'}->{'run-command'});

	if ($self->_is_enabled($self->{'config'}->{'no-run'}))
	{
		$self->{'config'}->{'no-run'} = 0;
		return(-1);
	}

	my $action = $self->{'log'}->{'action'};
	my $run    = $self->{'config'}->{'run-command'};

	$output = 'Starting'   if ('start'   eq $run);
	$output = 'Restarting' if ('restart' eq $run);
	$output = 'Stopping'   if ('stop'    eq $run);
	$output = 'Notifying'  if (!$output);
	
	# there are two components to the run commands
	#  1) the command to run
	#  2) when to run them (comma separated or blank for all)
	# i.e. - "restart;add,del,
	return($self) if ( ($run =~ m/;/i) && ($run =~ m/$action/i) );

	$self->_pretty_print_start("$output service (".$self->{'check'}.')');

	if (-1 == $self->_run_cmd($run, 1))
	{
		$self->_set_error("Error $output service");
	}
	return($self) if ($self->_print_error());
	$self->_print_ok();
} #_run_command

=item B<_run_sections>

  Title    : _run_sections
  Usage    : $sc->_run_sections($action)
  Function : Parses the configuration variable "run-sections" and then calls
             $obj->ask_action for each module found in "run-sections".
  Returns  :
  Args     : $action : What the object will be expected to perform.

=cut

sub _run_sections($)
{
	my ($self, $action) = @_;
	my $section_line  = $self->{'config'}->{'run-sections'};
	return(-1) if ($self->{'done'});

	my $config_file   = $self->{'file'};
	my $count=1;
	return(0) if (!$section_line);

	my $_s = $section_line;
	my @sections = split(',', $section_line);
	my $data = ($self->{'section'}->{'extra'}) ?
		$self->{'section'}->{'extra'} :
		{ };
#	foreach my $s (@sections)
	my $i;
	for($i = 0, my $s = $sections[$i];
	    $i <= $#sections; 
	    $i++, $s = $sections[$i])
	{
		next if (!$s);
		
		my %config = $self->_parse_configuration($config_file);

		my %conf;
		# merge the generic with the modules
		if ($config{lc($s)}->{'base'})
		{
			my $base = $config{lc($s)}->{'base'};
			%conf = $self->_merge_config(
			  $base,
			  $config{'generic'},
			  $config{$base}
			);
			%conf    = $self->_merge_config(
				lc($s),
				$config{lc($s)},
				\%conf
			);
		}
		else
		{
			%conf = %{$config{lc($s)}};
			%conf    = $self->_merge_config(
				lc($s),
				$config{lc($s)},
				$config{'generic'}
			);
		}

		# the sections configuration is the generic configuration for this
		# and the callers $self->{'section'}->{$section} is the
		# more module specific configuration especially for passing along
		# things such as 
		#  domain(real, alias, location), 
		#  user(name, id, gid, real_home, apache_home)
		# This gets put into the hash as {'extra'} and is 
		#  not in the configuration area unless it is under {$section_config}
		my $confm = ($self->{'section'}->{lc($s)}) ?
			$self->{'section'}->{lc($s)} :
			{ }; 
		my $execute = new Unix::ServiceConfig(
			'type'     => lc($s),
			'file'     => $config_file,
			'not_main' => 1,
			'config'   => $confm,
			'extra'    => $data,
			'action'   => 'ask_action',
			'generic'  => \%conf,
		);
		$execute->ask_action($action);
		$execute->_run_command();

		# we need to get the extra section back from the called file so that 
		# we can update the $data that we have since we might have new 
		# information that needs to be used in another section
		my %d      = %{$data};
		my $_extra = $execute->_get_extra();

		if (ref($_extra) eq 'HASH')
		{
			my %_e     = %{$_extra};
			foreach my $key (sort keys %_e)
			{
			# currently we do not clobber existing data
				next if ($data->{"$key"}); 
				$data->{"$key"} = $_e{"$key"};
			} # loop through the extra data
		}
		if ($i == $#sections)
		{
			return(0);
		}
	} # done with the sections
	$self->{'done'} = 1;
	return(0);
} #_run_sections

=item B<_log_event>

  Title    : _log_event
  Usage    : $self->_log_event();
  Function : 
  Returns  : 
  Args     : 

=cut

sub _log_event()
{
	my ($self) = @_;
	my ($_status, $_user, $_date, $_options);
	
	return(0) if (!$self->{'config'}->{'log-events'});

	my $action = $self->{'log'}->{'action'};
	my $status = $self->{'log'}->{'status'};
	my $what   = $self->{'log'}->{'what'};
	#no strict refs;
	my @args   = @{$self->{'log'}->{'args'}};
	#user strict;
	
	my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime time;
	my $log = $self->{'config'}->{'log-format'};
	my $file = $self->{'config'}->{'log-file'};
	
	# turn the status into a symbol
	$_status = '!' if ($status =~ m/^e/i); #('error' eq $status));
	$_status = '~' if ($status =~ m/^s/i); #('success' eq $status));
	$_status = '@' if (!$_status);
	
	# turn the action into a symbol
	$_status = $_status.'+' if ($action =~ m/^a/i); #'add'    eq $action);
	$_status = $_status.'-' if ($action =~ m/^d/i); # ('del' eq $action) || ('delete' eq $action) );
	$_status = $_status.'>' if ($action =~ m/^h/i); #'hold'   eq $action);
	$_status = $_status.'<' if ($action =~ m/^u/i); #'unhold' eq $action);
	$_status = $_status.'%' if ($action =~ m/^l/i); #'list'   eq $action);
	$_status = $_status.'?' if (!(2 <= length($_status)));

	$_date = (1900+$year).".$mon.$mday:$hour:$min:$sec";
	$_user = getlogin();
	chomp($_user);

	$_options = '';
	foreach my $o (@args)
	{
		$_options = $_options.':'.$o;
	}
	
	$_options =~ s/^://i;
	$log =~ s/date/$_date/i;
	$log =~ s/user/$_user/i;
	$log =~ s/status/$_status/i;
	$log =~ s/what/$what/i;
	$log =~ s/options/$_options/i;
	
	$log = $log . "\n";
	
	my $fh;
	open($fh, ">>$file");
	print $fh $log;
	close($fh);
} #_log_event

=item B<FINISHED>

=cut

########## FINISHED FUNCTIONS ##########
#
# Error Handling
#

=item B<Error Handling>

=item B<_error>

  Title    : _error
  Usage    : $self->_error('No such user');
  Function : Prints $message to the terminal in 'red'.
  Returns  :
  Args     : $message : The message to print out.

=cut

sub _error($)
{
	my ($self, $msg) = @_;
	print color('red');
	print $msg,"\n";
	print color('reset');
} #_error

=item B<_die_error>

  Title    : _die_error
  Usage    : $self->_die_error('No such user', 11);
  Function : Prints $message to the terminal in 'red', and then exits with
             $status_code.
  Returns  : 
  Args     : $message     : The message to print out.
             $status_code : The status code to exit with. [optional]
                            Defaults to 1 if not specified

=cut

sub _die_error($$)
{
	my ($self, $msg, $code) = @_;
	$code = -1 if (!$code);
	$self->_error($msg);
	exit($code); # _die_error
} #_die_error

=item B<_print_check_start>

  Title    : _print_check_start
  Usage    : $self->_print_check_start();
  Function : Calls $self->_error if an error message exists.
  Returns  :
  Args     : $flag : whether or not this is main

=cut

sub _print_check_start
{
	my ($self, $msg) = @_;
	
	$msg = 'Checking '.$self->{'check'}.' configuration';
	$self->_width_to_status($msg);
	$self->_pretty_print_start($msg);
} #_print_check_start

=item B<_print_error>

  Title    : _print_error
  Usage    : $self->_print_error();
  Function : Calls $self->_error if an error message exists.
  Returns  :
  Args     : $flag : Whether or not to die if there is an error.
                     This is useful if there is still more processing
                     that the caller wants to handle.

=cut

sub _print_error
{
	my ($self, $flag) = @_;

	# fail or skip
	$self->_print_fail() if (1 == $self->{'error'}->{'exists'});
	$self->_print_skip() if (2 == $self->{'error'}->{'exists'});

	if (1 <= $self->{'error'}->{'exists'})
	{
		$self->{'error'}->{'exists'} = 0; # reset the error flag
		$self->{'config'}->{'no-run'} = 1;

		if ( ($self->{'main'}) && (!$flag) )
		{
			$self->_die_error($self->{'error'}->{'msg'}, 1); # _print_error (main)
		} # 'main' module and allowed to exit
		else
		{
			$self->_error($self->{'error'}->{'msg'});
			return(-1);
		} # could be 'main' module and allowed exit
	}
	return(0);
} #_print_error

=item B<_set_error>

  Title    : _set_error
  Usage    : $self->_set_error('No such user');
  Function : Sets the error message and existence flag in the error hash.
  Returns  :
  Args     : $message : The message to print out 

=cut

sub _set_error($)
{
	my ($self, $msg, $errno) = @_;

	# default for exists is 1 but if $not_main is set then we want it to be
	# 2 because that means that we skip whatever is happening
	if (!$errno)
	{
		$errno = 1 if ($self->{'main'});
		$errno = 2 if (!$self->{'main'});
	} # allow the user to set the errno otherwise default base on main

	$self->{'error'}->{'msg'}    = $msg;
	$self->{'error'}->{'exists'} = $errno;
} #_set_error

=item B<Screen Output>

=item B<_die_print>

  Title    : _die_print
  Usage    : $self->_die_print('No such user', 0);
  Function : Prints $message to the terminal, and optionally logs the event. 
             Will then exit with a status of 1.
  Returns  :
  Args     : $message  : The message to to print out.
             $log_flag : Whether or not to log the event. [optional]

=cut

sub _die_print($;$)
{
	my ($self, $msg, $log) = @_;
	$log = 0 if (!$log);
	if (1 == $log)
	{
		$self->{'log'}->{'status'} = 'error';
		$self->_log_event();
	}
	print $msg,"\n";
	print color('reset');
	exit(1); # _die_print
} #_die_print

=item B<_pretty_print_start>

  Title    : _pretty_print_start
  Usage    : $self->_pretty_print_start('Checking Configuration');
  Function : Prints $message to the terminal with spacing set from the
             configuration variable "width-to-status".
  Returns  :
  Args     : $message : The message to print out.

=cut

sub _pretty_print_start($)
{
	my ($self, $msg, $offset) = @_;
	my $width = $self->{'config'}->{'width-to-status'};

	$width += $offset if ($offset);

	printf('%-'.$width.'s', $msg);
} #_pretty_print_start

=item B<_pretty_print_end>

  Title    : _pretty_print_end
  Usage    : $self->_pretty_print_end('green', 'OK');
  Function : Prints $message to the terminal in the specified $color using the
             configuration variable "width-status" to center the $message
             between brackets.
  Returns  :
  Args     : $color   : The color to use for printing the $message.
             $message : The message to print out.
  Example  : [ OK ] 

=cut

sub _pretty_print_end($$)
{
	my ($self, $color, $msg) = @_;
	$color = 'reset' if (!$color);
	my $width = $self->{'config'}->{'width-status'};

	$msg =~ s/(^\s+|\s+$)//g;
	
	# Can't remember where I found the formula for centering
	my $left  = int(($width - length($msg)) / 2);
	my $right = $width - $left - length($msg);
	
	print('          [ ');
	print(color($color));
	printf('%'.$left.'s',' ') if ($left > 0);
	print($msg);
	print(color('reset'));
	printf('%'.$right.'s',' ') if ($right > 0);
	print(" ]\n");
} #_pretty_print_end

=item B<_print>

  Title    : _print
  Usage    : $self->_print('green', 'Engage');
  Function : Prints $message to the terminal in the specified $color.
  Returns  :
  Args     : $color   : The color to use for printing the $message.
             $message : The message to print out.

=cut

sub _print($$)
{
	my ($self, $color, $msg) = @_;
	print color($color) if ($color);
	print $msg,"\n";
	print color('reset');
} #_print

=item B<_print_debug>

  Title    : _print_debug
  Usage    : $self->_print_debug('add', 'user to be added: test_user');
  Function : Prints $message to the terminal.
  Returns  :
  Args     : $function : The calling function.
             $message  : The message to print out.
  Example  : DEBUG[add]: user to be added: test_user

=cut

sub _print_debug($$)
{
	my ($self, $func, $msg) = @_;
	if (1 == $self->_is_enabled($self->{'config'}->{'debug-level'}))
	{
		print("DEBUG[$func]: $msg\n");
	}
} #_print_debug

=item B<_print_fail>

  Title    : _print_fail
  Usage    : $self->_print_fail();
             or
             $self->_print_fail(1);
  Function : Prints 'FAIL' to the terminal in 'bold red' by calling 
             $self->_pretty_print_end. Optionally calls $self->_die_error 
             if there is an error and $error_flag is set.
  Returns  :
  Args     : $error_flag : Whether or not to ignore any errors. [optional]
                           Defaults to 0.

=cut

sub _print_fail
{
	my ($self, $flag) = @_;
	$self->_pretty_print_end('bold red', 'FAIL');
} #_print_fail

=item B<_print_list_line>

  Title    : _print_list_line
  Usage    : $self->_print_list_line(10, 'example.com', 0);
  Function : Prints the following to the screen in either red or green:
              c. line
  Returns  :
  Args     : $count : What number to display
             $line  : What to display on the line.
             $held  : Whether to display red (held) or green (not held).

=cut

sub _print_list_line($$$)
{
	my ($self, $count, $line, $held) = @_;
	my $csize = (length($count) > 5) ? length($count) : 5;
	
	my $c     = sprintf('%'.$csize.'s.',  $count);
	my $color = ($self->_is_enabled($held)) ? 
	             color('bold red') : 
	             color('green');

	print(color('yellow').$c.color('reset'));
	print($color.$line.color('reset')."\n");
} # _print_list_line

=item B<_print_ok>

  Title    : _print_ok
  Usage    : $self->_print_ok();
             or
             $self->_print_ok(1);
  Function : Prints 'OK' to the terminal in 'bold green' by calling
             $self->_pretty_print_end.
  Returns  :
  Args     : none 

=cut

sub _print_ok
{
	my ($self) = @_;
	$self->_pretty_print_end('bold green', 'OK');
} #_print_ok

=item B<_print_skip>

  Title    : _print_skip
  Usage    : $self->_print_skip();
             or
             $self->_print_skip(1);
  Function : Prints 'SKIP' to the terminal in 'bold yellow' by calling
             $self->_pretty_print_end. Optionally calls $self->_die_error
             if there is an error and $error_flag is set.
  Returns  :
  Args     : $error_flag : Whether or not to ignore any errors. [optional]
                           Defaults to 0.

=cut

sub _print_skip
{
	my ($self, $flag) = @_;
	$self->_pretty_print_end('bold yellow', 'SKIP');
} #_print_skip

=item B<_width_status>

  Title    : _set_width_status
  Usage    : $self->_set_width_status('printme');
             or
             $width = $self->_width_status();
  Function : Set/get the configuration variable "width-status"
  Returns  : The width information from "width-status"
  Args     : $string : The string to calculate the width from. [optional]

=cut

sub _width_status()
{
	my ($self, $s) = @_;
	
	if ( $s && (length($s) > $self->{'config'}->{'width-status'}) )
	{
		$self->{'config'}->{'width-status'} = length($s);
	}
	elsif (!$s)
	{
		return($self->{'config'}->{'width-status'});
	}
} #_width_status

=item B<_width_to_status>

  Title    : _width_to_status
  Usage    : $self->_width_to_status('printme');
             or
             $width = $self->_width_status();
  Function : Set/get the configuration variable "width-status"
  Returns  : The width information from "width-status"
  Args     : $string : The string to calculate the width from. [optional]

=cut

sub _width_to_status()
{
	my ($self, $s) = @_;
	
	if ( $s && (length($s) > $self->{'config'}->{'width-to-status'}) )
	{
		$self->{'config'}->{'width-to-status'} = length($s);
	}
	elsif (!$s)
	{
		return($self->{'config'}->{'width-to-status'});
	}
} #_width_to_status

#
# Validations
#

=item B<Validation>

=item B<_is_enabled>

  Title    : _is_enabled
  Usage    : $self->_is_enabled($string);
  Function : Checks if $string is set to yes, true, or 1. $string does not
             have to be explicitely set to yes or true since just the 
             beginning of $string is checked for the existence of y, t, or 1.
  Returns  :
  Args     : $string : The string to check.

=cut

sub _is_enabled($)
{
	my ($self, $str) = @_;
	return(0) if (!$str);
	return(1) if ($str =~ m/^(y(es)?|t(rue)?|1)/i);
	return(0);
} #_is_enabled>

=item B<_is_valid>

  Title    : _is_valid
  Usage    : $self->_is_valid('domain', 'test.com');
  Function : Checks if $string is valid by testing the regular expression
             configuration variable "regex-$type" against it.
  Returns  : The results of calling $self->_is_valid_input().
  Args     : $type   : The regular expression variable to get from the
                       configuration.
             $string : The string to check.

=cut

sub _is_valid($$)
{
	my ($self, $stype, $str) = @_;
	
	return($self->_is_valid_input($str,$self->{'config'}->{"regex-$stype"}))
	  if ($self->{'config'}->{"regex-$stype"});
	return(0);
} #_is_valid

=item B<_is_valid_input>

  Title    : _is_valid_input
  Usage    : $self->_is_valid_input('checkme', '^(y|t|1)');
  Function : Checks if $string is valid by testing $regular_expression
             against it. Before this test $regular_expression is sent to
             $self->_regex_transform to be have an patterns that need to
             be replaced, done so.
  Returns  : 1 on success, 0 on failure
  Returns  : 1 if it passes the regular expression, 0 otherwise.
  Args     : $string             : The string to check.
             $regular_expression : The regular expression to use in the check.

=cut

sub _is_valid_input($$)
{
	my ($self, $str, $regex) = @_;
	
	return(1) if (!$regex);

	# check if there are any regex replacements
	$regex = $self->_regex_transform($regex);

	return(1) if ($str =~ m/$regex/i);

	return(0.0);
} #_is_valid_input

=item B<_is_valid_password>

  Title    : _is_valid_password
  Usage    : $self->_is_valid_password('new_pass');
             or
             $self->_is_valid_password('new_pass', 'test'_user');
             or
             $self->_is_valid_password('new_pass', '', 'old_pass');
  Function : If the configuration variable "allow-weak-passwd" is not enabled
             then $password is run through the following tests:
             1) $password cannot be longer than the configuration variable
                "password-length".
             2) If $username then $password cannot contain $username.
             3) If $old_password then $password cannot contain $old_password.
             4) $password cannot contain control codes.
             5) $password must contain at least one number (0-9).
             6) $password  must contain at least one alphabet 
                character (a-z, case-insensitive)
  Returns  : 1 if the password is acceptable or 0 if it isn't.
  Args     : $password     : The password to test.
             $username     : The username to be part of the test. [optional]
             $old_password : The old password to be part of the test. [optional]

=cut

sub _is_valid_password($;$$)
{
	my ($self, $pass, $user, $old) = @_;
	my $length     = $self->{'config'}->{'password-length'};
	my $allow_weak = $self->{'config'}->{'allow-weak-passwd'};
	
	# only check for weak passwords if they aren't allowed
	return(1) if (1 == $self->_is_enabled($self->{'config'}->{'allow-weak-passwd'}));
	
	# we have several methods of checking for weak, or bad passwords
	if (length($pass) < $length)
	{
		$self->_set_error("Password must be longer than $length characters");
		return(0);
	}
	elsif ( ($user) && ($pass =~ m/$user/) )
	{
		$self->_set_error('Username is not allowed within password.');
		return(0);
	}
	elsif ( ($old)  && ($pass =~ m/$old/) )
	{
		$self->_set_error('Old password is not allowed in new password.');
		return(0);
	}
	elsif ($pass =~ m/[\000-\037\177]/)
	{
		$self->_set_error('Control codes are not allowed within the password.');
		return(0);
	}
	elsif ($pass !~ m/[0-9]/)
	{
		$self->_set_error('Password must contain at least one number');
		return(0);
	}
	elsif ($pass !~ m/[a-z]/i)
	{
		$self->_set_error('Password must contain at least one alphabetical character');
		return(0);
	}

	return(1);
} #_is_valid_password

=item B<User Interaction>

=item B<_ask_to_create_directory>

  Title    : _ask_to_create_directory
  Usage    : $self->_ask_to_create_directory('/home/test_user');
  Function : Asks the user if the directory wants to be created.
  Returns  : 1 on failure, 0 on success
  Args     : 

=cut

sub _ask_to_create_directory($;$$$)
{
	my ($self, $dir, $user, $mode, $use_bypass) = @_;
	$use_bypass = 0      if (!$use_bypass);
	$user       = 'root' if (!$user);
	$mode       = '0755' if (!$mode);
	
	$self->_die_print("ERROR: no directory specified") # _ask_to_create_directory
	  if (!$dir);
	
	# the directory already exists, pretend lik we created it, and leave the
	# permissions up to the user.
	if (-d $dir)
	{
#		$self->_error("Directory already exists: $dir");
		return(0);
	}
	
	my $answer = $self->_get_yesno("Create $dir", 'y', $use_bypass);
	
	if (1 == $self->_is_enabled($answer))
	{
		# make sure we have the right user, and in the process it will check
		# if the user exists
		$user = $self->_get_valid_system_user($user, 'Directory owner', $use_bypass);
		
		# make sure we have a mode
		$mode = $self->_get_input_with_check('Directory permissions',
		  'Invalid permissions.', $use_bypass, '755', '/^0?[0-7]{1,3}$/');
		
		# make sure that the mode is octal
		$mode = "0$mode" if ($mode !~ m/^0/);
	
		# since we've confirmed that the user is real earlier we get the uid/gid
		# for owning.
		my @_user = getpwnam($user);

		return(1) if ($self->_mkdir($dir, $_user[2], $_user[3], $mode));

		return(0);
	}

	# the user didn't want to create the directory
	$self->_set_error('Directory creation aborted by user.');
	return(1);
} #_ask_to_create_directory

=item B<_ask_to_create_file>

  Title    : _ask_to_create_file
  Usage    : $self->_ask_to_create_file('myfile.txt');
  Function : Asks the user if $file should be created, and who the owner should
             be as well as permissions.
  Returns  : 1 on failure, 0 on success
  Args     : 

=cut

sub _ask_to_create_file($;$$$)
{
	my ($self, $file, $user, $mode, $use_bypass) = @_;
	$use_bypass = 0      if (!$use_bypass);
	$user       = 'root' if (!$user);
	$mode       = '0600' if (!$mode);
	
	# notify the user the file already exists because we should not have a 
	# file if they are asking us to create it.
	if (-e $file)
	{
#		$self->_error("File already exists: $file");
		return(0);
	}
	
	# clean the path of chroot's, if /./ is part of a file there are other
	# concerns.
	$file = $self->_path_clean_chroot($file);
	
	# ask the user if they want to create the file
	my $answer = $self->_get_yesno("Create $file", 'y');
	
	if (1 == $self->_is_enabled($answer))
	{
		# make sure we have the right user, and in the process it will check
		# if the user exists
		$user = $self->_get_valid_system_user($user, 'File owner', $use_bypass);
		
		# make sure we have a mode
		$mode = $self->_get_input_with_check('File permissions',
		  'Invalid permissions.', $use_bypass, '755', '/^0?[0-7]{1,3}$/');
		
		# make sure that the mode is octal
		$mode = "0$mode" if ($mode !~ m/^0/);
	
		# since we've confirmed that the user is real earlier we get the uid/gid
		# for owning.
		my @_user = getpwnam($user);

		# create it with empty data.
		return(1) if ($self->_file_create($file, ''));

		# make sure the permissions are set properly
		if (!chmod(oct($mode), $file))
		{
			$self->_error("Unable to set permissions on file ($file:$mode): $!");
			return(1);
		}
		# make sure it is owned properly
		if (!chown($_user[2], $_user[3], $file))
		{
			$self->_error("Unable to set owner/group on file ($file, $_user[2]:$_user[3]). $!");
			return(1);
		}

		return(0);
	}

	$self->_set_error('File creation aborted by user.');
	return(1);
} #_ask_to_create_file

=item B<_get_gid>

  Title    : _get_gid
  Usage    : $self->_get_gid('wheel', 20);
  Function : Checks if the $gid is valid on the system.
  Returns  : an integer
  Args     : $gid     : The GID to check.
             $default : The default GID if invalid. [optional]

=cut

sub _get_gid($$)
{
	my ($self, $gid, $default) = @_;
	my $regex = '(' . $self->{'config'}->{'regex-gid'}  . '|' .
	                  $self->{'config'}->{'regex-group'} . ')';

	$gid = 0 if (!$gid);

	# get the group information by gid
	if ($gid =~ m/^[0-9]*$/) 
	{
		my @g = getgrgid($gid);
		return($gid) if (-1 != $#g);
	}
	# get the user information by name
	else
	{
		my @g = getgrnam($gid);
		return($g[2]) if (-1 != $#g);
	}

	$gid = $self->_get_input_with_check('Enter group name or GID',
	  'Invalid group name or GID.', 0, $default,
	  $regex);


	# get the group information by gid
	if ($gid =~ m/^[0-9]*$/) 
	{
		my @g = getgrgid($gid);
		return($gid) if (-1 != $#g);
	}
	# get the user information by name
	else
	{
		my @g = getgrnam($gid);
		return($g[2]) if (-1 != $#g);
	}

	# Invalid group name or GID
	$self->_error("Invalid group name or GID ($gid).");
	return($self->_get_gid($gid, $default));
} #_get_gid

=item B<_get_input>

  Title    : _get_input
  Usage    : $self->_get_input('Your name');
             or
             $self->_get_input('Your name', 'David');
             or
             $self->_get_input('Your name', 'David', '?');
  Function : Gets input from the user
  Returns  : a string or integer (depends on your interpretation and question)
  Args     : $display : What to print out, usually in the form of a question.
             $default : The default data. [optional]
             $qmark   : Character to display for the end of the display.
                        Defaults to ':'. [optional]

=cut

sub _get_input($;$$)
{
	my ($self, $display, $default, $qmark) = @_;
	my $data = my $ret = '';
	$default = ''  if (!$default);
	$qmark   = ':' if (!$qmark);
	
	return($default) if (!$display);
	
	return($default) if (1 != $self->_is_enabled($self->{'config'}->{'verbose'}));
	
	print "$display [$default]$qmark ";
	$data = <STDIN>;
	$ret = $data if ($data);
	$ret = $default if (!$data);
	chomp($ret);
	
	return($default) if (!$ret);
	
	return($ret);
} #_get_input

=item B<_get_input_with_check>

  Title    : _get_input_with_check
  Usage    : $self->_get_input_with_check('Enter Username', 'Invalid Username',
                    '', '^[a-z][a-z0-9_-]{2,15}$');
             or
             $self->_get_input_with_check('Enter Username', 'Invalid Username',
                    '', '^[a-z][a-z0-9_-]{2,15}$', '?');
  Function : Gets input from the user and checks against a regular expression
             until it gets a result that passes the regular expression.
  Returns  : a string, or integer 
  Args     : $display : Message, or question to display to the user.
             $error   : Error to display on invalid data entry.
             $default : Default data to use.
             $check   : Regular expression to check the data against.
             $qmark   : Character to display for the end of the display.
                        Defaults to ':'. [optional]

=cut

sub _get_input_with_check($$$$$;$$)
{
	my ($self, $display, $error, $bypass, $default, $check, $check_display, $qmark) = @_;
	
	# set some defaults
	my $data = my $ret = '';
	$default = ''  if (!$default);
	$qmark   = ':' if (!$qmark);
	$check_display = $default if (!$check_display);

	# if we are not set to be verbose then we check the default data against
	# the check data (should be a regex), and it should be valid!
	# The exception to this is if bypass is set to 1
	if ( (1 != $bypass) && (1 != $self->_is_enabled($self->{'config'}->{'verbose'})) )
	{
		return($default) if (1 == $self->_is_valid_input($default, $check));
	}

	# Keep trying to get input if the data doesn't check out
	do
	{
		print "$display [$check_display]$qmark ";
		$data = <STDIN>;
		$ret = $data if ($data);
		chomp($ret);
		$ret = $default if (!$ret);
		$check_display = $default if (!$check_display);
	} while (1 != $self->_is_valid_input($ret, $check));

	return($ret);
} #_get_input_with_check

=item B<_get_password>

  Title    : _get_password
  Usage    : $password = $self->_get_password();
  Function : Gets the password from the user twice, then checks that the
             two match, calls itself if they don't match.
  Returns  : a string
  Args     : none

=cut

sub _get_password()
{
	my ($self) = @_;
	my $ret;
	my $data ='';
	my ($pass1, $pass2);
	
	print "Enter password: ";
	ReadMode('noecho');
	$pass1 = ReadLine(0);

	print "\nEnter password again: ";
	$pass2 = ReadLine(0);
	print "\n";

	ReadMode('normal');

	chomp($pass1);
	chomp($pass2);
	
	return($pass2) if ( ('' ne $pass1) && ('' ne $pass2) && ($pass2 eq $pass1) );

	$self->_error("Mismatch or empty; try again, EOF to quit.");
	return($self->_get_password());
} #_get_password

=item B<_get_uid>

  Title    : _get_uid
  Usage    : $self->_get_uid('root', 20);
  Function : Checks if the $uid is valid on the system. NOTE: Does not check
             for max or min UID's
  Returns  : an integer
  Args     : $uid     : The UID to check.
             $default : The default UID if invalid. [optional]

=cut

sub _get_uid($$)
{
	my ($self, $uid, $default,$times) = @_;
	my $regex = '(' . $self->{'config'}->{'regex-uid'}  . '|' .
	                  $self->{'config'}->{'regex-user'} . ')';
	$times    = 0 if (!$times);

	if (20 < $times)
	{
		$self->_set_error("Too many errors in retrieiving username.");
		return(-1);
	}
	$uid = 0 if (!$uid);

	# get the user information by uid
	if ($uid =~ m/^[0-9]*$/) 
	{
		my @u = getpwuid($uid);
		return($uid) if (-1 != $#u);
	}
	# get the user information by name
	else
	{
		my @u = getpwnam($uid);
		return($u[2]) if (-1 != $#u);
	}


	$uid = $self->_get_input_with_check('Enter username or UID',
	  'Invalid username or UID.', 0, $default,
	  $regex);
	
	# get the user information by uid
	if ($uid =~ m/^[0-9]*$/) 
	{
		my @u = getpwuid($uid);
		return($uid) if (-1 != $#u);
		$times++;
	}
	# get the user information by name
	else
	{
		my @u = getpwnam($uid);
		return($u[2]) if (-1 != $#u);
	}

	# Invalid username or UID
	$self->_error("Invalid username or UID ($uid).");
	return($self->_get_uid($uid, $default, $times));
} #_get_uid

=item B<_get_valid_system_user>

  Title    : _get_valid_system_user
  Usage    : $self->_get_valid_system_user('test_user');
             or
             $self->_get_valid_system_user('test_user', 'File owner');
  Function : Gets input from the user and then checks that the user exists on
  			 the system. 
  Returns  : a string
  Args     : $user    : The user to check, either username or uid.
             $display : The question to display to the user since this
                        method could have multiple uses. [optional]
                        Defaults to 'Enter username'.

=cut

sub _get_valid_system_user($;$$)
{
	my ($self, $user, $display, $bypass) = @_;

	$bypass  = 0                if (!$bypass);
	$display = 'Enter username' if (!$display);
	
	if (!$bypass)
	{
		# see if the user exists on the system and if so return the user
		my @u = getpwnam($user);
		return($user) if (-1 != $#u);

		$self->_error("Invalid username.");
	}

	my $default = $user;
	# the user didn't exist so let's get another name to try
	$user = $self->_get_input_with_check($display,
	  'Invalid username.', 1, $user,
	  $self->{'config'}->{'regex-user'});
	
	# we do not bypass on these next sections
	my @u = getpwnam($user);
	return($user) if (-1 != $#u);
	$self->_error("Invalid username.");
	
	return($self->_get_valid_system_user($default, $display, 1));
}

=item B<_get_valid_type_input>

  Title    : _get_valid_type_input
  Usage    : $self->_get_valid_type_input('example.com');
             or
             $self->_get_valid_type_input('test_user', 'MySQL');
  Function : Gets input from the user and then checks it against several tests
             to make sure that certain functions are not being called on data
             that is invalid for the module. User modules check against the
             "regex-user" configuration variable, and domain modules check
             against the "regex-domain" configuration variable. If the regular
             checks go okay then the module is given the chance to its own
             extra checks on the data since $self->extra_type_checks is
             called.
  Returns  : a string
  Args     : $data : The original data to check.
             $type : The module that "base_class" is using. [optional]
             %args : Extra arguments to call when $self->extra_type_checks and
                     $self->type_exists are called. [optional]

=cut

sub _get_valid_type_input($;$%)
{
	my ($self, $data, $type, %args) = @_;
	my ($e, $h, $type_display);
	my $what = lc($self->{'log'}->{'action'});
    my $s    = lc($self->{'base_type'});
	$h = 0;

	$recursion++;
	if (100 == $recursion)
	{
		($e, $h)      = $self->type_exists($data, %args);
		print ($e.'-'.$h."\n");
		print($data.'-'.$s."\n");
		print($self->{'config'}->{"regex-$s-disp"}."\n");
		print($self->{'config'}->{"regex-$s"}."\n");
		return($data);
	}

	# keel over if $what is not set properly
	if ('unknown' eq $what)
	{
		$self->_set_error("Invalid Command: $what");
		return(-1);
	}

	# determine what to do with by the base_type
	$type_display = ucfirst($s);
	$type_display = ucfirst($type) . ' ' . ucfirst($s) if ($type);
	($e, $h, %args)      = $self->type_exists($data, %args);

	# get data if there is nothing to do anything with
	if (!$data)
	{
		$data = $self->_get_input_with_check(
		  "$type_display to $what", 
		  "A valid $type_display is required.",
		  1,
		  $self->{'config'}->{"regex-$s-disp"},
		  $self->{'config'}->{"regex-$s"});
		($e, $h, %args)      = $self->type_exists($data, %args);
	}

	$args{'output_display'} = $type_display;

	# the real checks
	if (1 != $self->_is_valid_input($data, $self->{'config'}->{"regex-$s"}))
	{
		$data = $self->_get_input_with_check(
		  "$type_display to $what", 
		  "A valid $type_display is required ($data).",
		  1,
		  $self->{'config'}->{"regex-$s-disp"},
		  $self->{'config'}->{"regex-$s"});		
	}
	# this allows a different processing of the hold and exists type
	# which might be necessary by the module for aliases or other 
	# important checks that need to be carried out before other types
	# of checks
	elsif (0 != (my $error = $self->extra_type_checks($data, $what, $e, $h, %args)))
	{
		return($data);
	}
	elsif ( ('add' eq $what) && (1 == $e) )
	{
		$self->_set_error("$type_display already exists ($data).");
		return($data);
	}
	elsif ( ('add' ne $what) && (1 != $e) )
	{
		$self->_set_error("$type_display doesn't exist ($data).");
		return($data);
	}
	elsif ( (1 == $h) && ($what ne 'unhold') )
	{
		$self->_set_error("$type_display is on hold ($data).");
		return($data);
	}
	elsif ( (1 != $h) && ($what eq 'unhold') )
	{
		$self->_set_error("$type_display is already active ($data).");
		return($data);
	}
	else
	{
		return($data);
	}

	# keep going until we get a valid input
	return($self->_get_valid_type_input($data, $type, %args));

} #_get_valid_type_input

=item B<_get_yesno>

  Title    : _get_yesno
  Usage    : $self->_get_yesno('Do you eat');
             or
             $self->_get_yesno('Do you eat', 'yes');
  Function : Gets input from the user, in the form of either a positive or
             negative answer.
  Returns  : a string, either 'yes' or 'no'
  Args     : $display : Question to ask.
             $default : Which is default, yes or no. [optional]
                        Defaults to 'yes'.

=cut

sub _get_yesno($;$$)
{
	my ($self, $display, $default, $bypass) = @_;
	$bypass  = 0 if (!$bypass);
	$default = 1 if (!$default);
	$default = ($default =~ m/^(y|t|1)/i) ? 'Yn' : 'Ny';

	my $do = $self->_get_input_with_check($display, 
	       'Invalid answer, please enter yes or no', $bypass, $default,
	       '^(y(es)?|n(o)?|t(rue)?|f(alse)?|1|0)');
	
	# transform the $do into a real word
	return('yes') if ($do =~ m/^(y(es)?|t(rue)?|1)/i);
	return('no')  if ($do =~ m/^(n(o)?|f(alse)?|0)/i);
} #_get_yesno

=item B<Directory Functions>

=item B<_deltree>

  Title    : _deltree
  Usage    : $self->_deltree('/home/web/test_user');
  Function : Removes the $directory specified using recursion to ensure that
             the directories underneath are clean so rmdir will work properly.
  Returns  : 1 on failure, 0 on success
  Args     : $directory : The directory to remove

=cut

sub _deltree($)
{
	my ($self, $dir) = @_;
	my $dh;
	
	# open the directory and error out if not successful
	if (!opendir($dh, $dir))
	{
		$self->_set_error("Can't open $dir: $!");
		return(1);
	}
    
    # go through the directory deleting all files
    # NOTE: Following symlinks in this fashion is very dangerous to system
    #       if the user is chrooted and one of their symlinks points to /bin
    #       or /lib. It works fine while the user is chrooted but outside of
    #       the chroot it will cause a fair amount of problems if all the
    #       directories and files in those directories are deleted. This goes
    #       for any symlink to any other special area. To prevent this from
    #       happening we check if the entry is a symlink and if it is then
    #       unlink. This works well when it comes to directories as usually
    #       they would be traversed, and instead we catch the problem
    while (my $entry = readdir($dh))
    {
    	# ignore . and .. entries
    	if ($entry !~ m/^(\.|\.\.)$/)
    	{
    		# Symlinks and non-directory entries get unlinked
    		if ( (-l "$dir/$entry") || (!-d "$dir/$entry") )
    		{
    			unlink("$dir/$entry");
    		}
    		# it better have been recognized as a symlink or a non-directory
    		elsif (-d "$dir/$entry")
    		{
    			# empty the directory first, then remove it.
    			$self->_deltree("$dir/$entry");
   				rmdir("$dir/$entry");
    		}
        }
    }
	closedir($dh);
	
	# remove the directory
	rmdir($dir);

	# failures are ignored
	return(0);
} #_deltree

=item B<_mkdir>

  Title    : _mkdir
  Usage    : $self->_mkdir('/home/web/test_user', 'test_user', 'group', 0755)
  Function : Makes the $directory including intermediate directories with the
             $username, $groupname, and $mode specified. UID/GID are passed
             to their respective $self->_get_uid/_get_gid functions to ensure
             that they are valid ID's in use on the system. 
             NOTE: all directories that are created will have the same owner 
             and mode.
  Returns  : 1 on error, 0 on success
  Args     : $directory : The directory to create.
             $username  : The user id or name.
             $groupname : The group id or name.
             $mode      : The mode of the files. Defaults to 0755.

=cut

sub _mkdir($$$$)
{
	my ($self, $dir, $uid, $gid, $mode) = @_;
	my $error = 0;
	$mode     = '0755'   if (!$mode);
	$mode     = "0$mode" if ($mode !~ m/^0/);
	$mode     = "$mode";
	
	# Clean this directory up if there are chrooted users 
	$dir = $self->_path_clean_chroot($dir);
	
	# we need to make sure that the uid and gid are numbers
	$uid = $self->_get_uid($uid, $uid);
	$gid = $self->_get_gid($gid, $gid);

	# something major happened and uid/gid couldn't clean up after themselves
	# so we need to bow out.
	return(1) if ($self->_is_enabled($self->{'error'}->{'exists'}));

	# make the directories by looping through $dir.
	my @dirs = split('/', $dir);
	my $t = '';

	foreach my $d (@dirs)
	{
		$t = $t.$d.'/';
		# only try to create if the directory doesn't exist.
		if (!-d $t)
		{
			# make the directory and error out if it can't.
			if (!mkdir($t, oct($mode)))
			{
				$self->_error("Unable to make directory ($t:$mode). $!");
				return(1);
			}
			# this is done to ensure that umask doesn't interfere. Yes I know
			# why umask is there, but in this context it becomes very annoying
			# when the user can't use the mode they input, even if they remember
			# their umask.
			if (!chmod(oct($mode), $t))
			{
				$self->_error("Unable to set directory permissions ($t:$mode). $!");
				return(1);
			}
			# chown the directory
			if (!chown($uid, $gid, $t))
			{
				$self->_error("Unable to set owner/group on directory ($t, $uid:$gid). $!");
				return(1);
			}
		}
	}
	return(0);
} #_mkdir

=item B<_path_clean_chroot>

  Title    : _path_clean_chroot
  Usage    : $path = $self->_path_clean_chroot('/home/web/./home/test_user);
  Function : Transforms /./ to /
  Returns  : a string
  Args     : $string : The string to transform.

=cut

sub _path_clean_chroot($)
{
	my ($self, $s) = @_;
	$s =~ s/\/\.\//\//g;
	return $s;
} #_path_clean_chroot

=item B<_path_clean_variables>

  Title    : _path_clean_variables
  Usage    : $path = $self->_path_clean_variables('/home/%split%/test_user);
  Function : Transforms %vars% to ''.
  Returns  : a string
  Args     : $string : The string to transform.

=cut

sub _path_clean_variables($)
{
	my ($self, $s) = @_;
	$s =~ s/\%[^\%]*\%/\//g;
	do
	{
		$s =~ s/\/\//\//g;
	} while ($s =~ m/\/\//);
	return $s;
} #_path_clean_variables

=item B<_path_to>

  Title    : _path_to
  Usage    : $self->_path_to('myfile.txt', 'section');
  Function : Calls the objects make_path method, unless $path is already
             absolute.
  Returns  : a string
  Args     : $path           : The original path.
             $where          : Where the path should be.
             $force_absolute : Whether or not to force the path to be
                               absolute.

=cut

sub _path_to($$$)
{
	my ($self, $path, $where, $flag) = @_;
	$flag = 0 if (!$flag);

	# ignore absolute paths
	return($path) if ($path =~ m/^\//i);

	# call $obj->make_path
	return($self->make_path($path, $where, $flag));
} #_path_to

=item B<_path_to_tpl>

  Title    : _path_to_tpl
  Usage    : $self->_path_to_tpl('test/myfile.txt');
  Function : Returns the new path. Prepends "directory-template" to $path,
             unless it is absolute.
  Returns  : a string
  Args     : $path : The path to modify.

=cut

sub _path_to_tpl($)
{
	my ($self, $path) = @_;
	my $data;

	# absolute paths are not modified
	return($path) if ($path =~ m/^\//i);

	my $_path = $self->{'config'}->{'directory-template'};
	$_path =~ s/\%section\%/$self->{'me'}/i;

	return($_path.'/'.$path);
} #_path_to_tpl

=item B<File Functions>

=item B<_file_append>

  Title    : _file_append
  Usage    : $self->_file_append('myfile.txt', $data);
  Function : Appends $data to $file.
  Returns  : 1 if failed.
  Args     : $file : The name of the file to write.
             $data : The data to write.

=cut

sub _file_append($$)
{
	my ($self, $file, $data) = @_;
	my $fh;
	my $error = 0;

	return(-1) if (!$data);

	if ( (!-e $file ) || (!open($fh, ">>$file")) )
	{
		$self->_set_error("Error Appending to ($file): File not found.");
		return(-1);
	} # file doesn't exist

	printf $fh $data;
	close($fh);
	return(0);
}

=item B<_file_create>

  Title    : _file_create
  Usage    : $self->_file_create('myfile.txt', $data);
  Function : Writes $data to $file.
  Returns  : 1 if failed
  Args     : $file : Name of the file to write.
             $data : The data to write.

=cut

sub _file_create($$)
{
	my ($self, $file, $data) = @_;
	my $fh;
	my $error = 0;
	
	if (!open($fh, ">$file"))
	{
		$self->_set_error("Error creating ($file): $!.");
		return(-1);
	}

	printf $fh "$data";
	close($fh);
	return(0);
} # _file_create

=item B<_file_delete_line>

  Title    : _file_delete_line
  Usage    : $self->_file_delete_line('myfile.txt', 10);
  Function : Deletes the specified line number from the file
  Returns  : an integer, -1 on failure
  Args     : $file        : The file to delete the line from.
             $line_number : The line number to start at.

=cut

sub _file_delete_line($$)
{
	my ($self, $file, $line_number) = @_;
	my ($fh, @tmp);
	my $line     = 1;
	return(-1)   if (!$line_number);

	if (! -e $file )
	{
		$self->_set_error("Error Deleting line ($file): File not found.");
		return(-1);
	} # file doesn't exist

	if ($self->_file_line_count($file) < $line_number)
	{
		$self->_set_error("Invalid line number.");
		return(-1);
	} # no need to attempt if the file has less than the line number of lines

	# cycle through and delete that line
	if (!open($fh, $file))
	{
		$self->_set_error("Error Deleting line ($file): File not found.");
		return(-1);
	}
	while(my $data = <$fh>)
	{
		push(@tmp, $data) if ($line != $line_number);
		$line++;
	}
	close($fh);

	# create the temp file
	return(-1) if (-1 == $self->_file_create("$file.tmp", join('', @tmp)));

	# rename the file
	if (-1 == rename("$file.tmp", $file))
	{
		$self->_set_error("Error renaming to ($file). $!");
		unlink("$file.tmp");
		return(-1);
	}

	return(0);
} #_delete_line

=item B<_file_get>

  Title    : _file_get
  Usage    : @data = $self->_file_get('my.txt');
  Function : Retrieves the data from $file.
  Returns  : an array, or -1 on failure
  Args     : $file : The file to retrieve.

=cut

sub _file_get($)
{
	my ($self, $file) = @_;
	my ($fh, @data);

	if ( (! -e $file ) || (!open($fh, $file)) )
	{
		$self->_set_error("Error getting ($file): No such file or Directory.");
		return(-1);
	}

	@data = <$fh>;
	close($fh);

	return(@data);
}

=item B<_file_get_shell_commented>

  Title    : _file_get_shell_commented
  Usage    : $self->_file_get_shell_commented($file)
  Function : Gets $file and only returns lines that are not comments (using #)
             or blanks.
  Returns  : an array
  Args     : $file : The file to retrieve.

=cut

sub _file_get_shell_commented($)
{
	my ($self, $file) = @_;
	
	my @ret;
	my @data = $self->_file_get($file);

	return(-1) if (-1 == $#data);
	
	foreach my $line (@data)
	{
		push(@ret, $line) if ($line !~ m/^(\#|$)/);
	}
	return(@ret);
} #_file_get_shell_commented

=item B<_file_get_template>

  Title    : _file_get_template
  Usage    : $self->_file_get_template('my.tpl');
  Function : Gets the template file specified from the "directory-template"
             configuration variable directory by calling $self->_file_get.
  Returns  : an array
  Args     : $file : The template file to retrieve

=cut

sub _file_get_template($)
{
	my ($self, $file) = @_;
	my $tpl_dir = $self->{'config'}->{'directory-template'};
	
	# transform the file into an absolute path if it isn't already
	# NOTE: Should this transform it anyway to make sure that the template file
	#  is in the template directory.
	if ($file !~ m/^\//)
	{
		$tpl_dir =~ s/\%section\%/$self->{'me'}/i;
		$file = $tpl_dir.'/'.$file;
	}

	return($self->_file_get($file));
}

=item B<_file_line_count>

  Title    : _file_line_count
  Usage    : $self->_file_line_count('myfile.txt');
  Function : Gets the number of lines in $file.
  Returns  : an integer, -1 on failure
  Args     : $file : The file to count lines on.

=cut

sub _file_line_count($)
{
	my ($self, $file) = @_;
	my ($fh, $line);
	my $count = 0;

	if ( (! -e $file ) || (!open($fh, $file)) )
	{
		$self->_set_error("Error getting line count ($file): No such file or Directory.");
		return(-1);
	}

	while($line = <$fh>)
	{
		$count++;
	}
	close($fh);
	return($count);
} #_file_line_count

=item B<_file_search>

  Title    : _file_search
  Usage    : $self->_file_search('myfile.txt', 'me');
  Function : Searches $file for $search, and returns the first line number
             it is on, and the line itself.
  Returns  : an integer, -1 on failure
  Args     : $file   : The file to search.
             $search : The phrase to look for.
             $line   : The line number to start at. [optional]

=cut

sub _file_search($$;$)
{
	my ($self, $file, $search, $line_number) = @_;
	my $fh;
	my $line     = 0;
	my $data     = my $retval = '';
	$line_number = 0 if (!$line_number);

	if ( (! -e $file ) || (!open($fh, $file)) )
	{
		$self->_set_error("File Error ($file): No such file or Directory.");
		return(-1);
	}
	while($data = <$fh>)
	{
		chomp($data);
		next if ($line++ < $line_number);
		if ($data =~ m/$search/i)
		{
			close($fh);
			return($line, $data);
		}
	}
	close($fh);

	return(-1, ''); # return nothing
} #_file_search

=item B<Configuration>

=item B<_get_hold_style>

  Title    : _get_hold_style
  Usage    : my ($start, $line, $end) = $self->_get_hold_stype
  Function : In Apache it is '#' only, but in Bind9 '/* */', '#', '//' work.
             The first element of the array will always be the line comment, 
             '#' or '//' or ';' are considered single-line comments. The second
             element of the array will contain the opening of a multi-line
             comment. The third element will contain the closing of the multi-
             line comment. If the second element or third elements are missing
             from the configuration variable "hold-style" then it will treat
             the "hold-style" as a single line comment.
  Returns  : an array
  Args     : 
  Example  : configuration file > "* /* */" = multi-line comment
             configuration file > "#"       = single-line comment
             configuration file > "# /* */" = multi-line comment

=cut

sub _get_hold_style
{
	my ($self, $escape) = @_;
	my (@return, @ret);
	
	# defaults
	my $data = $self->{'config'}->{'hold-style'};
	$escape = 0 if (!$escape);
	
	# remove white noise, trim everything else
	$data =~ s/\s+/ /g;
	$data =~ s/(^\s+|\s+$)//g;
	
	# determine if the hold-style is to be escaped (for regex purposes)
	if (1 == $escape)
	{
		my @d = split(' ', $data);
		foreach my $t (@d)
		{
			# escape *\?/{}][()		
			$t =~ s/([\*\?\/\[\]\{\}\(\)]|\\)/\\$1/gi;
			push(@ret, $t);
		}
	}
	else
	{
		@ret = split(' ', $data);
	}

	# If the third element is not set and the second one is then we are assuming
	# that it is a multiline quotation and we react accordingly
	#
	# NOTE: There is no checking of whether or not the multi line comments
	#       are valid at this point
	#
	# TODO: Multi line comment open/close validation? -dlundgren.2006.05.28
	#
	# Order of elements returned
	#  0 Single line complete OR Multi line beginning
	#  1 Multi line open
	#  2 Multi line close
	if (!$ret[2] && !$ret[1])
	{
		push(@return, $ret[0]);
	} # single line complete or multi line begin
	elsif (!$ret[2] && $ret[1])
	{
		push(@return, '');
		push(@return, $ret[0]);
		push(@return, $ret[1]);
	} # multiline open and multiline close
	elsif ($ret[2] && $ret[1])
	{
		return(@ret);
	} # no need to worry about the order because we assume it is valid 

	return(@return);
} #_get_hold_style

=item B<_get_regex_descent>

  Title    : _get_regex_descent
  Usage    : my ($rs, $ds, $de, $re) = $self->_get_regex_descent();
  Function : Returns the configuration variables "regex-start",
             "regex-descent-start", "regex-descent-end", "regex-end" in that
             order as an array. It will perform the same transformation that
             $self->_get_input_with_check performs on the regular expression.
  Returns  : an array(string, string, string, string)
  Args     : $data : The data ro replace in the regular expressions that are
                     retrieved.

=cut

sub _get_regex_descent($)
{
	my ($self, $data) =  @_;
	my $regex_start   =  $self->{'config'}->{'regex-start'};
	my $regex_end     =  $self->{'config'}->{'regex-end'};
	my $descent_start =  $self->{'config'}->{'regex-descent-start'};
	my $descent_end   =  $self->{'config'}->{'regex-descent-end'};
	$regex_start      =~ s/\%data%/$data/i if ($regex_start);
	$regex_end        =~ s/\%data%/$data/i if ($regex_end);
	$descent_start    =~ s/\%data%/$data/i if ($descent_start);
	$descent_end      =~ s/\%data%/$data/i if ($descent_end);
	$descent_start    =  '######poi######' if (!$descent_start);
	$descent_end      =  '######poi######' if (!$descent_end);

	# Transform the regular expressions
	$regex_start   = $self->_regex_transform($regex_start);
	$regex_end     = $self->_regex_transform($regex_end);
	$descent_start = $self->_regex_transform($descent_start);
	$descent_end = $self->_regex_transform($descent_end);
	
	return ($regex_start, $descent_start, $descent_end, $regex_end);
} #_get_regex_descent

=item B<_merge_config>

  Title    : _merge_config
  Usage    : %config = 
                $self->_merge_config('dns', \%dns_config, \%global_config);
  Function : Combines two different sets of configuration hashes into one. The
             %global_config keys are the base of the new hash, and then 
             %dns_config will override any keys that %global_config has already
             placed in the configuration hash.
  Returns  : a hash
  Args     : $module : A hash reference
             $global : A hash reference

=cut

sub _merge_config($$)
{
	my ($self, $type, $module, $global) = @_;

	my %configuration = ();

	# populate with the generic configuration
	foreach my $key (sort keys %{$global})
	{
		$configuration{$key} = {%{$global}}->{$key};
	}

	# populate with the module information overwriting anything that was
	# previously there.
	foreach my $key (sort keys %{$module})
	{
		$configuration{$key} = {%{$module}}->{$key}
		  if {%{$module}}->{$key};
	}

	return(%configuration);
} #_merge_config

=item B<_parse_configuration>

  Title    : _parse_configuration
  Usage    : my %config = $self->_parse_configuration('file.conf');
  Function : Returns the configuration in a hash.
  Returns  : a hash
  Args     : $file : The file to get the configuration from. 
                     Should be absolute.

=cut

sub _parse_configuration($)
{
	my ($self, $file) = @_;
	my ($fh, $section, %config);
	$file       = $self if (!$_[1]);
	my $comment = my $lineno = 0;
	
	# error out unless the file is found
	if (! -e $file )
	{
		print "No configuration file found.\n";
		print "Please create $file.\n";
		exit(1); # _parse_configuration
	}
	
	# open the file and obtain the data in it
	open($fh, $file);
	while(my $line = <$fh>)
	{
		$lineno++;
		chomp($line);

		# we are inside a comment see if it closes
		if ( ($line =~ /\*\//) && (1 == $comment) )
		{
			$comment = 0;
			next;
		}
		next if (1 == $comment);
	
		# strip out quoted stuff after the = if there is any
		$line =~ s/= (\"[^\"]*\")/= QUOTED_STRING/i;
		my $quote = $1;
		
		# we allow comments on the lines so remove those comments
		# Comments wrapped in "" are not comments
  		$line =~ s/^\/\*.*?\*\/$//g;
  		$line =~ s/^(\/\/|\#).*$//g;
  		$line =~ s/(\/\/|\#).*$//g;
  		$line =~ s/\/\*.*?\*\/.*$//g;
  		
  		# replace QUOTED_STRING back in the equation
  		$line =~ s/QUOTED_STRING/$quote/;
  		
  		# skip the line if there is no data
		next if ($line =~ /^$/);
		
		# Strip out extra whitespace
		$line =~ s/\s+/ /ig;

		# Comment block?
		if ($line =~ /^\/\*/)
		{
			# die if this is a nested comment
			die "Syntax Error: $lineno: Nested Comments are not allowed.\n" if (1 == $comment);

			# mark as a comment
			$comment = 1;
			next;
		}

		# this is valid data now. YAHOO!!!
		if ($line =~ /^\s*?\[([a-z0-9_-]*)\]\s*?$/i)
		{
			# section line
			$section = lc($1);
		}
		elsif ($line =~ /([a-z0-9_-]*) = (\"?)(.*)?\2/i)
		{
			$config{$section}{lc("$1")} = "$3";
		}
	}
	close($fh);

	return(%config);
} #_parse_configuration

=item B<Misc>

=item B<_is_prime>

  Title    : _is_prime
  Usage    : my $is_prime = $self->_is_prime(127);
  Function : Determines if a number is prime or not
  Returns  : 1 for valid, 0 for non-valid
  Args     : $number : The number to test for primality.

=cut

sub _is_prime($)
{
	my ($p) = @_;
	my $i = my $is_prime = 1;
	
	# 2 is prime while all other even numbers are not prime
	return(1) if (2 == $p);
	return(0) if (0 == ($p % 2));

	# loop through starting at 3 to the sqrt of the number being tested.
	# Reasoning for going to the sqrt is that if we get to the sqrt + 1 then
	# we should have already have found whether or not any number will go into
	# the larger number.
	# NOTE: I ran a test against a file of known primes < 1,000,000 and then
	#       diff on it and came up with no differences.
	for($i = 3; $i <= $p; $i += 2)
	{
		next          if (0 == ($i % 2));
		return(1)     if ($i == $p);
		return(0)     if ( ($i > $p) || (0 == ($p % $i)) );
		return(0)     if (0 == ($p % $i));
		$is_prime = 0 if ($p % $i);
		
		# I am assuming that if nothing up to the square root of a number has
		# acheived a result then this is most likely a prime, but I could be
		#wrong
		return(1)     if ((int(sqrt($p))+ 1) < $i);
	}
	return($is_prime);
} #_is_prime

=item B<_rand>

  Title    : _rand
  Usage    : my $rand = int($self->_rand(127));
  Function : Returns a random number between 0 and the number supplied. If the
             number is not supplied then it assumes 1. This is the minimal 
             standard random number generator from Park & Miller (1988). I
             decided to implement it in this code instead of using perls so
             that the modulus and multiplier could be changed to suit tastes
             instead of using the defaults.
  Returns  : an integer, or a float.
  Args     : $bounds : The upper limit. [optional]

=cut

sub _rand
{
	my ($self, $bounds) = @_;
	$bounds = 0 if (!$bounds);
	my ($fh, $ctx);
	my $reseed = 0;
	
	# Maximum Integer Value & Modulus:
	# Typical systems will have a max int at 2147483647 or 2^31 - 1.
	#  NOTE[1]: This can be changed to various things depending on what
	#           you wan for randomness, as this also is the modulus.
	#  NOTE[2]: I found in testing that perl can handle larger integers in
	#           its it seems stupid to limit random to 2147483647.
	#  NOTE[3]: Currently I have it set to pi+21. I have noted that the highest
	#           I can go (on a 32-bit machine) is not above 2^46. After that
	#           the first number always seemed to be 1 less than the bounds.
	my $m = 3141592621;

	# Multipliers:
	#  Fishman & Moore, An exhaustive analysis and portable pseudo-random 
	#  number generator of multiplicative congruential generators with 
	#  modulus 2^31-1:
	#    [1986] 62089911,742938285,950706376,1226874159,1343714438
	#  Park & Miller, Random Number Generators: Good Ones are Hard to Find:
	#    [1988] 16807,397204094
	my $a  = 950706376;
	
	# q = m div a
	my $q = $m / $a;

	# r = m mod a;
	my $r = $m % $a;
	if ( ($reseed) || (!$next) )
	{
		my $seed;
		# this fetches the seed from /dev/random, and makes sure that it is
		# prime (as much as my _is_prime function can).
		open($fh, '/dev/random') or die("No /dev/random device: $!.");
		my $p = 0;
		while (1 != $p)
		{
			read($fh, $seed, 8);
			my $sval = unpack("L", $seed);
			if ( (_is_prime($sval)) && ($sval > 99999999) )
			{
				$ctx = $sval;
				$p++;
			}
		}
		close($fh);
	}
	# reuse the seed number like c/c++ rand does
	else
	{
		$ctx = $next;
	}
	
	# Determine the number
	my $x = ($m * ($ctx % $q)) - ($r * ($ctx / $q));
	
	$x += 0x7fffffff if ($x < 1);

	$next = (($ctx = $x) % ($m - 1));
	my $rand = $next / ($m - 1);
	
	# if the user supplied a bounds then we want to return something
	# in those bounds.
	$rand = ($rand * $bounds) if ($bounds > 1);
	return($rand);
}

=item B<_generate_password>

  Title    : _generate_password
  Usage    : my $password = $self->_generate_password();
  Function : Returns a generated password. The password is of the form
             'cvc##cvc' where c is a consonant, v a vowel, and # a number. It
             is fairly secure, is 8 characters long, and also contains a semi
             mnemonic device so that it can be remembered.
  Returns  : a string
  Args     : none

=cut

sub _generate_password
{
	my ($self) = @_;
	my (@password, $i);
	my @numbers   = (0..9);
	my @vowels    = ("a","e","i","o","u","y");
	my @consnants = ("b","c","d","f","g","h","j","k","l","m","n","p","q","r","s","t","v","w","x","z");
	my $passwords = 20;

	# Generate a set amount of passwords (there is an amount before they are
	# no longer random
	for($i = 0; $i < $passwords; $i++)
	{
		my $salt  = $consnants[int($self->_rand($#consnants+1))] .
	                $vowels[   int($self->_rand($#vowels+1))   ] .
	                $consnants[int($self->_rand($#consnants+1))] .
	                $numbers[  int($self->_rand($#numbers+1))  ] .
	                $numbers[  int($self->_rand($#numbers+1))  ] .
	                $consnants[int($self->_rand($#consnants+1))] .
	                $vowels[   int($self->_rand($#vowels+1))   ] .
	                $consnants[int($self->_rand($#consnants+1))];
		my @CaSe      = ( uc($salt), lc($salt) );
		$password[$i] = $CaSe[ int($self->_rand($#CaSe+1)) ];
	}
	
	return($password[ int($self->_rand($#password+1)) ]);
}


=item B<_regex_transform>

  Title    : _regex_transform
  Usage    : my $regex = $self->_regex_transform('^(y|n):%user%');
  Function : Any replacement variables in $regular_expression are replaced,
             as indicated by '%[a-z0-9_-]*%' being found. The replacement
             variable is obtained by getting it from the configuration 
             variable "regex-%variable%" and placing parenthesis around it,
             if it is not defined in the configuration variables then it is
              set to ''.
  Returns  : a string
  Args     : $regex : The regular expression to transform

=cut

sub _regex_transform($)
{
	my ($self, $regex) = @_;
	while ($regex =~ m/\%([a-z0-9_-]*)\%/i)
	{
		# see if the regex replacement exists in config
		my $re = ($self->{'config'}->{"regex-$1"}) ? 
		   '('.$self->{'config'}->{"regex-$1"}.')' : 
		   '';
		$regex =~ s/\%$1\%/$re/gi;
	}
	return($regex);
} #_regex_transform

=item B<_run_cmd>

  Title    : _run_cmd
  Usage    : my $error = $self->_run_cmd('cp', %args);
  Function : Runs the command obtain by breaking down the configuration 
             variable "command-%name%". "command-%name%" should be in the
             following format: '/path/to/command;arg1,arg2,arg3...' the 
             arguments may contain replacement variables, and if they are
             surrounded by parenthesis '(-u %arg1%),-d arg2' then if they
             do not exist in the %args hash the parenthetical arguments
             will be dropped.
  Returns  : 1 on failure, 0 on success
  Args     : $name            : The command configuration variable name.
             $suppress_output : Whether or not to suppress the output from
                                executing a command. Defaults to 0.
             %args            : The arguments to the command. [semi-optional]
                                It is a good idea to supply it anyway.
=cut

sub _run_cmd($$%)
{
	my ($self, $name, $suppress_output, %args) = @_;
	my ($cmd, @cmds);

	return(1) if ( (!$name) 
	             || (0 >= length($name)) 
	             || (!$self->{'config'}->{'command-'.$name}) 
	              );

	# get the command to run
	my $run  = $self->{'config'}->{'command-'.$name};
	my $pipe = $self->{'config'}->{'command-'.$name.'-pipe'};

	# remove pipe_data and chroot_dir from the arguments
	my $pipe_data  = $args{'pipe_data'};
	my $chroot_dir = $args{'chroot_dir'};
	delete($args{'pipe_data'});
	delete($args{'chroot_dir'});

	# check if we have any arguments to the command
	if ($run =~ m/;/)
	{
		my @t = split(';', $run);
		$cmd  = $t[0];
		my @c = split(',', $t[1]);

		# we need to make sure that the cmds don't have replacements
		foreach my $_c (@c)
		{
			my $opt = 0;
			# an optional parameter that only gets used if the filler is
			# there
			$opt = 1 if ($_c =~ m/\(/);
			$_c  =~ s/(\(|\))//gi;
			if ($_c =~ m/(\%([^\%]*?)\%)/)
			{
				my $arg = $2;
				if ($args{$arg})
				{
					my $re   = '%'.$arg.'%';
					my $argu = $args{$arg};
					# remove shell arguments that may cause problems
					$argu =~ s/[\&\;\`\'\\\"\|\*\?\~\<\>\^\(\)\[\]\{\}\$\n\r]//g;
					# if there is a space character then the option needs to be
					# encased in ""
					$argu = "\"$argu\"" if ($argu =~ m/\s/);
					$_c   =~ s/$re/$argu/i;
					$opt  = 0 if (1 == $opt);
				}
				elsif (0 == $opt)
				{
					$self->_set_error("error in _run_cmd syntax");
					return(1);
				}
			}
			# remove any leading and trailing whitespace
			chomp($_c);
			$_c =~ s/(^\s+|\s+$)//g;
			push(@cmds, $_c) if (!$opt);
		}
	}
	# there are no options to worry about
	else
	{
		$cmd = $run;
	}

	# pipe to the command if there is pipe_data and it is enabled.
	if ( ($pipe) && (1 == $self->_is_enabled($pipe)) && ($pipe_data))
	{
		if ($pipe_data)
		{
			my $nullfh;
			open($nullfh, '>/dev/null');
			# suppress output by sending data to /dev/null
			local *STDOUT = $nullfh if ($self->_is_enabled($suppress_output));
			local *STDERR = $nullfh if ($self->_is_enabled($suppress_output));
			my $pipe_cmd = $cmd . (@cmds ? ' ' . join(' ', @cmds) : '');
			my $fh;
			open($fh, "|$pipe_cmd");
			print $fh $pipe_data;
			close($fh);

			# Reset the output
			close($nullfh);
=todo 2006.08.11 dlundgren del
Figure out how to determine if the command failed.
=cut
			return(0);
		}
		else
		{
			$self->_set_error("Invalid use of _run_cmd: $cmd.");
			return(1);
		}
	}
	# we create another process that has the capability to chroot the
	# child process.
	else
	{
		my $pid;
		FORK: {
			if ($pid=fork())      {}
			elsif (defined($pid))
			{
				# disable some weirdness with certain binaries
				chroot($chroot_dir) if ($chroot_dir);
				my $so;
		#		my $nullfh;
		#		open($nullfh, '>/dev/null');
			# suppress output by sending data to /dev/null
				if ($self->_is_enabled($suppress_output))
				{
					open(STDOUT , '>/dev/null');
					open(STDERR , '>/dev/null');
				}
		#		local *STDOUT = $nullfh if ($self->_is_enabled($suppress_output));
		#		local *STDERR = $nullfh if ($self->_is_enabled($suppress_output));
				# run the command
				if (@cmds)
				{
					exec($cmd, @cmds);
				}
				else
				{
					exec($cmd);
				}
				# Reset the output
				close(STDOUT);
				close(STDERR);
		#		close($nullfh);
				# we do not need to rest the output since this is a different
				# process than the original
			}
			elsif ($! == 11)
			{
				sleep 5;
				redo FORK;
			}
			else
			{
				die "Can't fork: $!\n";
			}
		}
		waitpid($pid, 0);
		#$status = $?;
		if (0 != $?)
		{
			$self->_set_error("Error running cmd: $cmd.");
			return(1);
		}
	}
	return(0);
} #_run_cmd

=item B<_set_extra>

PLEASE FILL ME IN!

=cut

sub _set_extra($)
{
	my ($self, $e) = @_;
	
	$self->{'data'} = $e;
} #_set_extra

=item B<_get_extra>

PLEASE FILL ME IN!

=cut

sub _get_extra
{
	my ($self) = @_;
	return($self->{'section'}->{'extra'}) if ($self->{'section'}->{'extra'});
	my %args;
	return(%args);
} #_get_extra
=head2 Generic Internal Functions>

Generic functions for hold/unhold/add/del(ete)/edit

These may need to be modified to be more universal but I think it is fairly
capable of handling dns/web at least bind9/apache style at the same time

=item B<_delete>

  Title    : _delete
  Usage    : $self->_delete('domain.com', 'apache.conf', 0);
  Function : Locates the block of data based on $needle and removes it from
             $file.
  Returns  : 1 on failure, 0 otherwise
  Args     : $needle : The replacement in the regular expressions.
             $file   : The file to remove data from.
             $save   : Whether or not to save the file. [optional]

=cut

sub _delete($$;$)
{
	my ($self, $needle, $file, $save) = @_;
	my $fh;
	
	# Get the hold style, and the descent regular-expressions
	my ($hold_line, $hold_begin, $hold_end)     = $self->_get_hold_style(1);
	my ($re_start, $de_start, $de_end, $re_end) = 
	    $self->_get_regex_descent($needle);
	my $descent = my $block = my $lineno = 0;
	my @data;	# Where are we adding the directives

	# open the file
	open($fh, "$file") or $block = -1;
	if (-1 == $block)
	{
		$self->_set_error("Couldn't open for reading ($file): $!.");
		return(1);
	}

	while(my $line = <$fh>)
	{
		$lineno++;
		my $orig = $line; # keep the original line intact

		# trim any whitespace fore/aft of the string, and reduce multiple white-
		# space to single whitespace
		chomp($line);
		$line =~ s/^\s*//g;
		$line =~ s/\s+/ /g;

		# start of the zone we looking for
		if ($line =~ m/^$re_start/i)
		{
			$block   = 1;
			$descent = 1;
		}
		elsif ( ($line =~ m/.*?$de_start/i) 
		     && ($line =~ m/$de_end/) 
		     && (1 == $block) 
		      )
		{
			# There is a single line {}; bracket pair (at least one anyway)
			# Get the how
			my $offset = index($line, '{', 0);
			# Is there a better way to do this?
			while (-1 != ($offset = index($line, '{', $offset)))
			{
				# now descend and check for };
				$descent++ ;
				$descent-- if (-1 != ($offset = index($line, '};', $offset)));
				$offset++;
			}
		}
		elsif ( ($line =~ m/$de_start/) && (1 == $block) )
		{
			$descent++;
		}
		elsif ( ($line =~ m/^$de_end$/) && (1 == $block) )
		{	
			$descent--;
			if (0 == $descent)
			{
				$block = 0;
				next;
			}
		}
		elsif ( ($line =~ m/^$re_end$/) && (1 == $block) )
		{
			$block = 0;
			next;			
		}
		push(@data, $orig) if (0 == $block);
		
	} # close loop
	close($fh);
	
	if ( ($save) && (1 == $save) )
	{
		# NOTE: 2006.08.11 : changed to write to a temp file first then
		#                    rename the temp to the real file.
		return(1) if (-1 == $self->_file_create("$file.tmp", join('', @data)));
		
		if (-1 == rename("$file.tmp", $file))
		{
			$self->_set_error("Couldn't rename temp file to ($file): $!.");
			return(1);
		}
	} # done saving
	
	print @data if ( ($self->{'debug'}) && (1 == $self->{'debug'}) );
} #_delete

=item B<_hold>

  Title    : _hold
  Usage    : $self->_hold('domain.com', 'apache.conf', 1);
  Function : Locates the block of data based on $needle and 'holds' it in 
             $file.
  Returns  : 1 on failure, 0 otherwise
  Args     : $needle      : The replacement in the regular expressions.
             $file        : The file to modify.
             $hold_escape : Whether or not to escape the hold regex.
             $save        : Whether or not to save the file. [optional]

=cut

sub _hold($$$;$)
{
	my ($self, $needle, $file, $hold_escape, $save) = @_;
	my $fh;

	$hold_escape = 0 if (!$hold_escape);

	my ($hold_line, $hold_begin, $hold_end)
	    = $self->_get_hold_style($hold_escape);
	my ($re_start, $de_start, $de_end, $re_end)
	    = $self->_get_regex_descent($needle);
	my $descent = my $block = my $lineno = 0;
	my @data;	# Where are we adding the directives

	open($fh, "$file") or $block = -1;
	if (-1 == $block)
	{
		$self->_set_error("Couldn't open ($file). $!");
		return(1);
	}

	while(my $line = <$fh>)
	{
		$lineno++;
		my $orig = $line;
		# trim any whitespace fore/aft of the string, and reduce multiple white-
		# space to single whitespace
		chomp($line);
		$line =~ s/(^\s+|\s+$)//g;
		$line =~ s/\s+/ /g;
		if ($line =~ m/^$re_start/i)
		{
			$block   = 1;
			$descent = 1;
			push(@data, $hold_begin."\n") if ($hold_begin);
			push(@data, $hold_line.'|-|'.$orig);
		}
		elsif ( ($line =~ m/.*?$de_start/i)
		     && ($line =~ m/$re_end/)
		     && (1 == $block) 
		      )
		{
			# There is a single line {}; bracket pair (at least one anyway)
			# Get the how
			my $offset = index($line, '{', 0);
			# Is there a better way to do this?
			while (-1 != ($offset = index($line, '{', $offset)))
			{
				# now descend and check for };
				$descent++ ;
				$descent-- if (-1 != ($offset = index($line, '};', $offset)));
				$offset++;
			}
			push(@data, $hold_line.'|-|'.$orig);
		}
		elsif ( ($line =~ m/$de_start/) && (1 == $block) )
		{
			$descent++;
			push(@data, $hold_line.'|-|'.$orig);
		}
		elsif ( ($line =~ m/^$de_end$/) && (1 == $block) )
		{	
			$descent--;
			if (0 == $descent)
			{
				$block = 0;
				push(@data, $hold_line.'|-|'.$orig);
				push(@data, $hold_end."\n") if ($hold_end);
				next;
			}
			else
			{
				push(@data, $hold_line.'|-|'.$orig);
				push(@data, $hold_end."\n") if ($hold_end);
			}
		}
		elsif ( ($line =~ m/^$re_end$/) && (1 == $block) )
		{
			$block = 0;
			push(@data, $hold_line.'|-|'.$orig);
			push(@data, $hold_end."\n") if ($hold_end);
			next;
		}
		elsif (1 == $block)
		{
			push(@data, $hold_line.'|-|'.$orig);
		}
		push(@data, $orig) if (0 == $block);
		
	} # close loop
	close($fh);

	if ( ($save) && (1 == $save) )
	{
		# Hopefully no other processes are using it (There could be a better way
		# for doing this)
		return(1) if (-1 == $self->_file_create("$file.tmp", join('', @data)));
		
		if (-1 == rename("$file.tmp", $file))
		{
			$self->_set_error("Couldn't rename temp file to ($file): $!.");
			return(1);
		}
	}
	
	print @data if ( ($self->{'debug'}) && (1 == $self->{'debug'}) );
} #_hold

# This really shouldn't be global since the user module does it differently
# (TODO: rename to _list_domains)

=item B<_list>

  Title    : _delete
  Usage    : $self->_delete('domain.com', 'apache.conf', 0);
  Function : Locates the block of data based on $needle and removes it from
             $file.
  Returns  : 0 on failure, an array (count, a hash)
  Args     : $files : A comma delimited list of files to search.
             $searc : The file to search.

=cut

sub _list($$)
{
	my ($self, @args) = @_;
	$self->{'log'}->{'args'}   = \@args;
	$self->{'log'}->{'action'} = 'list';
	my ($file_list, $search) = @args;
	my $block = 0;
	$search = '.*'          if (!$search);
	$search = '^' . $search if ($search);

	my ($fh, %list);

	my $re_start = $self->{'config'}->{'regex-list'};
	$re_start    = $self->_regex_transform($re_start);
	my $lineno = 0;
	if ($file_list =~ m/,/)
	{
		$file_list =~ s/\s//gi;
	}
	elsif ( ($file_list eq 'all') || (!$file_list) )
	{
		$file_list = $self->{'config'}->{'config-files'};
	}

	$list{'size'}{'fsize'} = 4;
	$list{'size'}{'3size'} = 0;
	$list{'size'}{'4size'} = 0;
	$list{'size'}{'5size'} = 0;
		
	my @files = split(',',$file_list);
	my $count = 0;
	foreach my $t (@files)
	{
		next if (!$t);
		my $file = $self->{'config'}->{$t.'-conf-file'};
		$file = $self->make_path($file,$t,1);
		next if (!$file);
		if ( -e $file )
		{
			open($fh, $file) or $block = -1;
			if (-1 == $block)
			{
				$self->_set_error("Couldn't open ($file). $!");
				return(0);
			}
			while(my $line = <$fh>)
			{
				if ($line =~ m/$re_start/i)
				{
					my $found = $2;
					my ($f3, $f4, $f5);
					if ($3)
					{
						$list{'size'}{'3size'} = length($3)
						  if (length($3) > $list{'size'}{'3size'});
						$f3 = $3; 
					}
					if ($4)
					{
						$list{'size'}{'4size'} = length($4)
						  if (length($4) > $list{'size'}{'4size'});
						$f4 = $4;
					}
					if ($5)
					{
						$list{'size'}{'5size'} = length($5)
						  if (length($5) > $list{'size'}{'5size'});
						$f5 = $5;
					}
					if ($found =~ m/$search/i)
					{
						$list{'size'}{'fsize'} = length($found)
						  if (length($found) > $list{'size'}{'fsize'});
						# check if the domain is held
						$list{"$found"}{'held'} = 0;
						$list{"$found"}{'type'} = $t;
						$list{"$found"}{'f3'} = $f3 if ($f3);
						$list{"$found"}{'f4'} = $f4 if ($f4);
						$list{"$found"}{'f5'} = $f5 if ($f5);
						$list{"$found"}{'held'} = 1
						  if ($line=~ m/\|\-\|(.*?)$re_start/i);
						$count++;
					}
				}
			}
			close($fh);
		}
		else
		{
			$self->_set_error("Couldn't open ($file). No such file or directory");
			return(0);
		}
	}

	return ($count, %list);
} #_list

=item B<_unhold>

  Title    : _unhold
  Usage    : $self->_unhold('domain.com', 'apache.conf', 1);
  Function : Locates the block of data based on $needle and 'unholds' it from
             $file.
  Returns  : -1 on failure, 0 otherwise
  Args     : $needle      : The replacement in the regular expressions.
             $file        : The file to modify.
             $hold_escape : Whether or not to escape the hold regex.
             $save        : Whether or not to save the file. [optional]

=cut

sub _unhold($$$;$)
{
	my ($self, $needle, $file, $hold_escape, $save) = @_;
	my $fh;
	
	$hold_escape = 0 if (!$hold_escape);
	
	my ($hold_line, $hold_begin, $hold_end)
	    = $self->_get_hold_style($hold_escape);
	my ($re_start, $de_start, $de_end, $re_end)
	    = $self->_get_regex_descent($needle);
	my $descent = my $block = my $lineno = 0;
	my @data;	# Where are we adding the directives
	
	open($fh, "$file");
	if (-1 == $block)
	{
		$self->_set_error("Couldn't open ($file). $!");
		return(-1);
	}
	while(my $line = <$fh>)
	{
		$lineno++;
		my $orig = $line;

		# trim any whitespace fore/aft of the string, and reduce multiple white-
		# space to single whitespace
		chomp($line);
		$line =~ s/(^\s+|\s+$)//g;
		$line =~ s/\s+/ /g;
		
		# Since the default apache hold style is #
		# this gets rather tricky since we allow preline comments
		if ($hold_begin && $hold_end)
		{
			if ($line =~ m/^$hold_begin/)
			{
				# we need to get the next line
				my $l = <$fh>;
				if ($l =~ m/^$hold_line\|\-\|\s?$re_start/)
				{
					$l =~ s/^$hold_line\|\-\|//;
					push(@data, $l);
					$block = 1;
					next;
				}
				push(@data, $orig);
				push(@data, $l);
				next
			}
			elsif ( ($line =~ m/^$hold_end/) && (1 == $block) )
			{
				$block = 0;
				next;
			}
		} # the case that "* /* */"
		else
		{
			# This is the PITA because we have to do what we did in del/hold
			# to find the right amount of comments to uncomment
			if ($line =~ m/^$hold_line\|\-\|\s?$re_start/i)
			{
				$block   = 1;
				$descent = 1;
			}
			elsif ( ($line =~ m/$hold_line\|\-\|.*?\{/i) 
			     && ($line =~ m/$hold_line\|\-\|.*?\}\;/) 
			     && (1 == $block) )
			{
				# There is a single line {}; bracket pair (at least one anyway)
				# Get the how
				my $offset = index($line, '{', 0);
				# Is there a better way to do this?
				while (-1 != ($offset = index($line, '{', $offset)))
				{
					# now descend and check for };
					$descent++ ;
					$descent-- if (-1 != ($offset = index($line, '};', $offset)));
					$offset++;
				}
			}
			elsif ( ($line =~ m/$hold_line\|\-\|.*?$de_start/) && (1 == $block) )
			{
				$descent++;
			}
			elsif ( ($line =~ m/^$hold_line\|\-\|$de_end$/) && (1 == $block) )
			{	
				$descent--;
				if (0 == $descent)
				{
					$block = 0;
					next;
				}
			}
			elsif ( ($line =~ m/^$hold_line\|\-\|$re_end$/) && (1 == $block) )
			{
				$orig =~ s/^$hold_line\|\-\|//;
				push(@data, $orig);
				$block = 0;
				next;			
			}
		} # the case that "//" or "#" or ";" or "|" (I think anyway)

		if (1 == $block)
		{
			# trim the $hold_line and the |-| off of it
			$orig =~ s/^$hold_line\|\-\|//;
			push(@data, $orig);
		}

		# we push all data along unless the above doesn't want us to?
		push(@data, $orig) if (1 != $block);
		my $prev = $orig;		
	} # close loop
	close($fh);

	if ( ($save) && (1 == $save) )
	{
		# Hopefully no other processes are using it (There could be a better way
		# for doing this)
		return(1) if (-1 == $self->_file_create("$file.tmp", join('', @data)));
		
		if (-1 == rename("$file.tmp", $file))
		{
			$self->_set_error("Couldn't rename temp file to ($file): $!.");
			return(1);
		}
	}
	
	print @data if ( ($self->{'debug'}) && (1 == $self->{'debug'}) );
} #_unhold

=item B<_update>

  Title    : _update
  Usage    : $self->_update('domain.com', 'apache.conf', 0);
  Function : Locates the block of data based on $needle and removes it from
             $file.
  Returns  : -1 on failure, 0 otherwise
  Args     : $needle  : The replacement in the regular expressions.
             $file    : The file to remove data from.
             $op      : The action that is being performed.
             $op_line : The line to work on
             $save    : Whether or not to save the file. [optional]

=cut

sub _update($$$$;$)
{
	my ($self, $needle, $file, $op, $op_line, $save) = @_;
	my $fh;
	
	return(-1) if (!$op && !$op_line);
	
	my ($hold_line, $hold_begin, $hold_end)
	    = $self->_get_hold_style(1);
	my ($re_start, $de_start, $de_end, $re_end)
	    = $self->_get_regex_descent($needle);
	my $descent = my $block = my $lineno = my $skip = 0;
	my @data;	# Where are we adding the directives

	# we actually need to break up the data, which means that the file will
	# have to be searched multiple times for those lines to make sure that we get
	# everything we want
	
	open($fh, "$file") or $block = -1;
	if (-1 == $block)
	{
		$self->_set_error("Couldn't open ($file). $!");
		return(-1);
	}
	while(my $line = <$fh>)
	{
		$skip = 0;
		$lineno++;
		my $orig = $line;
		# trim any whitespace fore/aft of the string, and reduce multiple white-
		# space to single whitespace
		chomp($line);
		$line =~ s/(^\s+|\s+$)//g;
		$line =~ s/\s+/ /g;
		if ($line =~ m/^$re_start/i)
		{
			$block = 1;
		}
		elsif ( ($line =~ m/^$re_end$/) && (1 == $block) && ('add' eq $op) )
		{
			push(@data, $op_line);
			$block = 0;
		} # this only works for add
		elsif ( (1 == $block) && ('del' eq $op) )
		{
			my @split = split("\n", $op_line);
			foreach my $l (@split)
			{
				$l =~ s/^\s*//;
				if ($line =~ m/$l/i)
				{
					$skip = 1;
					last; # we only want to go to this line on this line
				}
			}
		} # del
		elsif ( (1 == $block) && ('hold' eq $op) )
		{
			my @split = split("\n", $op_line);
			foreach my $l (@split)
			{
				$l =~ s/^\s*//;
				if ($line =~ m/$l/si)
				{
					$orig = $hold_line.'|-|'.$orig;
					last; # we only want to go to this line on this line
				}
			}
		} # hold
		elsif ( (1 == $block) && ('unhold' eq $op) )
		{
			my @split = split("\n", $op_line);
			foreach my $l (@split)
			{
				$l =~ s/^\s*//;
				if ($line =~ m/$hold_line\|\-\|.*?$l/i)
				{
					$orig =~ s/^$hold_line\|\-\|//;
					last; # we only want to go to this line on this line
				}
			}
		} #unhold
		push(@data, $orig) if (0 == $skip);
		
	} # close loop
	close($fh);
	
	if ( ($save) && (1 == $save) )
	{
		# Hopefully no other processes are using it (There could be a better way
		# for doing this)
		return(1) if (-1 == $self->_file_create("$file.tmp", join('', @data)));
		
		if (-1 == rename("$file.tmp", $file))
		{
			$self->_set_error("Couldn't rename temp file to ($file): $!.");
			return(1);
		}
	}
	
	print @data if ( ($self->{'debug'}) && (1 == $self->{'debug'}) );
} #_update

=item B<Globals>

=item B<term_clear>

  Title    : term_clear
  Usage    : $self->term_clear();
             or
             $obj->term_clear();
  Function : Prints a 'reset' command to the terminal to clear any leaked
             color codes from other print commands.
  Returns  :
  Args     : none

=cut

sub term_clear()
{
	print color('reset');
} #term_clear

=item B<Aliases>

=item B<delete>

  Title    : delete
  Usage    : $obj->delete(@args);
  Function : An alias for the $obj->del function
  Returns  : an object
  Args     : @args : an array that will be passed on to $obj->delete

=cut

sub delete
{
	my ($self, @args) = @_;
	return($self->del(@args));
} #delete

=item B<Stub Methods>

These stubs should be filled in by the sub-classes.

=item B<add>

  Title    : add
  Usage    : $self->add(@args)
  Function : Performs an add action and returns itself.
  Returns  : an object
  Args     : @args : an array of the arguments to the function
                     generally including:
                     -data : The user/domain/etc to add

=cut

sub add
{
	my($self, @args) = @_;
	return($self);
} #add

=item B<ask_action>

  Title    : ask_action
  Usage    : $self->ask_action('add', @args);
  Function : Asks the user whether or not it should run its $action.
  Returns  : an object
  Args     : $action : The action to be performed.
             @args   : An array that is passed into the action.

=cut

sub ask_action($@)
{
	my ($self, $action, @args) = @_;
	return($self);
} #ask_action

=item B<del>

  Title    : del
  Usage    : $self->del(@args)
  Function : Performs a delete action and returns itself.
  Returns  : an object
  Args     : @args : an array of the arguments to the function
                     generally including:
                     -data : The user/domain/etc to delete

=cut

sub del
{
	my($self, @args) = @_;
	return($self);
} #del

=item B<edit>

  Title    : edit
  Usage    : $self->edit(@args);
  Function : Performs an unhold action and returns itself.
  Returns  : an object
  Args     : @args : an array of the arguments to the function
                     generally including:
                     -data : The user/domain/etc to edit

=cut

sub edit
{
	my($self, @args) = @_;
	return($self);
} #edit

=item B<extra_type_checks>

  Title    : extra_type_checks
  Usage    : $self->extra_type_checks($type);
  Function : Performs extra checks on the input type that might want to be
             run before performing the $action.
  Returns  : 1 on failure, 0 on success
  Args     : $string : The string to run the checks on.
             $action : The action that will be performed if the checks pass.
             $exists : Whether the type exists.
             $held   : Whether the type is on hold.

=cut

sub extra_type_checks($$$$)
{
	my ($self, $s, $a, $e, $h) = @_;

	return(0);
} #extra_type_checks

=item B<get_password>

  Title    : get_password
  Usage    : $self->get_password();
  Function : Returns the password.
  Returns  : aa string
  Args     : $user : The username.

=cut

sub get_password($)
{
	my ($self, $user) = @_;
	my ($password, $display_pass, $use_random);

	# Determine if passwords are going to be used.
	if ($self->_is_enabled(
	    ('ask' eq $self->{'config'}->{'use-password'}) ? 
	      $self->_get_yesno("Use password-based authentication?", 
	        $self->{'config'}->{'password-use'}) :
	      $self->{'config'}->{'password-use'}
	    )
	   )
#	if ('yes' eq lc($self->get_use_password()))
	{
		# Use an empty password.
		if ($self->_is_enabled(
		    $self->_get_yesno("Use an empty password? (yes/no)", 
		      $self->{'config'}->{'password-empty'}))
		   )
#		if ('yes' eq $self->get_use_empty())
		{
			$password = '';
			$display_pass = '<none>';
		}
		# Use a random password
		elsif ($self->_is_enabled(
		       $self->_get_yesno("Use a random password? (yes/no)",
		         $self->{'config'}->{'password-random'}))
		      )
#		elsif ('yes' eq $use_random)
		{
			$password = $self->_generate_password();
			$use_random = 1;
			$display_pass = $password;
		}
		# Obtain a valid password from the user
		else
		{
			my $error = 0;
			do
			{
				$password = $self->_get_password();
				$self->_print_error()
				  if ($error = $self->_check_password($password, $user));
			} while ($error);
			$display_pass = '*****';
		}
	}
	# Password has been disabled
	else
	{
		$display_pass = '<disabled>';
	}

	$use_random = 0 if (!$use_random);

	return($password, $display_pass, $use_random);
} #get_password

=item B<hold>

  Title    : hold
  Usage    : $self->hold(@args)
  Function : Performs a hold action and returns itself.
  Returns  : an object
  Args     : @args : an array of the arguments to the function
                     generally including:
                     -data : The user/domain/etc to hold

=cut

sub hold
{
	my($self, @args) = @_;
	return($self);
} #hold

=item B<list>

  Title    : list
  Usage    : $self->list(@args)
  Function : Performs a list action and returns itself.
  Returns  : an object
  Args     : @args : an array of the arguments to the function
                     generally including:
                     -search : The word to search for

=cut

sub list
{
	my($self, @args) = @_;
	return($self);
} #list

=item B<make_path>

  Title    : make_path
  Usage    : $self->make_path();
  Function : 
  Returns  : 
  Args     : $path     : The path.
             $to       : Where the path is going.
             $absolute : Whether or not the path should be absolute. [optional]
                         Defaults to 0.

=cut

sub make_path($$;$)
{
	my ($self, $path, $to, $absolute) = @_;
	my $_path = '';
	$to       = '' if (!$to);
	$absolute = 0  if (!$absolute);

	return($path) if ($path =~ m/^\//i);

	# we only have two types of paths zones (main,%zone_type%)
	if ('main' ne $to)
	{
		# main may be absolute at which point base MUST be absolute
		if ($self->{'config'}->{'directory-main'} !~ m/^\//)
		{
			if ( (!$self->{'config'}->{'directory-base'})
			  && ($self->{'config'}->{'directory-base'} !~ m/^\//)
			   )
			{
				$self->_set_error("directory-base in the generic config must be exist and be absolute.");
				return($self) if ($self->_print_error());
			}
			$_path = $self->{'config'}->{'directory-base'} . '/' .
				$self->{'config'}->{'directory-main'}
		}
		else
		{
			$_path = $self->{'config'}->{'directory-main'};
		}
	}

	if ($self->{'zone_type'})
	{
		my $zone_dir = $self->{'zone_type'}.'-directory';

		if ( $self->{'zone_type'} && ($self->{'config'}->{$zone_dir}) )
		{
			my $zdir = $self->{'config'}->{$zone_dir};
			# type-directory must exist in the config
			$self->_die_print("$zone_dir must exist in the config.") # make_path (if main)
			  if ( (!$zdir) && ($self->{'main'}) );
			if ($path !~ m/$zdir/)
			{
				$_path = ($_path ? $_path . '/' : '') . $zdir;
			}
		}
	}

    if ($self->_is_enabled($self->{'config'}->{'is-jail'})) {
        return $self->{'config'}->{'jail-path'}.'/'.$_path.'/'.$path;
    }

	return($_path.'/'.$path);
} #make_path

=item B<type_exists>

  Title    : type_exists
  Usage    : my ($t, $h)
  Function : Returns an array which notifies of the type's existence and then
             notifies if the type is on hold.
  Returns  : an array(integer, integer)
  Args     : $type : The type to check existence for.

=cut

sub type_exists()
{
	my ($self, $type) = @_;
	return(1, 1);
} #type_exists

=item B<unhold>

  Title    : unhold
  Usage    : $self->unhold(@args)
  Function : Performs an unhold action and returns itself.
  Returns  : an object
  Args     : @args : an array of the arguments to the function
                     generally including:
                     -data : The user/domain/etc to unhold

=cut

sub unhold
{
	my($self, @args) = @_;
	return($self);
} #unhold

=item B<usage>

  Title    : usage
  Usage    : $obj->usage()
  Function : Prints out the usage for the module
  Returns  : 
  Args     : none

=cut

sub usage
{
	print "Usage: service_setup [qn] <dns|web|mail|domain> <add|delete|hold|unhold> [options]\n";
	print "  -q		Quiet\n";
	print "  -f 	Configuration File\n";
	print "\n";
	term_clear();
	exit(1); # usage
}

=item B<valid_actions>

  Title    : valid_actions
  Usage    : @actions = $obj->valid_actions();
  Function : Returns a list of the currently valid actions that the module
             performs.
  Returns  : an array
  Args     : none

=cut

sub valid_actions()
{
	my ($self) = @_;
	
	$actions = $self->{'actions'};

	return($actions);
} #valid_actions


=item B<Depreciated>

I would like to know who first used deprecated to describe obsolete 
functions, it is a weird word that doesn't sound right when used, and
these functions have depreciated in their value!

=item B<domain_exists>

  Title    : domain_exists
  Usage    : my ($t, $h) = $obj->domain_exists();
  Function : Returns an array which notifies of the type's existence and then
             notifies if the type is on hold.
  Returns  : an array(string, integer)
  Args     : $domain : The domain to check existence for.

=cut

sub domain_exists($)
{
	my ($self, $domain) = @_;
	return($self->type_exists($domain));
} #domain_exists

=item B<_get_domain>

  Title    : _get_domain
  Usage    : $self->_get_domain('example.com');
  Function : Gets a domain from the user using $domain as the default by
             calling $self->_get_valid_input.
  Returns  : a string
  Args     : $domain : The domain name to use as default.
             $type     : The module type under base_type. [optional]

=cut

sub _get_domain($)
{
	# NOTE: This is kept around for backward compatibility with the earlier
	# modules, and as a quick alias to get it.
	my ($self, $domain, $type) = @_;
	return($self->_get_valid_input($domain, $type));
} #_get_domain

=item B<_get_user>

  Title    : _get_user
  Usage    : $self->_get_user('test_user');
  Function : Gets a username from the user using $username as the default by
             calling $self->_get_valid_input.
  Returns  : a string
  Args     : $username : The username to use as default.
             $type     : The module type under base_type. [optional]

=cut

sub _get_user($)
{
	my ($self, $user, $type) = @_;
	$user = $self->_get_input_with_check('Enter username',
	  'Invalid username.', 0, $user,
	  $self->{'config'}->{'regex-user'});
	return($user);
} #_get_user

=item B<user_exists>

  Title    : user_exists
  Usage    : my ($t, $h) = $obj->user_exists();
  Function : Returns an array which notifies of the type's existence and then
             notifies if the type is on hold.
  Returns  : an array(string, integer)
  Args     : $user : The user to check existence for.

=cut

sub user_exists($)
{
	my ($self, $user) = @_;
	return($self->type_exists($user));
} #user_exists

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
bug reports, please provide the version of SystemConfig.pm, the version of Perl,
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
