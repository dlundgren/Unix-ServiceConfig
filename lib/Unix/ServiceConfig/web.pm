######################################################################
#
# Unix/ServiceConfig/dns.pm
#
# Copyright (C) 2006-2014 David Lundgren. All Rights Reserved
#
# MIT License
#
######################################################################

package Unix::ServiceConfig::web;

no warnings 'portable';
use 5.6.0;
use strict;
use warnings;

use vars qw(@ISA);

use Term::ScreenColor;
use Unix::ServiceConfig;
@ISA = qw(Unix::ServiceConfig);

my $VERSION   = '0.02';
my $REVISION  = sprintf("%d.%02d", q$Revision: 1.2 $ =~ /(\d+)\.(\d+)/);

=item B<_make_log_directory>

  Title    : _make_log_directory
  Usage    : $self->_make_log_directory();
  Function : Makes sure that the log directory exists
  Returns  : an object
  Args     : $dir : The directory to create.
             $uid : The user that owns the directory.
             $gid : The gid that owns the directory.

=cut

sub _make_log_directory($)
{
	my ($self, $dir, $uid, $gid) = @_;
	my ($user, @u);

	$uid = $self->{'config'}-{'default-uid'} if (!$uid);
	if ($uid !~ m/^[0-9]*$/)
	{
		@u    = getpwnam($uid) if ($uid !~ m/^[0-9]*$/);
		$uid  = $u[2];
		$user = $u[7];
		$user = $self->_path_clean_chroot($user);
	} # make sure that uid is numeric
	if (!$gid)
	{
		@u   = getpwuid($uid);
		$gid = $u[3]                             if (-1 != $#u);
		$gid = $self->{'config'}-{'default-gid'} if (-1 == $#u);
	} # get the gid if it isn't set

	if (-e $dir)
	{
		my @s = stat($dir);
		chown($uid, -1, $dir) if ($s[4] != $uid);
		chown(-1, $gid, $dir) if ($s[5] != $gid);
		chmod(oct('0755'), $dir);
	} # make sure the permissions are set for it
	else
	{
		my $mode = '0755';
		if (!mkdir($dir, oct($mode)))
		{
			my @d = split('/', $dir);
			my $di = '';
			my $d_uid = $self->{'config'}->{'root-uid'};
			my $d_gid = $self->{'config'}->{'root-gid'};
			foreach my $i (@d)
			{
				$di = $di.'/'.$i;
				$di =~ s/\/\//\//gi;
				if ("$di/" eq $user)
				{
					$d_uid = $uid;
					$d_gid = $gid;
				} # if the directoy is below the users then they can own it
				next if (-e $di);
				mkdir($di, oct($mode));
				chmod(oct($mode), $di); 
				chown(int($d_uid),
				      int($d_gid),
				      $di);
			}
		} # make the prior directories
		chmod(oct($mode), $dir);
		chown(int($uid), int($gid), $dir);
	} # make the directory

	return(0);
} # _make_log_directory

=item B<check_location>

  Title    : check_location
  Usage    : $self->check_location();
  Function : Returns a valid directory for the domain to be added to.
  Returns  : a string
  Args     : $location : The username.
             $type     : domain
             $user_dir : The user directory. [optional]

=cut

sub check_location($$;$)
{
	my ($self, $location, $type, $user_dir) = @_;
	my ($dir, $user);
	$type     = 'data'       if (!$type);
	$user_dir = '%location%' if (!$user_dir);

	$location = $self->_get_input_with_check(
		  "Logs location", 
		  "Invalid username or directory",
		  1, '', '.*', 'username or directory') if (!$location);

	# there is no need to ask further questions if it is absolute
	if ($location !~ m/^\//)
	{
		# see if the user exists first
		$user     = $location;
		$user     =~ s/([^\/]*).*/$1/i;
		$location =~ s/$user//g;

		# check if the user actually exists
		my @user = getpwnam($user);
		my $home = $self->_path_clean_chroot($user[7]);
#		$answer = $self->_get_yesno("Use $home", 'y', 1);

		if (-1 == $#user)
		{
			$self->_error("Invalid user ($user)");
			return($self->check_location('', $type, $user_dir));
		}

		$user[7]  =~ s/\/$//;
		if ($self->_is_enabled($self->{'config'}->{'use-chroot'}))
		{
			my $chroot = $self->{'config'}->{'directory-chroot'};
			$user_dir =~ s/^$chroot//i;
		}
		$user_dir =~ s/\%location\%/$user[7]/i;
		$user_dir =~ s/\/$//;
		$dir      =  $user_dir.'/'.$location;
		$user_dir = $user[7].'/';
	}
	# this was an absolute location.
	else
	{
		$dir      = $location;
		$user     = '';
		$user_dir = $self->{'config'}->{'directory-base-logs'};
	}

	$user_dir = $self->_path_clean_chroot($user_dir);

	$dir = $self->_path_clean_chroot($dir);
	$dir = $self->_path_clean_variables($dir);

	return($dir, $user, $user_dir) if (-d $dir);
	return($dir, $user, $user_dir) if (!$self->_ask_to_create_directory($dir, 'root','',1));

	# Keep recursing until they get it right
	$self->_error("Invalid directory ($dir)\n");
	return($self->check_location($location, $type, $user_dir));
} #check_location

1;

__END__
