package Cennel::Process::RunAction;
use strict;
use warnings;
use File::Temp;
use Path::Tiny;
use AnyEvent;
use AnyEvent::Util qw(run_cmd);

sub new_from_def ($$) {
  return bless {def => $_[1]}, $_[0];
} # new_from_def

sub git ($;$) {
  return defined $_[0]->{def}->{git_path} ? $_[0]->{def}->{git_path} : 'git';
} # git

sub git_url ($) {
  return $_[0]->{def}->{git_url};
} # git_url

sub git_branch ($) {
  return defined $_[0]->{def}->{git_branch} ? $_[0]->{def}->{git_branch} : 'master';
} # git_branch

sub git_revision ($) {
  return $_[0]->{def}->{git_revision};
} # git_revision

sub cin_role ($) {
  return $_[0]->{def}->{cinnamon_role};
} # cin_role

sub cin_task ($) {
  return $_[0]->{def}->{cinnamon_task};
} # cin_task

sub temp_repo_path ($) {
  return $_[0]->{temp_repo_path} ||= do {
    $_[0]->{temp_dir} = File::Temp->newdir;
    path ($_[0]->{temp_dir} . '');
  };
} # temp_repo_path

sub onlog ($;$) {
  if (@_ > 1) {
    $_[0]->{onlog} = $_[1];
  }
  return $_[0]->{onlog} ||= sub {
    my ($msg, %args) = @_;
    warn "[@{[$args{channel} || '']}] $msg\n" if defined $msg;
  };
} # onload

sub log ($$%) {
  my $self = shift;
  $self->onlog->(@_);
} # log

sub git_clone_as_cv ($) {
  my $self = $_[0];
  my $cv = AE::cv;
  my $cmd = [$self->git, 'clone', '--depth', 20, '--branch', $self->git_branch, $self->git_url, $self->temp_repo_path];
  $self->log ((join ' ', '$', @$cmd), class => 'command');
  my $stderr = '';
  run_cmd (
    $cmd,
    '<' => \'',
    '>' => sub { $self->log ($_[0], channel => 'stdout') },
    '2>' => sub { $stderr .= $_[0] if defined $_[0]; $self->log ($_[0], channel => 'stderr') },
  )->cb (sub {
    my $result = {error => ($_[0]->recv >> 8) != 0};
    if ($stderr =~ /^warning: Remote branch \Q@{[$self->git_branch]}\E not found in upstream origin, using HEAD instead$/m) {
      $result->{error} = 1;
    }
    if ($result->{error} or not defined $self->git_revision) {
      $cv->send ($result);
    } else {
      my $cmd = [$self->git, 'checkout', $self->git_revision];
      $self->log ((join ' ', '$', @$cmd), class => 'command');
      my $cd = $self->temp_repo_path;
      run_cmd (
        "cd \Q$cd\E && " . (join ' ', map { quotemeta $_ } @$cmd),
        '<' => \'',
        '>' => sub { $self->log ($_[0], channel => 'stdout') },
        '2>' => sub { $self->log ($_[0], channel => 'stderr') },
      )->cb (sub {
        $cv->send ({error => ($_[0]->recv >> 8) != 0});
      });
    }
  });
  return $cv;
} # git_clone_as_cv

my $CinPath = path (__FILE__)->parent->parent->parent->parent->child ('cin')->absolute;

sub cin_as_cv ($) {
  my ($self) = @_;
  my $cv = AE::cv;
  my $cd = $self->temp_repo_path;
  my $cmd = [$CinPath, $self->cin_role, $self->cin_task];
  $self->log ((join ' ', '$', @$cmd), class => 'command');
  run_cmd (
    "cd \Q$cd\E && " . (join ' ', map { quotemeta $_ } @$cmd),
    '<' => \'',
    '>' => sub { $self->log ($_[0], channel => 'stdout') },
    '2>' => sub { $self->log ($_[0], channel => 'stderr') },
  )->cb (sub {
    $cv->send ({error => ($_[0]->recv >> 8) != 0});
  });
  return $cv;
} # cin_as_cv

sub docker_restart_as_cv ($) {
  my $self = $_[0];
  my $def = $self->{def};

  my $run = sub {
    my $cmd = $_[0];
    $self->log ((join ' ', '$', @$cmd), class => 'command');
    my $cv = AE::cv;
    run_cmd (
      $cmd,
      '<' => \'',
      '>' => sub { $self->log ($_[0], channel => 'stdout') },
      '2>' => sub { $self->log ($_[0], channel => 'stderr') },
    )->cb (sub {
      $cv->send ({error => ($_[0]->recv >> 8) != 0});
    });
    return $cv;
  }; # $run

  my $cv = AE::cv;
  my $name = 'cennel-' . $def->{docker_image};
  $name =~ s{/}{-};
  $run->(['docker', 'pull', $def->{docker_image}])->cb (sub {
    $run->(['docker', 'stop', $name])->cb (sub {
      $run->(['docker', 'rm', $name])->cb (sub {
        $run->(['docker', 'run', '-d', '--name=' . $name, '--restart=always', "-p=$def->{docker_ext_port}:$def->{docker_int_port}", $def->{docker_image}, $def->{docker_command}])->cb (sub {
          $cv->send ($_[0]->recv);
        });
      });
    });
  });
  return $cv;
} # docker_restart_as_cv

sub run_as_cv ($) {
  my ($self) = @_;

  if (defined $self->{def}->{docker_command}) {
    return $self->docker_restart_as_cv;
  }

  my $cv = AE::cv;
  $self->git_clone_as_cv->cb (sub {
    my $result = $_[0]->recv;
    unless ($result->{error}) {
      $self->cin_as_cv->cb (sub {
        my $result = $_[0]->recv;
        unless ($result->{error}) {
          $cv->send ({});
        } else {
          $cv->send ($result);
        }
      });
    } else {
      $cv->send ($result);
    }
  });

  return $cv;
} # run_as_cv

1;

=head1 LICENSE

Copyright 2014 Wakaba <wakaba@suikawiki.org>.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
